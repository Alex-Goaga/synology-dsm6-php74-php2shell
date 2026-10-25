#!/bin/bash
# Serve test-site/index.php with the rebuilt php74 (+ all extensions) and a
# throwaway MariaDB 10.3, then exercise it like a browser would.
B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
M=$W/mariadb; BASE=$M/mariadb-10.3.39-linux-systemd-x86_64; SOCK=$M/mysqld.sock
ORIG_MOD=$W/syno/pkg/usr/local/lib/php74/modules; NEW_MOD=$W/out/modules
SITE=$(cd "$B/.." && pwd)/test-site
export LD_LIBRARY_PATH=$W/deps/lib:$W/extdeps/xslt/lib:$SYSROOT/usr/lib:$W/syno/pkg/usr/lib

bash "$B/get-mariadb.sh" || exit 1
rm -rf $M/data && mkdir -p $M/data
( export LD_LIBRARY_PATH=$M/aio/root/usr/lib/x86_64-linux-gnu
  $BASE/scripts/mysql_install_db --no-defaults --basedir=$BASE --datadir=$M/data >/dev/null 2>&1
  $BASE/bin/mysqld --no-defaults --basedir=$BASE --datadir=$M/data --socket=$SOCK --port=33306 --bind-address=127.0.0.1 --log-error=$M/err.log --pid-file=$M/mysqld.pid & )
for i in $(seq 1 30); do [ -S $SOCK ] && break; sleep 1; done

EXT=""; for so in $ORIG_MOD/*.so; do n=$(basename $so); p=$so; [ -f $NEW_MOD/$n ] && p=$NEW_MOD/$n
  case " ${EXCLUDE:-} " in *" ${n%.so} "*) continue;; esac  # simulate a trimmed Web Station profile
  case $n in opcache.so|xdebug.so) ;; *) EXT="$EXT -d extension=$p";; esac; done
"$W/out/php74" -n $EXT -d session.save_path=/tmp -S 127.0.0.1:8099 -t $SITE >/tmp/site.log 2>&1 &
SRV=$!; sleep 1
echo "== lint: $("$W/out/php74" -n -l $SITE/index.php)"
echo "== GET"
env -u LD_LIBRARY_PATH curl -s -c /tmp/cj -b /tmp/cj http://127.0.0.1:8099/ | sed 's/<[^>]*>/ /g' | grep -E '✔|✘|ⓘ' | sed 's/  */ /g' | head -30
echo "== POST (DB + upload)"
echo "test file äöü" > /tmp/up.txt
env -u LD_LIBRARY_PATH curl -s -c /tmp/cj -b /tmp/cj -F action=test -F host=localhost -F port=0 -F socket=$SOCK -F user=root -F pass= -F name=php74_test -F file=@/tmp/up.txt http://127.0.0.1:8099/ \
  | sed 's/<[^>]*>/ /g' | grep -E 'MariaDB|upload|Session|Test ăîșț' | sed 's/  */ /g' | head -12
echo "== public IP via X-Forwarded-For (must be 403)"
env -u LD_LIBRARY_PATH curl -s -o /dev/null -w '%{http_code}\n' -H 'X-Forwarded-For: 8.8.8.8' http://127.0.0.1:8099/
echo "== server errors"; grep -iE 'warning|error|fatal' /tmp/site.log | head -5
kill $SRV; kill $(cat $M/mysqld.pid) 2>/dev/null
