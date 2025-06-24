# Anleitung zu `clone_disk.sh`

Dieses Dokument beschreibt ausführlich die Funktionsweise, Installation und Nutzung des Skripts **`clone_disk.sh`**, mit dem Festplattenabbilder interaktiv erzeugt und wahlweise lokal, per SSH oder auf einem Netzwerkshare abgelegt werden können.

---

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Funktionen & Features](#funktionen--features)
3. [Voraussetzungen](#voraussetzungen)
4. [Installation](#installation)
5. [Aufbau des Skripts](#aufbau-des-skripts)
6. [Konfiguration & Ausführung](#konfiguration--ausführung)

   1. [Quellgerät auswählen](#1-quellgerät-auswählen)
   2. [Speicherziel wählen](#2-speicherziel-wählen)
   3. [Parameter eingeben](#3-parameter-eingeben)
   4. [Blockgröße & Format festlegen](#4-blockgröße--format-festlegen)
   5. [Basis-Dateiname & Zeitstempel](#5-basis-dateiname--zeitstempel)
   6. [Klonvorgang starten](#6-klonvorgang-starten)
7. [Beispiele](#beispiele)
8. [Fehlersuche & Troubleshooting](#fehlersuche--troubleshooting)
9. [Lizenz & Haftungsausschluss](#lizenz--haftungsausschluss)

---

## Übersicht

Mit **`clone_disk.sh`** können Sie auf einfache Weise eine vollständige Kopie (Image) einer Festplatte erstellen und in verschiedenen Zielmedien ablegen:

* **Lokal** auf dem gleichen oder anderen Laufwerk
* **Per SSH** auf einen entfernten Server
* **Netzwerkshare** (NFS oder CIFS/SMB)

Das Skript führt Sie interaktiv durch alle notwendigen Schritte, vermeidet Überschreiben durch Zeitstempel und erlaubt Ausgabe im **raw**, **raw\.gz** oder **qcow2**-Format.

## Funktionen & Features

* **Interaktive Menüs** ohne zusätzliche Abhängigkeiten (nur Bash-Bordmittel)
* Automatische **Geräteerkennung** mittels `lsblk`
* Wahl zwischen **Lokal**, **SSH** und **Netzwerkshare**
* Unterstützung für **NFS** und **CIFS/SMB** inklusive Passwortabfrage
* Konfigurierbare **Blockgröße** (`dd bs=`) für RAM-Anforderungen
* Ausgabeformate:

  * `raw.gz` (komprimiertes Roh-Image)
  * `raw` (ungepacktes Roh-Image)
  * `qcow2` (QEMU Copy-On-Write, wenn `qemu-img` installiert)
* **Zeitstempel** im Dateinamen, um Überschreiben zu vermeiden
* Detaillierte **Statusausgabe** während des Klonvorgangs

## Voraussetzungen

* **Bash** (>= 4.x)
* `dd`, `gzip`, `lsblk`, `awk`, `stat`, `df`
* Für **qcow2**-Format: `qemu-img` (optional)
* Für **CIFS/SMB**: `mount.cifs` (Teil von `cifs-utils`)
* Für **NFS**: Kernel-Modul `nfs` bzw. Paket `nfs-common`

## Installation

1. Skript herunterladen und in ein Verzeichnis legen, z. B. `/usr/local/bin`:

   ```bash
   wget https://example.com/clone_disk.sh -O /usr/local/bin/clone_disk.sh
   chmod +x /usr/local/bin/clone_disk.sh
   ```
2. (Optional) Pakete installieren:

   ```bash
   # Für CIFS
   sudo apt install cifs-utils
   # Für qemu-img
   sudo apt install qemu-utils
   # Für NFS (Client)
   sudo apt install nfs-common
   ```

## Aufbau des Skripts

Das Skript gliedert sich in folgende Abschnitte:

1. **Prüfungen** (Bash, qemu-img)
2. **Interaktive Auswahl** von Quellgerät (`lsblk`) und Speichertyp
3. **Konfiguration** des Speicherziels (Lokal, SSH, Netzwerkshare)
4. **Eingabe** von Blockgröße und Ausgabeformat
5. **Benutzerdefinierter** Basis-Dateiname sowie Zeitstempel-Generierung
6. **Klonvorgang** mit `dd` und ggf. `qemu-img` für Konvertierung
7. **Abschlussmeldung** und Anzeige der resultierenden Dateigröße

## Konfiguration & Ausführung

### 1. Quellgerät auswählen

Das Skript zeigt alle physischen Laufwerke aus `lsblk`. Wählen Sie das gewünschte Gerät per Nummer aus.

### 2. Speicherziel wählen

Wählen Sie, ob das Abbild **lokal**, per **SSH** oder auf einem **Netzwerkshare** (NFS/CIFS) gespeichert werden soll.

### 3. Parameter eingeben

* **Lokal**: Ziel-Verzeichnis (`/tmp` etc.)
* **SSH**: Ziel-Verzeichnis auf dem Remote-Host (`user@host:/pfad`)
* **Netzwerkshare**:

  * Protokoll (NFS oder CIFS)
  * Freigabe-Pfad
  * Lokaler Einhängepunkt (wird bei Bedarf angelegt)
  * Bei CIFS: Benutzername & Passwort

### 4. Blockgröße & Format festlegen

* **Blockgröße** für `dd`: 512K / 1M / 4M
* **Format**: `raw.gz`, `raw` oder (wenn verfügbar) `qcow2`

### 5. Basis-Dateiname & Zeitstempel

Geben Sie einen aussagekräftigen Namen ohne Extension ein. Ein Zeitstempel im Format `YYYYMMDD_HHMMSS` wird automatisch angehängt.

### 6. Klonvorgang starten

Das Skript führt den Klon mit `dd` aus:

* Bei `raw.gz` werden Daten on-the-fly komprimiert.
* Bei `raw` entsteht ein unkomprimiertes Image.
* Bei `qcow2` wird zunächst `raw` geschrieben und anschließend mit `qemu-img convert` umgewandelt.

Während des Vorgangs zeigt `dd status=progress` den Kopierfortschritt.

## Beispiele

```bash
$ clone_disk.sh
# Interaktiver Ablauf gemäß obiger Anleitung
```

**Beispiel für SSH-Backup:**

```text
Speichertyp: SSH
SSH-Ziel-Verzeichnis: backup@server:/mnt/backups
...
Fortfahren? j
Starte Klonvorgang: 2025-06-24
1048576+0 records in
1048576+0 records out
...
Klon abgeschlossen: backup@server:/mnt/backups/linuxserver_20250624_203045.img.gz
```

## Fehlersuche & Troubleshooting

* **`mount: cannot mount`**: Prüfen Sie Protokoll, Pfad und Berechtigungen.
* **`dd: cannot open`**: Stellen Sie sicher, dass Sie Root-Rechte haben und das Device nicht belegt ist.
* **`qemu-img: command not found`**: Installieren Sie `qemu-utils`.
* **SSH-Verbindung**: Testen Sie manuell mit `ssh user@host "touch /mnt/backups/test"`.

## Lizenz & Haftungsausschluss

Das Skript wird ohne Gewährleistung bereitgestellt. Der Anwender ist allein verantwortlich für den korrekten Einsatz und etwaige Datenverluste.

---

