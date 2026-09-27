#!/usr/bin/env bash
# Refreshes the translations: extracts i18n*() strings from the package into framewidge.pot,
# merges them into every <lang>.po and compiles the .mo files into the package
# (package/contents/locale/<lang>/LC_MESSAGES/, loaded by Plasma for the installed widget).
#   po/update.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DOMAIN=plasma_applet_org.kde.plasma.framewidge
xgettext --from-code=UTF-8 -L JavaScript --no-location --add-comments=i18n \
    --keyword=i18n:1 --keyword=i18nc:1c,2 --keyword=i18np:1,2 --keyword=i18ncp:1c,2,3 \
    --package-name=FrameWidge -o po/framewidge.pot $(find package/contents -name '*.qml' -o -name '*.js' | sort)
sed -i '/^#, .*javascript-format/d' po/framewidge.pot   # KDE's %1 is no printf format
for po in po/*.po; do
    lang="$(basename "${po}" .po)"
    msgmerge --quiet --update --backup=none --no-location "${po}" po/framewidge.pot
    sed -i '/^#, .*javascript-format/d' "${po}"
    mkdir -p "package/contents/locale/${lang}/LC_MESSAGES"
    msgfmt --check-format -o "package/contents/locale/${lang}/LC_MESSAGES/${DOMAIN}.mo" "${po}"
    echo "${lang}: $(msgfmt --statistics -o /dev/null "${po}" 2>&1)"
done
