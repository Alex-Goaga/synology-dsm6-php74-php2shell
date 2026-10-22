#!/bin/bash
# Fetch a throwaway MariaDB 10.3.39 (official binary tarball) and libaio for
# the database tests, into ~/synobuild/mariadb. No root needed.
set -euo pipefail

M=$HOME/synobuild/mariadb
F=mariadb-10.3.39-linux-systemd-x86_64.tar.gz
URL=https://archive.mariadb.org/mariadb-10.3.39/bintar-linux-systemd-x86_64
mkdir -p "$M" && cd "$M"

if [ ! -d "${F%.tar.gz}" ]; then
  [ -s "$F" ] || curl -fsSL -o "$F" "$URL/$F"
  curl -fsSL "$URL/sha256sums.txt" | grep " $F\$" | sha256sum -c -
  tar -xzf "$F"
fi

# mysqld needs libaio.so.1; take Ubuntu's package without installing it
if [ ! -e aio/root/usr/lib/x86_64-linux-gnu/libaio.so.1 ]; then
  mkdir -p aio && cd aio
  apt download libaio1 >/dev/null 2>&1
  dpkg-deb -x libaio1_*.deb root
fi
