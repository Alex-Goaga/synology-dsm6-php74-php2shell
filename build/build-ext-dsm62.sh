#!/bin/bash
# Rebuild the Synology PHP7.4 shared extensions that have security fixes in
# the patch set, with the same features/libraries as Synology's reference
# package (see build/lib/target.sh for which version/arch):
#   openssl soap phar ftp gd intl ldap pgsql pdo_pgsql pdo_sqlite pdo_dblib xsl
# Uses a separate copy of the patched tree; core binaries come from
# build-php74-dsm62.sh and are not replaced here.
set -euo pipefail

B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
INC=$SYSROOT/usr/include
DEPS=$W/deps
XD=$W/extdeps
SRC=$W/src-ext/php-7.4.33
OUT=$W/out/modules
PKG_LIBDIR=/var/packages/PHP7.4/target/usr/lib
EXTS="openssl soap phar ftp gd intl ldap pgsql pdo_pgsql pdo_sqlite pdo_dblib xsl"

export PATH=$TC/bin:$W/tools/bin:$PATH

rm -rf "$W/src-ext" && mkdir -p "$W/src-ext"
cp -a "$W/src/php-7.4.33" "$W/src-ext/"
cd "$SRC"
make distclean >/dev/null 2>&1 || true

export CC=$HOST-gcc CXX=$HOST-g++ AR=$HOST-ar RANLIB=$HOST-ranlib STRIP=$HOST-strip
export CFLAGS="-O2 -pipe -fno-strict-aliasing"
export CXXFLAGS="-O2 -pipe"
export CPPFLAGS="-I$DEPS/include -I$INC/libxml2"
export LDFLAGS="-L$DEPS/lib -L$XD/xslt/lib -Wl,-rpath-link,$DEPS/lib:$XD/xslt/lib:$SYSROOT/usr/lib -Wl,-rpath,$PKG_LIBDIR"
export EXTENSION_DIR=/usr/local/lib/php74/modules
export PKG_CONFIG=/bin/false

export LIBXML_CFLAGS="-I$INC/libxml2" LIBXML_LIBS="-lxml2"
export OPENSSL_CFLAGS="-I$INC" OPENSSL_LIBS="-lssl -lcrypto"
export ZLIB_CFLAGS="-I$INC" ZLIB_LIBS="-lz"
export PCRE2_CFLAGS="-I$DEPS/include" PCRE2_LIBS="-lpcre2-8"
export ONIG_CFLAGS="-I$DEPS/include" ONIG_LIBS="-lonig"
export SQLITE_CFLAGS="-I$INC" SQLITE_LIBS="-lsqlite3"
export PNG_CFLAGS="-I$INC/libpng16" PNG_LIBS="-lpng16"
export JPEG_CFLAGS="-I$INC" JPEG_LIBS="-ljpeg"
export WEBP_CFLAGS="-I$INC" WEBP_LIBS="-lwebp"
export FREETYPE2_CFLAGS="-I$INC/freetype2" FREETYPE2_LIBS="-lfreetype"
export ICU_CFLAGS="-I$INC" ICU_LIBS="-licuio -licui18n -licuuc -licudata"
export SASL_CFLAGS="-I$INC" SASL_LIBS="-lsasl2"
export XSL_CFLAGS="-I$XD/xslt/include -I$INC/libxml2" XSL_LIBS="-lxslt -lxml2"
export EXSLT_CFLAGS="-I$XD/xslt/include" EXSLT_LIBS="-lexslt -lxslt -lxml2"

# run-tests need the DSM libs at runtime (see build-php74-dsm62.sh)
export LD_LIBRARY_PATH="$DEPS/lib:$XD/xslt/lib:$XD/freetds/lib:$SYSROOT/usr/lib"
./configure \
  --host=$HOST --build=$BUILD --disable-rpath \
  --prefix=/usr --sysconfdir=/usr/local/etc/php74 \
  --with-config-file-path=/usr/local/etc/php74/cli \
  --localstatedir=/var --with-pear=/usr/share/pear --disable-all --disable-phpdbg --enable-cli --disable-cgi \
  --enable-ctype --enable-dom --enable-fileinfo --enable-filter --enable-json \
  --with-libxml --enable-mbstring --enable-mysqlnd --enable-pcntl \
  --with-external-pcre --with-pcre-jit --enable-pdo --enable-session \
  --enable-simplexml --enable-tokenizer --enable-xml --enable-xmlreader --enable-xmlwriter \
  --bindir=/usr/local/bin --mandir=/usr/share/man \
  --with-config-file-scan-dir=/usr/local/etc/php74/cli/conf.d \
  --with-mhash --with-zlib=shared \
  --with-openssl=shared \
  --enable-soap=shared \
  --enable-phar=shared \
  --enable-ftp=shared \
  --enable-gd=shared --with-freetype --with-jpeg --with-webp \
  --enable-intl=shared \
  --with-ldap=shared,"$SYSROOT/usr" --with-ldap-sasl \
  --with-pgsql=shared,"$SYSROOT/usr" --with-pdo-pgsql=shared,"$SYSROOT/usr" \
  --with-pdo-sqlite=shared \
  --with-pdo-dblib=shared,"$XD/freetds" \
  --with-xsl=shared \
  2>&1 | tee "$W/configure-ext.log" | grep -E "^configure: (error|WARNING)" || true
grep -q "Thank you for using PHP" "$W/configure-ext.log" || { tail -20 "$W/configure-ext.log"; exit 1; }

make -j"$(nproc)" 2>&1 | tee "$W/make-ext.log" | grep -E "error:|Error [0-9]" || true

rm -rf "$OUT" && mkdir -p "$OUT"
for e in $EXTS; do
  test -f "modules/$e.so" || { echo "MISSING modules/$e.so"; exit 1; }
  cp "modules/$e.so" "$OUT/"
done
$STRIP --strip-unneeded "$OUT"/*.so
ls -la "$OUT"
