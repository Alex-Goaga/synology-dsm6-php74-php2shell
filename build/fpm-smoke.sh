#!/bin/bash
W=$HOME/synobuild
export LD_LIBRARY_PATH=$W/deps/lib:$W/root/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root/usr/lib
D=/tmp/fpmtest; rm -rf $D; mkdir -p $D
cat > $D/fpm.conf <<CONF
[global]
error_log = $D/fpm.log
[www]
listen = 127.0.0.1:9074
pm = static
pm.max_children = 2
CONF
cat > $D/t.php <<'PHP'
<?php
echo PHP_VERSION, " ", PHP_SAPI, " GET=", json_encode($_GET), " POST=", json_encode($_POST),
  " FILES=", isset($_FILES['f']) ? $_FILES['f']['name'] . ':' . file_get_contents($_FILES['f']['tmp_name']) : 'none';
PHP
B=${1:-$W/out}
$B/php74-fpm -n -y $D/fpm.conf -F -d upload_tmp_dir=$D &
pid=$!; sleep 2
python3 -I "$(cd "$(dirname "$0")" && pwd)/fpm-smoke.py" $D/t.php
kill -QUIT $pid; wait $pid 2>/dev/null
grep -iE 'error|warn' $D/fpm.log | head -5
