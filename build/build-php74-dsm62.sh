#!/bin/bash
# Build PHP 7.4.33 (+ Debian/Ondrej security backports incl. PHP2Shell) fo
# Synology DSM 6.2 x86_64 (avoton toolchain, gcc 4.9.3 / glibc 2.20).
#
# Produces drop-in replacements for php74, php74-cgi and php74-fpm of the
# Synology PHP7.4 7.4.30-0009 package. Shared extensions are NOT rebuilt.
#
# Expects (see README.md):
#   ~/synobuild/root      Synology ds.avoton-6.2 env+dev (toolchain + sysroot)
#   ~/synobuild/syno/pkg  extracted package.tgz of PHP7.4-x86_64-7.4.30-0009
#   ~/synobuild/src/php-7.4.33  patched source tree
#   ~/synobuild/tools     re2c 1.3, pcre2-10.40 / onig-6.9.5 tarballs
set -euo pipefail

W=$HOME/synobuild
TC=$W/root/usr/local/x86_64-pc-linux-gnu
SYSROOT=$TC/x86_64-pc-linux-gnu/sys-root
PKG=$W/syno/pkg
SRC=$W/src/php-7.4.33
DEPS=$W/deps
OUT=$W/out
PKG_LIBDIR=/var/packages/PHP7.4/target/usr/lib

export PATH=$TC/bin:$W/tools/bin:$PATH
HOST=x86_64-pc-linux-gnu

# --- headers + link stubs for the libs that ship inside the Synology package
rm -rf "$DEPS" && mkdir -p "$DEPS/include" "$DEPS/lib"
tar -xjf $W/tools/src/pcre2-10.40.tar.bz2 -C "$DEPS"
cp "$DEPS/pcre2-10.40/src/pcre2.h.generic" "$DEPS/include/pcre2.h"
tar -xzf $W/tools/src/onig-6.9.5.tar.gz -C "$DEPS"
cp "$DEPS/onig-6.9.5/src/oniguruma.h" "$DEPS/include/"
# link directly against Synology's own builds (same SONAMEs at runtime)
cp -a "$PKG/usr/lib/libpcre2-8.so.0.11.0" "$PKG/usr/lib/libonig.so.5.0.0" "$DEPS/lib/"
ln -sf libpcre2-8.so.0.11.0 "$DEPS/lib/libpcre2-8.so.0"
ln -sf libpcre2-8.so.0 "$DEPS/lib/libpcre2-8.so"
ln -sf libonig.so.5.0.0 "$DEPS/lib/libonig.so.5"
ln -sf libonig.so.5 "$DEPS/lib/libonig.so"

export CC=$HOST-gcc CXX=$HOST-g++ AR=$HOST-ar RANLIB=$HOST-ranlib STRIP=$HOST-strip
export CFLAGS="-O2 -pipe -fno-strict-aliasing"
export CXXFLAGS="-O2 -pipe"
export CPPFLAGS="-I$DEPS/include -I$SYSROOT/usr/include/libxml2"
export LDFLAGS="-L$DEPS/lib -Wl,-rpath-link,$DEPS/lib -Wl,-rpath,$PKG_LIBDIR"
export EXTENSION_DIR=/usr/local/lib/php74/modules

# pkg-config bypass: PKG_CHECK_MODULES uses these when set
export LIBXML_CFLAGS="-I$SYSROOT/usr/include/libxml2" LIBXML_LIBS="-lxml2"
export OPENSSL_CFLAGS="-I$SYSROOT/usr/include" OPENSSL_LIBS="-lssl -lcrypto"
export ZLIB_CFLAGS="-I$SYSROOT/usr/include" ZLIB_LIBS="-lz"
export PCRE2_CFLAGS="-I$DEPS/include" PCRE2_LIBS="-lpcre2-8"
export ONIG_CFLAGS="-I$DEPS/include" ONIG_LIBS="-lonig"
export PKG_CONFIG=/bin/false

cd "$SRC"
# regenerate lexers touched by the security patches (0136)
for re in ext/pdo/pdo_sql_parser.re ext/standard/url_scanner_ex.re; do touch "$re"; done

make distclean >/dev/null 2>&1 || true
# host == build on purpose: the target binaries run on the WSL host, so
# configure's run-tests execute instead of falling back to cross defaults.
# Those run-tests link DSM libs (readline 6, OpenSSL 1.0, ...) that the WSL
# host doesn't have; without them checks fail and features get dropped
# (e.g. res_nsearch -> no dns_get_record/checkdnsrr/getmxrr)
export LD_LIBRARY_PATH="$DEPS/lib:$SYSROOT/usr/lib"
./configure \
  --host=$HOST --build=$HOST \
  --disable-rpath \
  --prefix=/usr \
  --bindir=/usr/local/bin --mandir=/usr/share/man \
  --sysconfdir=/usr/local/etc/php74 \
  --with-config-file-path=/usr/local/etc/php74/cli \
  --with-config-file-scan-dir=/usr/local/etc/php74/cli/conf.d \
  --localstatedir=/var \
  --with-pear=/usr/share/pear \
  --disable-all \
  --disable-phpdbg \
  --enable-cli --enable-cgi \
  --enable-fpm --with-fpm-user=http --with-fpm-group=http \
  --enable-ctype --enable-dom --enable-fileinfo --enable-filter --enable-json \
  --with-libxml --enable-mbstring --enable-mysqlnd --enable-pcntl \
  --with-external-pcre --with-pcre-jit \
  --enable-pdo --with-readline="$SYSROOT/usr" \
  --enable-session --enable-simplexml --enable-tokenizer \
  --enable-xml --enable-xmlreader --enable-xmlwriter \
  --with-mhash \
  --with-openssl=shared --with-zlib=shared \
  2>&1 | tee "$W/configure.log" | grep -E "^(configure: (error|WARNING)|checking for re2c)" || true

grep -q "Thank you for using PHP" "$W/configure.log" || { echo "configure failed, see $W/configure.log"; exit 1; }

make -j"$(nproc)" 2>&1 | tee "$W/make.log" | grep -E "error:|Error [0-9]" || true
test -x sapi/fpm/php-fpm && test -x sapi/cli/php && test -x sapi/cgi/php-cgi

mkdir -p "$OUT" && rm -f "$OUT"/php74 "$OUT"/php74-cgi "$OUT"/php74-fpm
cp sapi/cli/php "$OUT/php74"
cp sapi/cgi/php-cgi "$OUT/php74-cgi"
cp sapi/fpm/php-fpm "$OUT/php74-fpm"
$STRIP "$OUT"/php74*
ls -la "$OUT"
