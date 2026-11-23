#!/bin/bash
# Downloads the latest OpenTAKServer-UI release into SWAG's www folder.
# Usage: ./fetch-ots-ui.sh /path/to/swag/config
set -e
SWAG_CONFIG="${1:?path to SWAG /config folder}"
DEST="$SWAG_CONFIG/www/opentakserver"
URL=$(curl -s https://api.github.com/repos/brian7704/OpenTAKServer-UI/releases/latest \
      | grep -o '"browser_download_url": *"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Downloading $URL"
TMP=$(mktemp -d)
curl -L "$URL" -o "$TMP/ui"
mkdir -p "$DEST"
case "$URL" in
  *.zip)            unzip -o "$TMP/ui" -d "$DEST" ;;
  *.tar.gz|*.tgz)   tar -xzf "$TMP/ui" -C "$DEST" ;;
  *) echo "Unknown asset type: $URL"; exit 1 ;;
esac
rm -rf "$TMP"
echo "UI files in $DEST - check that index.html is directly inside it."
