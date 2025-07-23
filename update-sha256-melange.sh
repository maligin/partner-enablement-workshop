#!/bin/bash
set -e

YAML_FILE="melange/melange.yaml"
URL="https://github.com/maligin/partner-enablement-workshop/archive/refs/heads/main.tar.gz"

# SHA256 automatisch ermitteln
NEW_HASH=$(curl -sSL "$URL" | sha256sum | awk '{print $1}')

# Debug-Ausgabe
echo "Neuer SHA256: $NEW_HASH"

# Wert im YAML ersetzen
yq -i '
  (.pipeline[] | select(.uses == "fetch") | .with.expected-sha256) = "'"$NEW_HASH"'"
' "$YAML_FILE"

echo "melange.yaml wurde aktualisiert."

