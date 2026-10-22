#!/bin/bash
# Compare rebuilt extensions with Synology's originals (linkage, features, phpt tests).
set -uo pipefail

W=$HOME/synobuild
SYSROOT=$W/root/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root
ORIG=$W/syno/pkg/usr/local/lib/php74/modules
NEW=$W/out/modules
CORE=$W/out
SRC=$W/src-ext/php-7.4.33
# libxslt only exists in our staging dir (on the NAS it comes from DSM)
export LD_LIBRARY_PATH=$W/deps/lib:$W/extdeps/xslt/lib:$W/extdeps/freetds/lib:$SYSROOT/usr/lib:$W/syno/pkg/usr/lib

sec() { # binary-dir ext-dir ext -> phpinfo section of that ext
  local mod=$3 name=$3
  case $3 in phar) name=Phar;; esac
  "$1/php74" -n -d extension="$2/$mod.so" -i 2>&1 |
    awk -v n="$name" '$0==n{p=1;next} /^Directive/{p=0} p&&NF' | grep -vE 'Active (Persistent )?Links|Total Links'
}

for e in $(ls "$NEW" | sed 's/\.so$//'); do
  echo "=================== $e"
  a=$(readelf -d "$ORIG/$e.so" | awk '/NEEDED/{gsub(/[\[\]]/,"",$5); print $5}' | sort | tr '\n' ' ')
  b=$(readelf -d "$NEW/$e.so" | awk '/NEEDED/{gsub(/[\[\]]/,"",$5); print $5}' | sort | tr '\n' ' ')
  [ "$a" = "$b" ] && echo "NEEDED identical: $b" || { echo "NEEDED orig: $a"; echo "NEEDED new : $b"; }
  echo "max GLIBC: $(objdump -T "$NEW/$e.so" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)"
  load=$("$CORE/php74" -n -d extension="$NEW/$e.so" -m 2>&1 | grep -iE 'warning|unable|undefined')
  [ -n "$load" ] && echo "LOAD: $load"
  d=$(diff <(sec "$CORE" "$ORIG" $e) <(sec "$CORE" "$NEW" $e))
  [ -z "$d" ] && echo "phpinfo identical ($(sec "$CORE" "$NEW" $e | wc -l) lines)" || { echo "phpinfo differs:"; echo "$d" | head -10; }
done

echo
echo "=================== phpt tests (new core + original ext vs new core + new ext)"
cd "$SRC"
for e in $(ls "$NEW" | sed 's/\.so$//'); do
  t=ext/$e/tests; [ -d "$t" ] || continue
  for v in orig new; do
    dir=$ORIG; [ $v = new ] && dir=$NEW
    deps="-d extension=$dir/$e.so"
    TEST_PHP_EXECUTABLE=$CORE/php74 NO_INTERACTION=1 \
      "$CORE/php74" -n run-tests.php -q -j4 -n $deps "$t" > "/tmp/ext-$e-$v.txt" 2>&1
    grep -aoE 'FAIL .*\[[^]]+\]' "/tmp/ext-$e-$v.txt" | sed 's/^FAIL //' | sort -u > "/tmp/ext-$e-$v.fail"
  done
  p=$(grep -aE '^Tests passed' "/tmp/ext-$e-new.txt" | awk '{print $4}')
  f=$(grep -aE '^Tests failed' "/tmp/ext-$e-new.txt" | awk '{print $4}')
  reg=$(comm -13 "/tmp/ext-$e-orig.fail" "/tmp/ext-$e-new.fail")
  fix=$(comm -23 "/tmp/ext-$e-orig.fail" "/tmp/ext-$e-new.fail")
  printf "%-11s passed=%-4s failed=%-3s regressions=%s fixed=%s\n" "$e" "${p:-?}" "${f:-?}" "$(echo -n "$reg" | grep -c .)" "$(echo -n "$fix" | grep -c .)"
  [ -n "$reg" ] && echo "$reg" | sed 's/^/    REGRESSION: /'
  [ -n "$fix" ] && echo "$fix" | sed 's/^/    fixed     : /'
done
