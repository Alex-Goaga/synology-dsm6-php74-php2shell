#!/bin/bash
# Run a throwaway MariaDB 10.3 (same major as DSM 6.2's MariaDB 10 package) as
# the current user and exercise mysqli + PDO_mysql with the rebuilt php74
# (mysqlnd is in core and carries the wire-protocol security fixes).
set -uo pipefail

B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
M=$W/mariadb
BASE=$M/mariadb-10.3.39-linux-systemd-x86_64
DATA=$M/data
SOCK=$M/mysqld.sock
PORT=33306
MOD=$W/syno/pkg/usr/local/lib/php74/modules
export LD_LIBRARY_PATH=$W/deps/lib:$SYSROOT/usr/lib:$W/syno/pkg/usr/lib

bash "$B/get-mariadb.sh" || exit 1
rm -rf "$DATA" && mkdir -p "$DATA"
( export LD_LIBRARY_PATH=$M/aio/root/usr/lib/x86_64-linux-gnu  # libaio for mysqld only
  "$BASE/scripts/mysql_install_db" --no-defaults --basedir="$BASE" --datadir="$DATA" >"$M/install.log" 2>&1
  "$BASE/bin/mysqld" --no-defaults --basedir="$BASE" --datadir="$DATA" --socket="$SOCK" --port=$PORT \
     --bind-address=127.0.0.1 --log-error="$M/err.log" --pid-file="$M/mysqld.pid" &
)
for i in $(seq 1 30); do [ -S "$SOCK" ] && break; sleep 1; done
[ -S "$SOCK" ] || { echo "MariaDB did not start"; tail -20 "$M/err.log"; exit 1; }
MOD_INI="-d extension=$MOD/mysqli.so -d extension=$MOD/pdo_mysql.so"
# create the test db/user from PHP (the mysql CLI would need libncurses5)
"$W/out/php74" -n $MOD_INI -r '
  $db = new mysqli("localhost", "root", "", "", 0, $argv[1]);
  foreach (["CREATE DATABASE t CHARACTER SET utf8mb4",
            "CREATE USER \"web\"@\"127.0.0.1\" IDENTIFIED BY \"test-password\"",
            "CREATE USER \"web\"@\"localhost\" IDENTIFIED BY \"test-password\"",
            "GRANT ALL ON t.* TO \"web\"@\"127.0.0.1\"", "GRANT ALL ON t.* TO \"web\"@\"localhost\""] as $q)
    $db->query($q) or die($db->error . "\n");
  echo "MariaDB ", $db->server_info, " ready\n";' "$SOCK" || exit 1

cat > /tmp/db.php <<'PHP'
<?php
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
[$sock, $port] = [$argv[1], (int)$argv[2]];
$ok = 0; $fail = 0;
function check($name, $cond) { global $ok, $fail; echo ($cond ? "  OK   " : "  FAIL "), $name, "\n"; $cond ? $ok++ : $fail++; }

foreach (['tcp' => ['127.0.0.1', $port, null], 'socket' => ['localhost', 0, $sock]] as $via => [$h, $p, $s]) {
    echo "mysqli via $via\n";
    $db = new mysqli($h, 'web', 'test-password', 't', $p, $s);
    $db->set_charset('utf8mb4');
    check('server ' . $db->server_info, $db->server_version >= 100300);
    $db->query('DROP TABLE IF EXISTS x');
    $db->query('CREATE TABLE x (id INT AUTO_INCREMENT PRIMARY KEY, s VARCHAR(100), d DATETIME(6), f DOUBLE, b LONGBLOB, n INT NULL) ENGINE=InnoDB');
    $st = $db->prepare('INSERT INTO x (s, d, f, b, n) VALUES (?, ?, ?, ?, ?)');
    $s1 = 'ăîșțâ 😀 ünïcødé'; $d1 = '2026-10-22 12:34:56.123456'; $f1 = 3.14159; $b1 = random_bytes(5 * 1024 * 1024); $n1 = null;
    $st->bind_param('ssdsi', $s1, $d1, $f1, $b1, $n1);
    check('prepared insert (5 MB blob)', $st->execute());
    $r = $db->query('SELECT * FROM x')->fetch_assoc();
    check('text query utf8mb4', $r['s'] === $s1);
    check('blob roundtrip', $r['b'] === $b1);
    check('NULL', $r['n'] === null);
    $st = $db->prepare('SELECT s, d, f, n FROM x WHERE id = ?');
    $id = 1; $st->bind_param('i', $id); $st->execute();
    $row = $st->get_result()->fetch_assoc();
    check('prepared select datetime(6)', $row['d'] === $d1 && abs($row['f'] - $f1) < 1e-9);
    $db->begin_transaction(); $db->query("INSERT INTO x (s) VALUES ('rb')"); $db->rollback();
    check('rollback', (int)$db->query('SELECT COUNT(*) c FROM x')->fetch_assoc()['c'] === 1);
    $res = $db->query('SELECT seq FROM seq_0_to_49999');
    check('50k rows', $res->num_rows === 50000);
    $db->multi_query('SELECT 1; SELECT 2;'); $n = 0; do { if ($rs = $db->store_result()) { $n++; $rs->free(); } } while ($db->more_results() && $db->next_result());
    check('multi_query', $n === 2);
    try { $db->query('SELECT * FROM nope'); check('error handling', false); } catch (mysqli_sql_exception $e) { check('error handling (' . $e->getCode() . ')', $e->getCode() === 1146); }
    $db->close();

    echo "PDO via $via\n";
    $dsn = $s ? "mysql:unix_socket=$s;dbname=t;charset=utf8mb4" : "mysql:host=$h;port=$p;dbname=t;charset=utf8mb4";
    foreach ([true, false] as $emu) {
        $pdo = new PDO($dsn, 'web', 'test-password', [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => $emu]);
        $q = $pdo->prepare('SELECT s, b FROM x WHERE id = :id'); $q->execute([':id' => 1]); $r = $q->fetch(PDO::FETCH_ASSOC);
        check('PDO ' . ($emu ? 'emulated' : 'native') . ' prepare', $r['s'] === $s1 && $r['b'] === $b1);
        check('PDO quote', $pdo->query('SELECT ' . $pdo->quote("o'reilly \\ \"x\"") . ' v')->fetch()['v'] === "o'reilly \\ \"x\"");
    }
}
echo "\nRESULT: $ok OK, $fail FAIL\n";
exit($fail ? 1 : 0);
PHP

INI="$MOD_INI -d memory_limit=256M"
rc=0
for b in "$W/out/php74:NEW (patched 7.4.33)" "$W/syno/pkg/usr/local/bin/php74:ORIGINAL (7.4.30)"; do
  echo "########## ${b#*:}"
  "${b%%:*}" -n $INI /tmp/db.php "$SOCK" $PORT || rc=1
done

kill "$(cat "$M/mysqld.pid")" 2>/dev/null; sleep 2
exit $rc
