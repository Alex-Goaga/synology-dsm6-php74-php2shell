#!/bin/bash
# Fetch a throwaway MariaDB 10.3.39 (official binary tarball) and libaio for
# the database tests, into $W/mariadb. No root needed.
# Intentionally always x86_64, whatever the build target: this DB only serves
# the php74 client binary under test over TCP/socket, and the mysqlnd wire
# protocol is architecture-agnostic, so it always runs on the build host's
# own (x86_64) architecture.
set -euo pipefail

B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
M=$W/mariadb
F=mariadb-10.3.39-linux-systemd-x86_64.tar.gz
URL=https://archive.mariadb.org/mariadb-10.3.39/bintar-linux-systemd-x86_64
mkdir -p "$M" && cd "$M"

if [ ! -d "${F%.tar.gz}" ]; then
  [ -s "$F" ] || curl -fsSL -o "$F" "$URL/$F"
  curl -fsSL "$URL/sha256sums.txt" | grep -E " \./?$F\$" | sha256sum -c -
  tar -xzf "$F"
fi

# mysqld needs libaio.so.1; take the distro's package without installing it
# (named libaio1 on Ubuntu/older Debian, libaio1t64 after Debian's 64-bit
# time_t package transition -- which on some hosts also renames the actual
# SONAME on disk to libaio.so.1t64, so fall back to the already-installed
# system copy, aliased to the old name, if the mirror has no .deb to fetch)
mkdir -p aio/root/usr/lib/x86_64-linux-gnu
if [ ! -e aio/root/usr/lib/x86_64-linux-gnu/libaio.so.1 ]; then
  if ( cd aio && apt download libaio1 >/dev/null 2>&1 || apt download libaio1t64 >/dev/null 2>&1 ) \
      && ls aio/libaio1*.deb >/dev/null 2>&1; then
    ( cd aio && dpkg-deb -x libaio1*.deb root )
  else
    sys=$(find /usr/lib /lib -maxdepth 2 -name 'libaio.so.1*' 2>/dev/null | head -1)
    [ -n "$sys" ] || { echo "libaio.so.1(.t64) not found: install libaio1/libaio1t64 or fetch its .deb manually" >&2; exit 1; }
    cp "$sys" aio/root/usr/lib/x86_64-linux-gnu/libaio.so.1
  fi
fi
