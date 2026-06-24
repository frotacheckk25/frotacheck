#!/bin/bash
# Vercel build script for Flutter Web
# Uses direct download (faster than git clone)
set -e

FLUTTER_DIR="$HOME/flutter"
FLUTTER_VERSION="3.41.1"

# 1. Install Flutter if not cached
if [ ! -d "$FLUTTER_DIR/bin" ]; then
  echo "Downloading Flutter $FLUTTER_VERSION..."
  ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl -fL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}" \
    -o /tmp/flutter.tar.xz
  tar xf /tmp/flutter.tar.xz -C "$HOME"
  rm /tmp/flutter.tar.xz
fi

export PATH="$PATH:$FLUTTER_DIR/bin"
flutter --version

# 2. Inject Supabase credentials from Vercel env vars (if set)
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_KEY" ]; then
  echo "Injecting credentials from Vercel env vars..."
  cat > web/config.json <<EOF
{
  "SUPABASE_URL": "$SUPABASE_URL",
  "SUPABASE_KEY": "$SUPABASE_KEY"
}
EOF
else
  echo "SUPABASE_URL/SUPABASE_KEY not set — using values from web/config.json"
fi

# 3. Build
flutter pub get
flutter build web --release

# 4. Sanity checks
[ -f "build/web/index.html" ]            || { echo "ERROR: index.html missing" >&2; exit 1; }
[ -f "build/web/flutter_bootstrap.js" ]  || { echo "ERROR: flutter_bootstrap.js missing" >&2; exit 1; }
[ -f "build/web/main.dart.js" ]          || { echo "ERROR: main.dart.js missing" >&2; exit 1; }
[ -f "build/web/assets/web/config.json" ] || { echo "ERROR: assets/web/config.json missing" >&2; exit 1; }

echo "Vercel build OK."
