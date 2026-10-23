#!/usr/bin/env bash
# Baut mlx.metallib aus den MLX-Kernel-Quellen.
#
# Hintergrund: `swift build` kompiliert .metal-Quellen NICHT (nur Xcode
# tut das) — MLX braucht aber eine Basis-Library neben dem Binary
# (device.cpp: get_colocated_mtllib_path). Einmal pro mlx-swift-Version
# nötig; deploy.sh ruft das bei Bedarf auf.
# Voraussetzung: Metal-Toolchain (xcodebuild -downloadComponent MetalToolchain).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal
OUT="${1:-.build/release}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ ! -d "$SRC" ]; then
  echo "Kernel-Quellen fehlen ($SRC) — erst 'swift build' laufen lassen." >&2
  exit 1
fi

for f in "$SRC"/*.metal; do
  xcrun -sdk macosx metal -O2 -ffast-math -c "$f" -I "$SRC" \
    -o "$TMP/$(basename "${f%.metal}").air"
done
xcrun -sdk macosx metallib "$TMP"/*.air -o "$OUT/mlx.metallib"
echo "mlx.metallib → $OUT"
