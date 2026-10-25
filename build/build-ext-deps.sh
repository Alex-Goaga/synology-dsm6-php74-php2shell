#!/bin/bash
# Headers/link libraries that the target's sysroot lacks, at the exact
# versions found on the NAS / in the PHP7.4 package:
#   libxslt 1.1.28 (DSM system lib, used by xsl.so)
#   FreeTDS 1.1.20 (libsybdb.so.5 shipped in the PHP7.4 package, used by pdo_dblib.so)
# Only headers + link-time .so are used; at runtime the NAS's own libs are loaded.
set -euo pipefail

B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
DL=$W/tools/src
D=$W/extdeps
export PATH=$TC/bin:$PATH

mkdir -p "$DL" && cd "$DL"
fetch() { # out url...
  local out=$1; shift
  [ -s "$out" ] && return 0
  for u in "$@"; do curl -fsSL -o "$out" "$u" && return 0; done
  echo "download failed: $out" >&2; return 1
}
fetch libxslt-1.1.28.tar.xz \
  https://download.gnome.org/sources/libxslt/1.1/libxslt-1.1.28.tar.xz
fetch freetds-1.1.20.tar.gz \
  https://www.freetds.org/files/stable/freetds-1.1.20.tar.gz \
  https://www.freetds.org/files/stable/old/freetds-1.1.20.tar.gz
sha256sum libxslt-1.1.28.tar.xz freetds-1.1.20.tar.gz

rm -rf "$D" && mkdir -p "$D/build"

# --- libxslt 1.1.28 built with the Synology toolchain against DSM's libxml2 2.9.4
tar -xJf "$DL/libxslt-1.1.28.tar.xz" -C "$D/build"
cd "$D/build/libxslt-1.1.28"
# xml2-config shim pointing at DSM's libxml2 in the sysroot
mkdir -p "$D/xml2/bin"
cat > "$D/xml2/bin/xml2-config" <<SHIM
#!/bin/sh
case "\$1" in
  --version) echo $LIBXML2_VER ;;
  --cflags) echo "-I$SYSROOT/usr/include/libxml2" ;;
  --libs) echo "-lxml2 -lz -lm -ldl" ;;
  --prefix) echo "$SYSROOT/usr" ;;
esac
SHIM
chmod +x "$D/xml2/bin/xml2-config"
# --build=$BUILD (not a literal x86_64 triplet): must match the core PHP
# build's native-execution choice, or configure silently falls back to
# cross-compile defaults (see build-php74-dsm62.sh)
CC=$HOST-gcc ./configure --host=$HOST --build=$BUILD --prefix="$D/xslt" \
  --with-libxml-prefix="$D/xml2" \
  --without-python --without-crypto --without-debug --without-plugins >/dev/null
make -j"$(nproc)" >/dev/null 2>&1 && make install >/dev/null
ls "$D/xslt/lib" | grep -E '^lib(e)?xslt\.so'

# --- FreeTDS 1.1.20
tar -xzf "$DL/freetds-1.1.20.tar.gz" -C "$D/build"
cd "$D/build/freetds-1.1.20"
CC=$HOST-gcc ./configure --host=$HOST --build=$BUILD --prefix="$D/freetds" \
  --disable-odbc --disable-apps --disable-server --disable-pool --without-openssl --without-gnutls >/dev/null
mkdir -p "$D/freetds/include" "$D/freetds/lib"
cp include/sybdb.h include/sybfront.h include/syberror.h include/tds_sysdep_public.h "$D/freetds/include/"
if [ "${FREETDS_FROM_SOURCE:-0}" = 1 ]; then
  # avoton's reference package's own libsybdb.so is linked against whatever
  # OpenSSL SONAME its DSM/toolkit vintage had (e.g. libssl.so.1.0.0); when
  # the reference package predates the target's toolkit (as for evansport,
  # see build/targets/evansport-dsm71.env), that SONAME is absent from the
  # real sysroot and the copied .so fails to load. Build it ourselves
  # instead: --without-openssl --without-gnutls (already set above) means
  # libsybdb depends on nothing but libc/libpthread, which always resolves.
  make -j"$(nproc)" >/dev/null
  SYBDB_SO=$(basename "$(ls src/dblib/.libs/libsybdb.so.*.*.* 2>/dev/null | head -1)")
  cp -a "src/dblib/.libs/$SYBDB_SO" "$D/freetds/lib/"
else
  # headers only; link against the reference package's own prebuilt libsybdb
  # (same SONAME at runtime as what the NAS already has installed)
  SYBDB_SO=$(basename "$(ls "$PKG"/usr/lib/libsybdb.so.*.*.* 2>/dev/null | head -1)")
  cp -a "$PKG/usr/lib/$SYBDB_SO" "$D/freetds/lib/"
fi
ln -sf "$SYBDB_SO" "$D/freetds/lib/libsybdb.so.5"
ln -sf libsybdb.so.5 "$D/freetds/lib/libsybdb.so"
ls -la "$D/freetds/include" "$D/freetds/lib"
