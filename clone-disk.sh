#!/usr/bin/env bash
#
# Copyright (c) 2025 Marc Backes
# Alle Rechte vorbehalten.
#
# clone_disk.sh - Interaktives Skript zum Klonen einer Festplatte
#                       Wahlweise Speichern: lokal, per SSH oder auf gemountetem Netzwerkshare
#                       Bei Netzwerkshare kann ein entfernte Freigabe automatisch gemountet werden.
#                       Kein externes Tool erforderlich, Auswahl des Ausgabeformats, Basis-Dateinamens und Zeitstempel.

set -euo pipefail

# Fehlerfunktion
err() { echo "Fehler: $*" >&2; exit 1; }

# 1. Prüfen: Skript muss in Bash laufen
type bash >/dev/null 2>&1 || err "Bash nicht gefunden."

# 2. Prüfen auf qemu-img für qcow2-Option
if command -v qemu-img >/dev/null 2>&1; then
  HAVE_QEMU=true
else
  HAVE_QEMU=false
fi

# 3. Quellgerät mit Bash 'select' wählen
mapfile -t DEVS < <(lsblk -dn -o NAME,SIZE | awk '{print "/dev/"$1" – "$2}')
echo "Verfügbare Blockgeräte:"
PS3="Quellgerät wählen (Nummer): "
select DEV_LINE in "${DEVS[@]}"; do
  [[ -n "$DEV_LINE" ]] || { echo "Ungültige Auswahl."; continue; }
  SRC_DEV=${DEV_LINE%% – *}
  break
done

# 4. Speichertyp mit select
OPTIONS=(Lokal SSH Netzwerkshare)
PS3="Speichertyp wählen (Nummer): "
select TARGET_TYPE in "${OPTIONS[@]}"; do
  [[ -n "$TARGET_TYPE" ]] || { echo "Ungültige Auswahl."; continue; }
  break
done

# 5. Ziel-Verzeichnis bzw. Mount konfigurieren
case "$TARGET_TYPE" in
  Lokal)
    read -rp "Ziel-Verzeichnis [ /tmp ]: " TARGET_DIR
    TARGET_DIR=${TARGET_DIR:-/tmp}
    ;;
  SSH)
    read -rp "SSH-Ziel-Verzeichnis (user@host:/pfad): " SSH_DEST_DIR
    ;;
  Netzwerkshare)
    # Protokollauswahl für Netzwerkshare
    echo
    echo "Freigabe-Protokoll wählen:"
    echo "1) NFS"
    echo "2) CIFS/SMB"
    read -rp "Option (1-2): " proto_opt
    case "$proto_opt" in
      1) PROTO="nfs";;
      2) PROTO="cifs";;
      *) echo "Ungültige Auswahl, verwende NFS."; PROTO="nfs";;
    esac
    
    # Eingabe der Freigabe und Mount-Punkt
    read -rp "Freigabe ($PROTO: server:/pfad oder //server/share): " REMOTE_SHARE
    read -rp "Lokaler Mount-Punkt [ /mnt/backup ]: " MOUNT_POINT
    MOUNT_POINT=${MOUNT_POINT:-/mnt/backup}
    mkdir -p "$MOUNT_POINT"

    if [[ "$PROTO" == "nfs" ]]; then
      sudo mount -t nfs "$REMOTE_SHARE" "$MOUNT_POINT" || err "NFS-Mount fehlgeschlagen."
    else
      # CIFS: Benutzername/Passwort abfragen
      read -rp "CIFS Benutzername: " CIFS_USER
      read -srp "CIFS Passwort: " CIFS_PASS; echo
      sudo mount -t cifs "$REMOTE_SHARE" "$MOUNT_POINT" \
        -o username="$CIFS_USER",password="$CIFS_PASS",rw || err "CIFS-Mount fehlgeschlagen."
    fi
    TARGET_DIR="$MOUNT_POINT"
    ;;
esac

# 6. Blockgröße wählen Blockgröße wählen
echo
echo "Blockgrößen (Standard 1M für ~4GB RAM):"
echo "1) 512K (niedriger Speicherbedarf)"
echo "2) 1M   (ausgewogen)"
echo "3) 4M   (schneller, viel RAM)"
read -rp "Blockgröße wählen (1-3): " bs_opt
case "$bs_opt" in
  1) BS=512K;;
  3) BS=4M;;
  *) BS=1M;;
esac

# 7. Ausgabeformat wählen
echo
echo "Ausgabeformat wählen:"
echo "1) raw.gz  (komprimiertes Roh-Image)"
echo "2) raw     (ungepacktes Roh-Image)"
if [[ "$HAVE_QEMU" == true ]]; then echo "3) qcow2   (QEMU Copy-On-Write)"; fi
read -rp "Format wählen (1-3): " fmt_opt
case "$fmt_opt" in
  2) FORMAT=raw;;
  3) if [[ "$HAVE_QEMU" == true ]]; then FORMAT=qcow2; else echo "qcow2 nicht verfügbar, verwende raw.gz."; FORMAT=raw.gz; fi;;
  *) FORMAT=raw.gz;;
esac

# 8. Basis-Dateiname wählen
echo
read -rp "Basis-Dateiname (ohne Extension) [linuxserver]: " base_name
base_name=${base_name:-linuxserver}

# 9. Zeitstempel erzeugen
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 10. Zusammenfassung anzeigen
echo
echo "=== Zusammenfassung ==="
echo "Quellgerät:      $SRC_DEV"
echo "Speichertyp:      $TARGET_TYPE"
case "$TARGET_TYPE" in
  Lokal|Netzwerkshare)
    echo "Ziel-Verzeichnis: $TARGET_DIR"
    ;;
  SSH)
    echo "SSH-Ziel-Dir:     $SSH_DEST_DIR"
    ;;
esac
echo "Blockgröße:       $BS"
echo "Format:           $FORMAT"
echo "Basis-Dateiname:  $base_name"
echo "Zeitstempel:      $TIMESTAMP"
read -rp "Fortfahren? (j/n): " confirm
[[ "$confirm" =~ ^[jJ] ]] || { echo "Abbruch."; exit 0; }

# 11. Finale Paths erzeugen
case "$FORMAT" in
  raw)    ext=".img";;
  qcow2)  ext=".qcow2";;
  *)      ext=".img.gz";;
esac
filename="${base_name}_${TIMESTAMP}${ext}"
if [[ "$TARGET_TYPE" == "SSH" ]]; then
  REMOTE_PATH="${SSH_DEST_DIR%/}/$filename"
else
  OUT_FINAL="${TARGET_DIR%/}/$filename"
fi

# 12. Klonvorgang starten
echo "Starte Klonvorgang: $(date)"
if [[ "$TARGET_TYPE" == "SSH" ]]; then
  dd if="$SRC_DEV" bs="$BS" status=progress | gzip | ssh "$SSH_DEST_DIR" "cat > '$filename'"
  echo "Klon abgeschlossen: $REMOTE_PATH"
else
  case "$FORMAT" in
    raw.gz)
      dd if="$SRC_DEV" bs="$BS" status=progress | gzip > "$OUT_FINAL"
      ;;
    raw)
      dd if="$SRC_DEV" bs="$BS" status=progress > "$OUT_FINAL"
      ;;
    qcow2)
      tmp="${TARGET_DIR%/}/${base_name}_${TIMESTAMP}.raw"
      dd if="$SRC_DEV" bs="$BS" status=progress > "$tmp"
      qemu-img convert -f raw -O qcow2 "$tmp" "$OUT_FINAL"
      rm -f "$tmp"
      ;;
  esac
  echo "Klon abgeschlossen: $OUT_FINAL"
fi

# 13. Abschlussmeldung
echo "Fertig: $(date)"
if [[ "$TARGET_TYPE" != "SSH" ]]; then
  size=$(stat -c '%s' "$OUT_FINAL")
  echo "Dateigröße: $(awk "BEGIN{printf \"%.2f MB\", $size/1024/1024}")"
fi
