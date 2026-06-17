#!/usr/bin/env bash
set -euo pipefail

# Use a known stable Flutter version compatible with the project.
FLUTTER_VERSION="3.41.1-stable"
FLUTTER_DIR="$HOME/flutter"
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Installing Flutter SDK ${FLUTTER_VERSION}..."
  mkdir -p "$HOME"
  if command -v curl >/dev/null 2>&1; then
    curl -L "$FLUTTER_URL" -o "/tmp/${FLUTTER_ARCHIVE}"
  else
    wget "$FLUTTER_URL" -O "/tmp/${FLUTTER_ARCHIVE}"
  fi
  tar xf "/tmp/${FLUTTER_ARCHIVE}" -C "$HOME"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
export PUB_CACHE="$HOME/.pub-cache"

flutter --version
flutter pub get
flutter build web
