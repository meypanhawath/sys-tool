set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/meypanhawath/sys-tool/master/sys-tool.sh"
DEST="/usr/local/bin/sys-tool.sh"

echo "Downloading sys-tool.sh..."
sudo curl -sSL "$REPO_URL" -o "$DEST"
sudo chmod +x "$DEST"

# Ensure the script uses bash explicitly
sudo sed -i '1c #!/usr/bin/env bash' "$DEST"

echo "Installation complete!"
echo "You can now run the tool with:"
echo "sudo sys-tool.sh"

