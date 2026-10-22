#!/bin/bash
# Step 2 – patched PHP 7.4.33 source tree in ~/synobuild/src/php-7.4.33:
#   php.net 7.4.33 + Ondřej Surý's php7.4 1:7.4.33-31 security backports
#   (incl. PHP2Shell, patch 0164) + Synology compatibility patches.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
W=$HOME/synobuild
DEB=php7.4_7.4.33-31+ubuntu22.04.1+deb.sury.org+1.debian.tar.xz
mkdir -p "$W/src" "$W/dl/ondrej-31"

cd "$W/src"
[ -s php-7.4.33.tar.xz ] || curl -fsSL -o php-7.4.33.tar.xz https://www.php.net/distributions/php-7.4.33.tar.xz
echo "924846abf93bc613815c55dd3f5809377813ac62a9ec4eb3778675b82a27b927  php-7.4.33.tar.xz" | sha256sum -c -
rm -rf php-7.4.33 && tar -xJf php-7.4.33.tar.xz

cd "$W/dl/ondrej-31"
[ -s debian.tar.xz ] || curl -fsSL -o debian.tar.xz "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/pool/main/p/php7.4/$DEB"
rm -rf debian && tar -xJf debian.tar.xz
P=$W/dl/ondrej-31/debian/patches

cd "$W/src/php-7.4.33"
# applied-patches.txt pins the exact list; "(filtered)" = NEWS/tests hunks dropped
# because they do not apply to the php.net tarball. Excluded on purpose:
# Debian packaging (0001-0047), NEWS/README/credits/Windows, and 0128
# ("secure DNS telemetry": phones home with version-check DNS queries).
while read -r line; do
  [ -z "$line" ] && continue
  p=${line%% *}
  if [[ $line == *"(filtered)"* ]]; then
    python3 -I "$HERE/filterpatch.py" "$P/$p" | patch -p1 -N -s
  else
    patch -p1 -N -s < "$P/$p"
  fi
done < "$HERE/applied-patches.txt"
echo "applied $(grep -c . "$HERE/applied-patches.txt") Debian/Ondřej patches"

# Synology behaviour reconstructed from the original php74-fpm (see README)
python3 -I "$HERE/apply_syno_compat.py" main/php_ini.c
python3 -I "$HERE/apply_syno_extdir.py" .
python3 -I "$HERE/apply_syno_dupmod.py" .
grep -q zend_mm_safe_error_ex Zend/zend_alloc.h && echo "PHP2Shell fix present"
