#!/bin/sh
# Install patched PHP 7.4.33 (PHP2Shell fix + security backports) over Synology
# PHP7.4 7.4.30-0009 on DSM 6.2 x86_64: core binaries + rebuilt extensions.
# Run on the NAS as root:  sudo -i ; sh install.sh
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
PKGDIR=/var/packages/PHP7.4
BIN=$PKGDIR/target/usr/local/bin
MODDIR=$PKGDIR/target/usr/local/lib/php74/modules
BACKUP=$PKGDIR/target/.orig-7.4.30-0009
FILES="php74 php74-cgi php74-fpm"
MODS=$(cd "$HERE/modules" && ls *.so)

die() { echo "ERROR: $*" >&2; exit 1; }

# php-fpm sets its title to "php-fpm: master process (...)" regardless of the
# binary name, so pick masters by the executable they run
fpm74_masters() {
  for p in $(ps -eo pid,args 2>/dev/null | awk '/php-fpm: master process/ && !/awk/ {print $1}'); do
    case "$(readlink "/proc/$p/exe" 2>/dev/null)" in *php74-fpm*) echo "$p";; esac
  done
  # always succeed: with set -e, a non-PHP-7.4 FPM master (e.g. another PHP
  # package) listed last would otherwise abort the script before the reload
  return 0
}

# copy to a temp name and rename: running processes keep the old inode, so
# nothing that is mapped in memory gets overwritten in place
replace() { # src dst
  cp "$1" "$2.new.$$"
  chown --reference="$2" "$2.new.$$" 2>/dev/null || true
  chmod --reference="$2" "$2.new.$$" 2>/dev/null || chmod 755 "$2.new.$$"
  mv -f "$2.new.$$" "$2"
}

[ "$(id -u)" = 0 ] || die "run as root (sudo -i)"
[ "$(uname -m)" = x86_64 ] || die "architecture is not x86_64"
grep -q '^version="7.4.30-0009"' "$PKGDIR/INFO" 2>/dev/null || die "the installed PHP7.4 package is not 7.4.30-0009"
grep -q '^arch="x86_64"' "$PKGDIR/INFO" || die "the PHP7.4 package is not x86_64"
for m in $MODS; do [ -f "$MODDIR/$m" ] || die "extension $m does not exist in the installed package"; done

cd "$HERE"
sha256sum -c SHA256SUMS >/dev/null || die "checksum mismatch (files corrupted while copying)"
echo "== checksums OK"

echo "== testing the new binaries before installing"
# -c reads only php.ini; the extension list lives in conf.d/extension.ini
CLI_INI=/usr/local/etc/php74/cli
[ -d "$CLI_INI/conf.d" ] && export PHP_INI_SCAN_DIR="$CLI_INI/conf.d"
# reference = the original Synology binary (backup if a previous run installed already)
REF=$BIN/php74; [ -x "$BACKUP/bin/php74" ] && REF=$BACKUP/bin/php74
"$REF" -v 2>/dev/null | head -1 | grep -q 'PHP 7.4.30' || die "reference binary $REF is not the original 7.4.30"
TMP=/tmp/php74-fix.$$; mkdir -p $TMP; trap 'rm -rf $TMP' EXIT
startup_warnings() { # php-binary -> sorted startup warnings with the real config
  "$1" -c "$CLI_INI" -m 2>&1 | grep -iE 'warning|unable to (load|initialize)|undefined symbol' | sort -u
}
modules_count() { "$1" -c "$CLI_INI" -m 2>/dev/null | grep -cvE '^\[|^$'; }
# config warnings that already exist with the original binary are not ours;
# fail only on warnings the new binary adds, or on fewer loaded modules.
# The baseline is taken once, before anything is replaced (original core + modules)
check_against_ref() { # php-binary label
  if [ ! -f $TMP/ref.count ]; then
    startup_warnings "$REF" > $TMP/ref.txt
    modules_count "$REF" > $TMP/ref.count
  fi
  startup_warnings "$1" > $TMP/new.txt
  extra=$(grep -vxF -f $TMP/ref.txt $TMP/new.txt || true)
  nr=$(cat $TMP/ref.count); nn=$(modules_count "$1")
  if [ -n "$extra" ] || [ "$nn" -lt "$nr" ]; then
    echo "$extra" >&2; echo "modules: original=$nr new=$nn" >&2
    return 1
  fi
  [ -s $TMP/ref.txt ] && echo "   (warnings from your own config, identical with the original: $(wc -l < $TMP/ref.txt))"
  echo "   $2: OK ($nn modules, same as the original)"
}
chmod 755 $FILES
./php74 -v 2>/dev/null | head -1 | grep -q 'PHP 7.4.33' || die "php74 does not start"
./php74-fpm -n -v | head -1 | grep -q 'PHP 7.4.33' || die "php74-fpm does not start"
check_against_ref ./php74 "new php74 + current extensions" || die "the new binary loads extensions differently than the original"
for m in $MODS; do
  r=$(./php74 -n -d extension="$HERE/modules/$m" -r 'echo "ok";' 2>&1)
  [ "$r" = ok ] || die "new extension $m does not load: $r"
done
echo "   new extensions ($(echo $MODS | wc -w)): OK"

echo "== backup to $BACKUP"
if [ ! -d "$BACKUP" ]; then
  mkdir -p "$BACKUP/bin" "$BACKUP/modules"
  for f in $FILES; do cp -p "$BIN/$f" "$BACKUP/bin/$f"; done
  for m in $MODS; do cp -p "$MODDIR/$m" "$BACKUP/modules/$m"; done
else
  echo "   existing backup kept"
fi

echo "== installing"
for m in $MODS; do replace "$HERE/modules/$m" "$MODDIR/$m"; done
for f in $FILES; do replace "$HERE/$f" "$BIN/$f"; done

echo "== checking after install"
if ! check_against_ref "$BIN/php74" "installed + new extensions"; then
  echo "Extensions fail to load: rolling back to the original automatically." >&2
  sh "$HERE/uninstall.sh"
  exit 1
fi
"$BIN/php74" -v 2>/dev/null | head -1

echo "== reloading php74-fpm (re-exec with the new binary, no downtime)"
pids=$(fpm74_masters)
if [ -n "$pids" ]; then
  for p in $pids; do kill -USR2 "$p"; done
  sleep 3
  for p in $(fpm74_masters); do echo "   php74-fpm master pid $p -> $(readlink /proc/$p/exe)"; done
else
  echo "   no php74-fpm master running (it starts when Web Station uses it)"
fi
echo "Done. Check your websites. To roll back: sh $HERE/uninstall.sh"
