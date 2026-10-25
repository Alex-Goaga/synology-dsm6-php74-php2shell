#!/bin/bash
# Full verification of the final build (core + rebuilt extensions).
B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
echo "############ 1. API inventory (original vs new)"
bash $B/parity.sh | tail -n +3
echo "############ 2. symbols: new extensions + all originals with the new core"
bash $B/check-symbols.sh
bash $B/check-symbols.sh "$W/syno/pkg/usr/local/lib/php74/modules/*.so"
echo "############ 3. extensions: linkage, phpinfo, tests"
bash $B/verify-ext.sh 2>&1 | grep -E 'LOAD|passed=|REGRESIE'
echo "############ 4. core: PHP tests new vs original"
bash $B/run-tests.sh 2>&1 | tail -14
echo "############ 5. real FPM (GET + multipart upload)"
bash $B/fpm-smoke.sh
echo "############ 6. MariaDB 10.3"
bash $B/test-mariadb.sh 2>&1 | grep -E 'RESULT|FAIL|ready'
echo "############ 7. core linkage"
readelf -d $W/out/php74-fpm | grep -E 'NEEDED|RPATH' | awk '{print $NF}' | tr '\n' ' '; echo
echo "max GLIBC: $(objdump -T $W/out/php74-fpm | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)"
