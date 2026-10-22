#!/bin/sh
# Compare the extensions loaded by the original Synology php74 (backup) and the
# new one with EXACTLY the ini files a website's FPM worker uses. Read-only.
# Take the command from the test page ("Diagnostic command"), e.g.:
#   sudo -i ; sh diag-fpm.sh '/path/php.ini' '/path/a.ini,/path/b.ini'

ORIG=/var/packages/PHP7.4/target/.orig-7.4.30-0009/bin/php74
NEW=/var/packages/PHP7.4/target/usr/local/bin/php74
INI=$1
SCANNED=$2

[ -x "$ORIG" ] || { echo "original binary missing from backup: $ORIG"; exit 1; }
[ -n "$INI" ] || { echo "use the command shown on the test page (section 'PHP configuration')"; exit 1; }

# rebuild the scan dir from the listed files so both binaries read the same set
T=/tmp/diag-fpm.$$; mkdir -p "$T/scan"; trap 'rm -rf "$T"' EXIT
echo "$SCANNED" | tr ',' '\n' | while read -r f; do [ -n "$f" ] && ln -s "$f" "$T/scan/$(basename "$f")"; done
CARG=""; [ "$INI" != "(none)" ] && CARG="-c $INI"

echo "################ extension= lines in the site's configuration"
for f in $([ "$INI" != "(none)" ] && echo "$INI") $(echo "$SCANNED" | tr ',' ' '); do
  [ -f "$f" ] && grep -nE '^[[:space:]]*;?[[:space:]]*(zend_)?extension[[:space:]]*=' "$f" | sed "s|^|$f:|"
done

for v in orig new; do
  b=$ORIG; [ $v = new ] && b=$NEW
  echo "################ $v: $("$b" -v 2>/dev/null | head -1 | cut -d' ' -f1-2)"
  PHP_INI_SCAN_DIR="$T/scan" "$b" $CARG -r 'echo implode("\n", get_loaded_extensions()), "\n";' 2>"$T/$v.err" | sort > "$T/$v.ext"
  echo "$(wc -l < "$T/$v.ext") extensions: $(tr '\n' ' ' < "$T/$v.ext")"
  grep -iE 'unable|undefined|warning' "$T/$v.err" | head -10
done
echo "################ differences (< original only, > new only)"
diff "$T/orig.ext" "$T/new.ext" && echo "none: both binaries load exactly the same extensions with the site's configuration"
