#!/bin/bash
# Run upstream phpt tests for the new and the original binary (baseline).
W=$HOME/synobuild
SYSROOT=$W/root/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root
export LD_LIBRARY_PATH=$W/deps/lib:$SYSROOT/usr/lib
SRC=$W/src/php-7.4.33
cd "$SRC"
T="tests/basic tests/lang Zend/tests/bug79919.phpt Zend/tests/bug71474.phpt ext/standard/tests/general_functions ext/session/tests/rfc1867*.phpt main/tests"
for v in new orig; do
  if [ $v = new ]; then B=$W/out; else B=$W/syno/pkg/usr/local/bin; fi
  echo "== $v: $($B/php74 -n -v | head -1)"
  TEST_PHP_EXECUTABLE=$B/php74 TEST_PHP_CGI_EXECUTABLE=$B/php74-cgi NO_INTERACTION=1 REPORT_EXIT_STATUS=0 \
    $B/php74 -n run-tests.php -q -j4 $(ls -d $T 2>/dev/null) > /tmp/rt-$v.txt 2>&1
  grep -E '^(Tests (passed|failed|skipped)|Number of tests)' /tmp/rt-$v.txt
  grep -aoE 'FAIL .*\[[^]]+\]' /tmp/rt-$v.txt | sed 's/^FAIL /   /' | sort -u > /tmp/fail-$v.txt
done
echo "== FAIL only with the new binary (regressions):"
comm -23 /tmp/fail-new.txt /tmp/fail-orig.txt | head -40
echo "== FAIL only with the original (fixed):"
comm -13 /tmp/fail-new.txt /tmp/fail-orig.txt | head -40
