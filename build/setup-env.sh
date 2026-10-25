#!/bin/bash
# Step 1 – build environment in $W (Linux / WSL, no root needed):
#   - Synology toolkit for the selected target: toolchain + sysroot
#   - Synology PHP7.4 reference package (binaries/extensions)
#   - re2c 1.3, PCRE2 and oniguruma sources (headers only)
# Target selection: see build/lib/target.sh (default = avoton/DSM6.2).
set -euo pipefail

B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
mkdir -p "$W/dl" "$W/root" "$W/syno/spk" "$W/syno/pkg" "$W/tools/src"

fetch() { # out url
  [ -s "$1" ] || curl -fSL --retry 3 -o "$1" "$2"
}

echo "== Synology DSM $DSM_VER $PLATFORM env + dev"
cd "$W/dl"
for f in env dev; do
  fetch ds.$PLATFORM-$DSM_VER.$f.txz "https://global.synologydownload.com/download/ToolChain/toolkit/$DSM_VER/$PLATFORM/ds.$PLATFORM-$DSM_VER.$f.txz"
done
cd "$W/root"
# only the target toolchain + sysroot; dev is extracted over env without
# keeping env's read-only directory modes
xz -T0 -dc "$W/dl/ds.$PLATFORM-$DSM_VER.env.txz" | tar -x --wildcards "usr/local/$HOST/*" 2>/dev/null || true
chmod -R u+w "$W/root"
xz -T0 -dc "$W/dl/ds.$PLATFORM-$DSM_VER.dev.txz" | tar -x --no-same-permissions --wildcards "usr/local/$HOST/*" 2>/dev/null || true
chmod -R u+w "$W/root"
"$TC/bin/$HOST-gcc" --version | head -1
test -f "$SYSROOT/usr/include/openssl/ssl.h"

echo "== Synology PHP7.4 $PKG_VER $PKG_ARCH package"
SPK=PHP7.4-$PKG_ARCH-$PKG_VER.spk
fetch "$W/syno/spk/$SPK" "https://global.synologydownload.com/download/Package/spk/PHP7.4/$PKG_VER/$SPK"
tar -xf "$W/syno/spk/$SPK" -C "$W/syno/spk"
xz -dc "$W/syno/spk/package.tgz" | tar -x -C "$W/syno/pkg"
ls "$W/syno/pkg/usr/local/bin"

echo "== re2c 1.3 (regenerates lexers touched by the security patches)"
cd "$W/tools/src"
fetch re2c-1.3.tar.xz https://github.com/skvadrik/re2c/releases/download/1.3/re2c-1.3.tar.xz
rm -rf re2c-1.3 && tar -xJf re2c-1.3.tar.xz
( cd re2c-1.3 && ./configure --prefix="$W/tools" --disable-docs >/dev/null && make -j"$(nproc)" >/dev/null 2>&1 && make install >/dev/null )
"$W/tools/bin/re2c" --version

echo "== PCRE2 $PCRE2_VER / oniguruma $ONIG_VER (same versions as the libs shipped in the package)"
fetch pcre2-$PCRE2_VER.tar.bz2 https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VER/pcre2-$PCRE2_VER.tar.bz2
fetch onig-$ONIG_VER.tar.gz https://github.com/kkos/oniguruma/releases/download/v$ONIG_VER/onig-$ONIG_VER.tar.gz
# sha256 pin only for the known-good default version; other versions just get printed
if [ "$PCRE2_VER" = 10.40 ]; then
  echo "14e4b83c4783933dc17e964318e6324f7cae1bc75d8f3c79bc6969f00c159d68  pcre2-10.40.tar.bz2" | sha256sum -c -
else
  sha256sum pcre2-$PCRE2_VER.tar.bz2
fi
echo "Environment ready in $W"
