#!/bin/bash
# Step 1 – build environment in ~/synobuild (Linux / WSL, no root needed):
#   - Synology DSM 6.2 avoton toolkit: toolchain (gcc 4.9.3, glibc 2.20) + sysroot
#   - Synology PHP7.4 7.4.30-0009 x86_64 package (reference binaries/extensions)
#   - re2c 1.3, PCRE2 10.40 and oniguruma 6.9.5 sources (headers only)
set -euo pipefail

W=$HOME/synobuild
mkdir -p "$W/dl" "$W/root" "$W/syno/spk" "$W/syno/pkg" "$W/tools/src"

fetch() { # out url
  [ -s "$1" ] || curl -fSL --retry 3 -o "$1" "$2"
}

echo "== Synology DSM 6.2 avoton env + dev (~700 MB)"
cd "$W/dl"
for f in env dev; do
  fetch ds.avoton-6.2.$f.txz "https://global.synologydownload.com/download/ToolChain/toolkit/6.2/avoton/ds.avoton-6.2.$f.txz"
done
cd "$W/root"
# only the x86_64 toolchain + sysroot; dev is extracted over env without
# keeping env's read-only directory modes
xz -T0 -dc "$W/dl/ds.avoton-6.2.env.txz" | tar -x --wildcards 'usr/local/x86_64-pc-linux-gnu/*' 2>/dev/null || true
chmod -R u+w "$W/root"
xz -T0 -dc "$W/dl/ds.avoton-6.2.dev.txz" | tar -x --no-same-permissions --wildcards 'usr/local/x86_64-pc-linux-gnu/*' 2>/dev/null || true
chmod -R u+w "$W/root"
TC=$W/root/usr/local/x86_64-pc-linux-gnu
"$TC/bin/x86_64-pc-linux-gnu-gcc" --version | head -1
test -f "$TC/x86_64-pc-linux-gnu/sys-root/usr/include/openssl/ssl.h"

echo "== Synology PHP7.4 7.4.30-0009 x86_64 package"
SPK=PHP7.4-x86_64-7.4.30-0009.spk
fetch "$W/syno/spk/$SPK" "https://global.synologydownload.com/download/Package/spk/PHP7.4/7.4.30-0009/$SPK"
tar -xf "$W/syno/spk/$SPK" -C "$W/syno/spk"
xz -dc "$W/syno/spk/package.tgz" | tar -x -C "$W/syno/pkg"
ls "$W/syno/pkg/usr/local/bin"

echo "== re2c 1.3 (regenerates lexers touched by the security patches)"
cd "$W/tools/src"
fetch re2c-1.3.tar.xz https://github.com/skvadrik/re2c/releases/download/1.3/re2c-1.3.tar.xz
rm -rf re2c-1.3 && tar -xJf re2c-1.3.tar.xz
( cd re2c-1.3 && ./configure --prefix="$W/tools" --disable-docs >/dev/null && make -j"$(nproc)" >/dev/null 2>&1 && make install >/dev/null )
"$W/tools/bin/re2c" --version

echo "== PCRE2 10.40 / oniguruma 6.9.5 (same versions as the libs shipped in the package)"
fetch pcre2-10.40.tar.bz2 https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.40/pcre2-10.40.tar.bz2
fetch onig-6.9.5.tar.gz https://github.com/kkos/oniguruma/releases/download/v6.9.5/onig-6.9.5.tar.gz
echo "14e4b83c4783933dc17e964318e6324f7cae1bc75d8f3c79bc6969f00c159d68  pcre2-10.40.tar.bz2" | sha256sum -c -
echo "Environment ready in $W"
