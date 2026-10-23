#!/usr/bin/env bash
# Ekko deployen mit STABILER Signatur (README-Ritual gekapselt).
# Ad-hoc-Signatur (-s -) NIE — bricht alle TCC-Freigaben.
set -euo pipefail
cd "$(dirname "$0")"

echo "→ alte Instanz beenden"
pkill -f "Ekko.app/Contents" 2>/dev/null || true
sleep 1

echo "→ build (release)"
swift build -c release

echo "→ Binary ins Bundle + Version hochzählen + signieren"
mkdir -p Ekko.app/Contents/MacOS   # Build-Artefakte sind nicht im Repo
cp .build/release/Ekko Ekko.app/Contents/MacOS/Ekko
# MLX braucht mlx.metallib neben dem Binary (swift build kompiliert
# .metal nicht — siehe tools/build-mlx-metallib.sh). Ablage in
# Resources/ + Symlink in MacOS/: codesign verweigert Nicht-Code in
# MacOS/, MLX sucht aber per dladdr neben dem Binary.
if [ ! -f .build/release/mlx.metallib ]; then
  tools/build-mlx-metallib.sh .build/release
fi
cp .build/release/mlx.metallib Ekko.app/Contents/Resources/
ln -sf ../Resources/mlx.metallib Ekko.app/Contents/MacOS/mlx.metallib
# Markenschrift Sora (OFL) ins Paket — vor dem Signieren
mkdir -p Ekko.app/Contents/Resources/Fonts
cp Resources/Fonts/Sora-Variable.ttf Resources/Fonts/OFL.txt Ekko.app/Contents/Resources/Fonts/
# Lokalisierung (de = Quelle, en) — ebenfalls vor dem Signieren
cp -R Resources/Lokalisierung/*.lproj Ekko.app/Contents/Resources/
# CFBundleVersion pro Deploy: macOS wertet neue Binary sonst als
# „veränderte App" und fragt Bildschirmaufnahme-Freigabe neu ab.
plutil -replace CFBundleVersion -string "$(date +%Y%m%d%H%M)" Ekko.app/Contents/Info.plist
# Identität: EKKO_IDENTITAET oder die einzige „Apple Development"-Identität
# im Schlüsselbund. Bei mehreren lieber abbrechen als die falsche nehmen
# (andere Identität = alle Freigaben verfallen).
if [ -z "${EKKO_IDENTITAET:-}" ]; then
  kandidaten=$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development/ {print $2}')
  if [ "$(printf '%s\n' "$kandidaten" | grep -c .)" -ne 1 ]; then
    echo "Bitte EKKO_IDENTITAET setzen — gefunden:"; printf '%s\n' "$kandidaten"; exit 1
  fi
  EKKO_IDENTITAET="$kandidaten"
fi
codesign --force -s "$EKKO_IDENTITAET" Ekko.app

echo "→ starten"
open Ekko.app
sleep 1
echo "deployed — PID $(pgrep -f 'Ekko.app/Contents' || echo '?')"
