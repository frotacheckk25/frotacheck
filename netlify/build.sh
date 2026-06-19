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