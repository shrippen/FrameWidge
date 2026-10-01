#!/usr/bin/env bash
# Copies the Kante QML module from the design system repo into the widget.
#
#   package/contents/ui/Kante        KanteStyle, components, skins, fonts
#   package/contents/ui/KantePlasma  the PlasmaComponents3 wrappers
#
# A Plasma Store package cannot use import paths, so the modules are vendored.
# Source: KANTE_DS, default ../Kante (https://github.com/shrippen/Kante).
# The copies are not edited here; change the design system and sync again.
set -euo pipefail
cd "$(dirname "$0")/.."

DS="${KANTE_DS:-../Kante}"
if [ ! -f "$DS/qml/Kante/qmldir" ]; then
    echo "sync-kante: no Kante module in $DS/qml (set KANTE_DS)" >&2
    exit 1
fi

for module in Kante KantePlasma; do
    rm -rf "package/contents/ui/$module"
    cp -r "$DS/qml/$module" "package/contents/ui/$module"
done

echo "sync-kante: $(git -C "$DS" describe --always --dirty 2>/dev/null || echo unknown) -> package/contents/ui/Kante, KantePlasma"
