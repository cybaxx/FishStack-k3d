#!/usr/bin/env sh
set -eu

WWWROOT=/var/www/forum
APPDATA=/var/www/appdata

# Directories to persist on the appdata PVC and symlink back into wwwroot.
# On first start they are seeded from the image; on subsequent starts the
# symlink is re-established and existing data is preserved.
PERSIST_DIRS="
  attachments
  avatars
  custom_avatar
  fish
  Packages
  Smileys
  Themes
  images"

WEB_USER="www-data"
WEB_GROUP="www-data"

echo "[entrypoint] Setting up SMF persistent directories..."

for d in $PERSIST_DIRS; do
  TARGET="$WWWROOT/$d"
  SOURCE="$APPDATA/$d"

  # Ensure the persistent dir exists
  mkdir -p "$SOURCE"

  # Seed from image on first start (source empty, target is a real dir)
  if [ -d "$TARGET" ] && [ ! -L "$TARGET" ] && [ -z "$(ls -A "$SOURCE" 2>/dev/null)" ]; then
    echo "[entrypoint] Seeding $d into appdata PVC..."
    cp -a "$TARGET/." "$SOURCE/" || true
  fi

  # Replace real dir with symlink
  if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    rm -rf "$TARGET"
  fi

  if [ ! -L "$TARGET" ]; then
    ln -s "$SOURCE" "$TARGET"
  fi

  chown -R "$WEB_USER:$WEB_GROUP" "$SOURCE"
  chmod -R u+rwX,go+rX "$SOURCE"
done

# Remove install.php — should never be accessible in production
if [ -f "$WWWROOT/install.php" ]; then
  echo "[entrypoint] Removing install.php..."
  rm -f "$WWWROOT/install.php"
fi

# Fix permissions on wwwroot
chown -R "$WEB_USER:$WEB_GROUP" "$WWWROOT" "$APPDATA"
find "$WWWROOT" -type d -exec chmod 755 {} \;
find "$WWWROOT" -type f -exec chmod 644 {} \;

echo "[entrypoint] Done. Starting php-fpm..."
exec "$@"
