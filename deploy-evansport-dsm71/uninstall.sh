#!/bin/sh
# Restore the original Synology PHP7.4 binaries and extensions saved by install.sh.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/target.env"
PKGDIR=/var/packages/PHP7.4
BIN=$PKGDIR/target/usr/local/bin
MODDIR=$PKGDIR/target/usr/local/lib/php74/modules
BACKUP=$PKGDIR/target/.orig-$PKG_VER

[ "$(id -u)" = 0 ] || { echo "run as root (sudo -i)"; exit 1; }
[ -d "$BACKUP/bin" ] || { echo "no backup found in $BACKUP"; exit 1; }

restore() { cp -p "$1" "$2.old.$$" && mv -f "$2.old.$$" "$2"; }
for f in "$BACKUP"/modules/*.so; do [ -e "$f" ] && restore "$f" "$MODDIR/$(basename "$f")"; done
for f in php74 php74-cgi php74-fpm; do restore "$BACKUP/bin/$f" "$BIN/$f"; done

# only PHP 7.4 masters; other PHP packages' FPM masters are left alone
for p in $(ps -eo pid,args 2>/dev/null | awk '/php-fpm: master process/ && !/awk/ {print $1}'); do
  case "$(readlink "/proc/$p/exe" 2>/dev/null)" in *php74-fpm*) kill -USR2 "$p";; esac
done
"$BIN/php74" -v 2>/dev/null | head -1
echo "Original files restored (VULNERABLE to PHP2Shell)."
