#!/bin/bash
# Vercel build script for Flutter Web
set -e

# 1. Install Flutter (stable) if not cached
FLUTTER_DIR="$HOME/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Installing Flutter..."
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$PATH:$FLUTTER_DIR/bin"

flutter --version

# 2. Inject Supabase credentials from Vercel env vars (if provided)
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_KEY" ]; then
  echo "Injecting credentials from Vercel env vars..."
  cat > web/config.json <<EOF
{
  "SUPABASE_URL": "$SUPABASE_URL",
  "SUPABASE_KEY": "$SUPABASE_KEY"
}
EOF
else
  echo "SUPABASE_URL/SUPABASE_KEY not set — using values already in web/config.json"
fi

# 3. Build
flutter pub get
flutter build web --release

# 4. Sanity checks
[ -f "build/web/index.html" ]       || { echo "ERROR: index.html missing" >&2; exit 1; }
[ -f "build/web/flutter_bootstrap.js" ] || { echo "ERROR: flutter_bootstrap.js missing" >&2; exit 1; }
[ -f "build/web/main.dart.js" ]     || { echo "ERROR: main.dart.js missing" >&2; exit 1; }

echo "Vercel build OK."
