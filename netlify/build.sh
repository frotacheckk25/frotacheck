#!/bin/bash
# Netlify build script for Flutter
set -e

# Install Flutter
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter.git $HOME/flutter
fi
export PATH="$PATH:$HOME/flutter/bin"

# Flutter setup
flutter doctor -v
flutter pub get
flutter build web --release

# Sanity checks (prevents publishing a blank page)
if [ ! -f "build/web/index.html" ]; then
  echo "ERROR: build/web/index.html not found" >&2
  exit 1
fi

if [ ! -f "build/web/flutter_bootstrap.js" ]; then
  echo "ERROR: build/web/flutter_bootstrap.js not found" >&2
  exit 1
fi

if [ ! -f "build/web/main.dart.js" ]; then
  echo "ERROR: build/web/main.dart.js not found" >&2
  exit 1
fi

echo "Netlify build OK: Flutter artifacts present." 

