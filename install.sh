
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/meypanhawath/sys-tool/master/sys-tool.sh"
TARGET="/usr/local/bin/sys-tool.sh"

echo "Downloading sys-tool.sh..."
curl -sSL "$RAW_URL" -o "$TARGET"

chmod +x "$TARGET"

echo "Installation complete!"
echo "You can now run the tool with:"
echo "sudo $TARGET"

