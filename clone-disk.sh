#!/usr/bin/env bash
#
# clone_disk.sh - Interaktives Skript zum Klonen einer Festplatte
#                Wahlweise Speichern: lokal, per SSH oder auf gemountetem Netzwerkshare
#                Führt Prüfungen durch und erklärt Parameter.
#                Bei Netzwerkshare kann ein entfernte Freigabe automatisch gemountet werden.

set -euo pipefail  # Beende Skript bei Fehlern und undefined Variablen

#--- Funktionen --------------------------------------------------------------
function err() {
  echo "Fehler: $*" >&2
  exit 1
}

function check_command() {
  command -v "$1" >/dev/null 2>&1 || err "Kommando '$1' nicht gefunden."
}

function prompt_default() {
  local varname="$1"; shift
  local prompt_text="$*"
  local default_value="${!varname}"
  read -rp "$prompt_text [$default_value]: " input
  printf -v "$varname" '%s' "${input:-$default_value}"
}
#----------------------------------------------------------------------------

# 1. Root-Rechte sicherstellen
[[ $EUID -eq 0 ]] || err "Dieses Skript muss als root ausgeführt werden."

# 2. Benötigte Tools prüfen
for cmd in lsblk dd gzip df stat blockdev awk ssh mountpoint mount mkdir; do
  check_command "$cmd"
done

# 3. Blockgeräte auflisten
cat <<EOF
Verfügbare Blockgeräte:
NAME    SIZE   TYPE MODEL
EOF
lsblk -dn -o NAME,SIZE,TYPE,MODEL | awk '{printf "/dev/%-7s %-6s %-5s %s\n", $1, $2, $3, substr($0,index($0,$4))}'

echo
# 4. Quellgerät auswählen
SRC_DEV_DEFAULT=$(lsblk -dn -o NAME | awk 'NR==1{print "/dev/"$1}')
SRC_DEV="$SRC_DEV_DEFAULT"
prompt_default SRC_DEV "Quellgerät auswählen"

# 5. Speichertyp abfragen
cat <<EOF
Speicherziel wählen:
 1) Lokal (Standard)
 2) Per SSH auf entfernten Server
 3) Netzwerkshare (NFS/CIFS)
EOF
TARGET_TYPE="1"
prompt_default TARGET_TYPE "Option"

# 6. Parameter für Ziel abhängig vom Typ
case "$TARGET_TYPE" in
  2)
    # SSH-Zieldetails
    SSH_DEST_DEFAULT="user@remote-host:/pfad/zum/backup/linuxserver.img.gz"
    SSH_DEST="$SSH_DEST_DEFAULT"
    prompt_default SSH_DEST "SSH-Ziel (user@host:/pfad/datei.img.gz)"
    ;;
  3)
    # Auswahl des Protokolls für Netzwerkshare
    echo "Protokoll für Netzwerkshare wählen:"
    echo " 1) NFS"
    echo " 2) CIFS/SMB"
    PROTO_TYPE="1"
    prompt_default PROTO_TYPE "Option"
    # Gemeinsame Parameter
    MOUNT_POINT_DEFAULT="/mnt/backup"
    MOUNT_POINT="$MOUNT_POINT_DEFAULT"
    prompt_default MOUNT_POINT "Lokaler Mount-Punkt"
    mkdir -p "$MOUNT_POINT"
    if [[ "$PROTO_TYPE" == "1" ]]; then
      # NFS
      NFS_REMOTE_DEFAULT="server:/export/path"
      NFS_REMOTE="$NFS_REMOTE_DEFAULT"
      prompt_default NFS_REMOTE "NFS-Freigabe (server:/pfad)"
      echo "Mounten der NFS-Freigabe $NFS_REMOTE auf $MOUNT_POINT"
      mount -t nfs "$NFS_REMOTE" "$MOUNT_POINT"
    else
            # CIFS/SMB
      CIFS_REMOTE_DEFAULT="//server/share"
      CIFS_REMOTE="$CIFS_REMOTE_DEFAULT"
      prompt_default CIFS_REMOTE "CIFS-Freigabe (//server/share)"
      # Credentials abfragen
      read -rp "CIFS Username: " CIFS_USER
      read -srp "CIFS Passwort: " CIFS_PASS; echo
      # Optional: SMB-Protokollversion (z.B. 3.0 für Kompatibilität)
      SMB_VER_DEFAULT="3.0"
      SMB_VER="$SMB_VER_DEFAULT"
      prompt_default SMB_VER "SMB-Protokollversion (z.B. 3.0)"
      echo "Mounten der CIFS-Freigabe $CIFS_REMOTE auf $MOUNT_POINT mit vers=$SMB_VER"
      mount -t cifs "$CIFS_REMOTE" "$MOUNT_POINT" \
        -o username="$CIFS_USER",password="$CIFS_PASS",vers=$SMB_VER,iocharset=utf8,sec=ntlmssp
    fi
    # Ziel-Image-Pfad
    OUT_FILE="$MOUNT_POINT/linuxserver.img.gz"
    ;;
  *)
    # Lokal
    OUT_FILE_DEFAULT="/tmp/linuxserver.img.gz"
    OUT_FILE="$OUT_FILE_DEFAULT"
    prompt_default OUT_FILE "Ziel-Datei (inkl. .img.gz) eingeben"
    ;;
esac

# 7. Blockgröße erklären und Standard setzen
cat <<EOF

Blockgröße für dd (bs) - beeinflusst Durchsatz und RAM-Verbrauch:
 - 512K : geringerer Speicherverbrauch, langsamer
 - 1M   : ausgewogen für ~4GB RAM (Standard)
 - 4M   : schneller, benötigt ≥8GB RAM
EOF
BS_DEFAULT="1M"
BS="$BS_DEFAULT"
prompt_default BS "Blockgröße wählen"

echo
# 8. Zusammenfassung vor Ausführung
echo "Zusammenfassung:"
echo "  Quellgerät:    $SRC_DEV"
echo -n "  Speicherziel:   "
case "$TARGET_TYPE" in
  1) echo "Lokal: $OUT_FILE";;
  2) echo "SSH: $SSH_DEST";;
  3) echo "Share: $OUT_FILE";;
esac
echo "  Blockgröße:    $BS"
read -rp "Fortfahren und Klon erstellen? (j/n): " proceed
[[ "$proceed" =~ ^[jJ] ]] || { echo "Abbruch."; exit 0; }

# 9. Speicherort-Prüfung bei lokal/share
if [[ "$TARGET_TYPE" != "2" ]]; then
  disk_bytes=$(blockdev --getsize64 "$SRC_DEV")
  disk_gb=$(( disk_bytes/1024/1024/1024 ))
  free_kb=$(df -P "$(dirname "$OUT_FILE")" | awk 'NR==2{print $4}')
  free_gb=$(( free_kb/1024/1024 ))
  echo "Quellgröße: ${disk_gb}GB, freier Speicher: ${free_gb}GB"
  if (( free_gb < disk_gb )); then
    read -rp "Wenig Speicherplatz. Trotzdem fortfahren? (j/n): " proceed2
    [[ "$proceed2" =~ ^[jJ] ]] || { echo "Abbruch."; exit 0; }
  fi
  # Prüfen auf identisches Medium
  base_src="${SRC_DEV%%[0-9]*}"
  target_device=$(df -P "$(dirname "$OUT_FILE")" | awk 'NR==2{print $1}')
  if [[ "$target_device" == "$base_src"* ]]; then
    echo "WARNUNG: Ziel liegt auf demselben Medium wie Quelle."
    read -rp "Trotzdem fortfahren? (j/n): " proceed3
    [[ "$proceed3" =~ ^[jJ] ]] || { echo "Abbruch."; exit 0; }
  fi
fi

# 10. Klonvorgang starten
echo "Starte Klonvorgang: $(date)"
case "$TARGET_TYPE" in
  2)
    # SSH-Streaming per SSH
    dd if="$SRC_DEV" bs="$BS" status=progress | gzip | ssh "$SSH_DEST" 'cat > "$(basename "${SSH_DEST#*:}")"'
    ;;
  *)
    # Lokal oder gemountetes Share
    dd if="$SRC_DEV" bs="$BS" status=progress | gzip > "$OUT_FILE"
    ;;
esac

echo -n "Klon abgeschlossen: "
case "$TARGET_TYPE" in
  2) echo "$SSH_DEST";;
  *) echo "$OUT_FILE";;
esac
# Ausgabe der erzeugten Dateigröße bei lokal/share
if [[ "$TARGET_TYPE" != "2" ]]; then
  echo -n "Image-Größe: "
  stat -c '%s' "$OUT_FILE" | awk '{printf "%.2f MB\n", $1/1024/1024}'
fi
