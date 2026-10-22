<?php
/*
 * PHP 7.4 test page (Synology) – after installing the PHP2Shell fix.
 * Reachable from the local network only. DELETE IT after testing.
 */
declare(strict_types=1);

// --- LAN-only access -------------------------------------------------------------
// behind DSM's reverse proxy REMOTE_ADDR is 127.0.0.1, so the forwarded
// client addresses must be private too
function is_lan(string $ip): bool {
    $ip = trim($ip);
    return filter_var($ip, FILTER_VALIDATE_IP) !== false
        && filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false;
}
$ips = [$_SERVER['REMOTE_ADDR'] ?? ''];
foreach (['HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP'] as $hdr) {
    if (!empty($_SERVER[$hdr])) $ips = array_merge($ips, explode(',', $_SERVER[$hdr]));
}
if (in_array(false, array_map('is_lan', $ips), true)) {
    http_response_code(403);
    exit('Access allowed from the local network only.');
}

session_start();
$_SESSION['visits'] = ($_SESSION['visits'] ?? 0) + 1;

function h($s): string { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

$results = [];
function check(string $name, callable $fn): void {
    global $results;
    try {
        $r = $fn();
        $results[] = [$name, $r[0], $r[1]];
    } catch (Throwable $e) {
        $results[] = [$name, false, get_class($e) . ': ' . $e->getMessage()];
    }
}

// --- PHP checks --------------------------------------------------------------------
check('PHP version', fn() => [PHP_VERSION === '7.4.33', PHP_VERSION . ' (' . PHP_SAPI . ')' . (PHP_VERSION === '7.4.33' ? ' – the patched build' : ' – NOT the new binary!')]);
check('PHP2Shell protection', fn() => [ini_get('max_multipart_body_parts') !== false, 'max_multipart_body_parts exists (only present in the patched build)']);
foreach (['mysqli', 'pdo_mysql', 'openssl', 'curl', 'gd', 'mbstring', 'intl', 'zip', 'json', 'xml', 'soap', 'exif'] as $ext) {
    // a profile may leave extensions off on purpose, so missing ones are informational
    check("Extension $ext", fn() => extension_loaded($ext) ? [true, 'loaded'] : [null, 'not enabled in the Web Station PHP profile']);
}
check('DNS (checkdnsrr / dns_get_record)', function () {
    if (!function_exists('dns_get_record')) return [false, 'DNS functions are missing'];
    $r = @dns_get_record('synology.com', DNS_A);
    return [true, 'functions present; synology.com → ' . ($r ? $r[0]['ip'] : 'no answer (does the NAS have DNS/Internet?)')];
});
check('fnmatch()', fn() => [function_exists('fnmatch') && fnmatch('*.php', 'index.php'), 'OK']);
check('OpenSSL', fn() => extension_loaded('openssl')
    ? [strlen(openssl_random_pseudo_bytes(16)) === 16, OPENSSL_VERSION_TEXT]
    : [null, 'openssl extension not enabled in the profile (HTTPS still works through curl)']);
check('Outbound HTTPS (curl)', function () {
    $c = curl_init('https://www.php.net/');
    curl_setopt_array($c, [CURLOPT_NOBODY => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 8]);
    $ok = curl_exec($c) !== false;
    $msg = $ok ? 'HTTP ' . curl_getinfo($c, CURLINFO_HTTP_CODE) : curl_error($c);
    curl_close($c);
    return [$ok, $msg . ($ok ? '' : ' (expected if the NAS has no Internet access)')];
});
check('mbstring (accented characters)', function () {
    $s = mb_strtoupper('ăîșț äöü éñ');
    return [$s === 'ĂÎȘȚ ÄÖÜ ÉÑ', $s];
});
// null = informational: ICU data comes from DSM, not PHP (same result with the original binary)
check('intl (locale formatting)', function () {
    try {
        return [true, (new NumberFormatter('en_US', NumberFormatter::CURRENCY))->formatCurrency(1234.5, 'USD')
            . ' · ' . (new NumberFormatter('de_DE', NumberFormatter::CURRENCY))->formatCurrency(1234.5, 'EUR')];
    } catch (Throwable $e) {
        return [null, "DSM's ICU data lacks these locales (unrelated to the PHP update)"];
    }
});
check('Session', fn() => [true, 'visits in this session: ' . $_SESSION['visits'] . ' (refresh, it must increase)']);
$img = '';
check('GD (generated image)', function () use (&$img) {
    $im = imagecreatetruecolor(160, 40);
    imagefill($im, 0, 0, imagecolorallocate($im, 30, 120, 60));
    imagestring($im, 5, 12, 12, 'PHP ' . PHP_VERSION, imagecolorallocate($im, 255, 255, 255));
    ob_start(); imagepng($im); $img = base64_encode(ob_get_clean()); imagedestroy($im);
    return [true, 'PNG generated (see below)'];
});

// --- upload (multipart – exactly the code path fixed for PHP2Shell) ----------------
$upload = null;
if (!empty($_FILES['file']['name'])) {
    $f = $_FILES['file'];
    $upload = $f['error'] === UPLOAD_ERR_OK
        ? [true, h($f['name']) . ' · ' . number_format($f['size']) . ' bytes · sha256 ' . substr(hash_file('sha256', $f['tmp_name']), 0, 16) . '…']
        : [false, 'upload error code ' . $f['error']];
}

// --- database ------------------------------------------------------------------------
$db = [
    'host' => $_POST['host'] ?? 'localhost',
    'port' => (int)($_POST['port'] ?? 3307),
    'socket' => $_POST['socket'] ?? '/run/mysqld/mysqld10.sock',
    'user' => $_POST['user'] ?? 'root',
    'pass' => $_POST['pass'] ?? '',
    'name' => $_POST['name'] ?? 'php74_test',
];
$dbResults = [];
$rows = [];
if (($_POST['action'] ?? '') !== '') {
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    try {
        $sock = $db['host'] === 'localhost' && $db['socket'] !== '' ? $db['socket'] : null;
        if ($sock !== null && !@file_exists($sock)) {
            $found = @glob('/run/mysqld/*.sock') ?: [];
            $dbResults[] = [null, "socket $sock does not exist" . ($found ? '; found: ' . implode(', ', $found) : '') . " – trying TCP 127.0.0.1:{$db['port']}"];
            $sock = null;
            $db['host'] = '127.0.0.1';
        }
        $m = new mysqli($db['host'], $db['user'], $db['pass'], '', $db['port'], $sock);
        $m->set_charset('utf8mb4');
        $dbResults[] = [true, 'mysqli connected: MariaDB/MySQL ' . $m->server_info . ($sock ? " (socket $sock)" : " (TCP {$db['host']}:{$db['port']})")];
        $name = preg_replace('/[^A-Za-z0-9_]/', '', $db['name']);
        $m->query("CREATE DATABASE IF NOT EXISTS `$name` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
        $m->select_db($name);
        if ($_POST['action'] === 'drop') {
            $m->query('DROP TABLE IF EXISTS messages');
            $dbResults[] = [true, "table messages dropped from `$name`"];
        } else {
            // TIMESTAMP (not DATETIME) so the default works on MariaDB 5.5 too
            $m->query('CREATE TABLE IF NOT EXISTS messages (id INT AUTO_INCREMENT PRIMARY KEY, text VARCHAR(255), created TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB');
            $text = trim($_POST['message'] ?? '') ?: 'Test ăîșț äöü 😀 ' . date('H:i:s');
            $st = $m->prepare('INSERT INTO messages (text) VALUES (?)');
            $st->bind_param('s', $text);
            $st->execute();
            $newId = $m->insert_id;
            $dbResults[] = [true, 'mysqli prepared INSERT: row #' . $newId];
            $rows = $m->query('SELECT id, text, created FROM messages ORDER BY id DESC LIMIT 10')->fetch_all(MYSQLI_ASSOC);
            $back = $rows[0]['text'] ?? '';
            $dbResults[] = [$back === $text, 'mysqli SELECT: ' . count($rows) . ' rows, accents/emoji ' . ($back === $text ? 'correct' : 'WRONG')];
            if (extension_loaded('pdo_mysql')) {
                $pdo = new PDO($sock ? "mysql:unix_socket=$sock;dbname=$name;charset=utf8mb4" : "mysql:host={$db['host']};port={$db['port']};dbname=$name;charset=utf8mb4",
                    $db['user'], $db['pass'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
                $q = $pdo->prepare('SELECT text FROM messages WHERE id = ?');
                $q->execute([$newId]);
                $dbResults[] = [$q->fetchColumn() === $text, 'PDO prepared SELECT: same row read back correctly'];
            } else {
                $dbResults[] = [null, 'pdo_mysql not enabled in the profile – tested through mysqli only'];
            }
        }
        $m->close();
    } catch (Throwable $e) {
        $dbResults[] = [false, $e->getMessage()];
    }
}
$okAll = !in_array(false, array_column($results, 1), true);
$iniLoaded = php_ini_loaded_file() ?: '(none)';
$iniScanned = array_values(array_filter(array_map('trim', explode(',', (string)php_ini_scanned_files()))));
$exts = get_loaded_extensions();
sort($exts, SORT_FLAG_CASE | SORT_STRING);
// one-line command for diag-fpm.sh with exactly the files this FPM worker loaded
$diagCmd = 'sh diag-fpm.sh ' . escapeshellarg($iniLoaded) . ($iniScanned ? ' ' . escapeshellarg(implode(',', $iniScanned)) : '');

// --- compatibility report (pre-fills the GitHub issue form) -------------------------
const REPO_URL = 'https://github.com/Alex-Goaga/synology-dsm6-php74-php2shell';

// open_basedir may hide these files; an empty string means "unknown"
function read_file_quiet(string $file): string {
    $s = @file_get_contents($file);
    return $s === false ? '' : trim($s);
}
$ver = @parse_ini_string(read_file_quiet('/etc.defaults/VERSION')) ?: [];
$pkg = @parse_ini_string(read_file_quiet('/var/packages/PHP7.4/INFO')) ?: [];
$cpu = preg_match('/^model name\s*:\s*(.+)$/m', read_file_quiet('/proc/cpuinfo'), $mm) ? trim($mm[1]) : '';
$syno = [
    'model' => read_file_quiet('/proc/sys/kernel/syno_hw_version'),
    'dsm' => isset($ver['productversion'])
        ? $ver['productversion'] . '-' . ($ver['buildnumber'] ?? '?') . (!empty($ver['smallfixnumber']) ? ' Update ' . $ver['smallfixnumber'] : '')
        : '',
    'cpu' => $cpu,
    'package' => $pkg['version'] ?? '',
];
$mark = fn($ok) => $ok === null ? 'i' : ($ok ? 'OK' : 'FAIL');
$lines = [
    'Model: ' . ($syno['model'] ?: 'unknown'),
    'DSM: ' . ($syno['dsm'] ?: 'unknown'),
    'CPU: ' . ($syno['cpu'] ?: 'unknown'),
    'PHP7.4 package: ' . ($syno['package'] ?: 'unknown') . ' (binaries replaced by this project)',
    'PHP: ' . PHP_VERSION . ' (' . PHP_SAPI . '), web server: ' . strtok((string)($_SERVER['SERVER_SOFTWARE'] ?? 'unknown'), ' '),
    'Extensions loaded: ' . count($exts),
    '',
    'Checks:',
];
foreach ($results as [$n, $ok, $msg]) $lines[] = "[{$mark($ok)}] $n – $msg";
if ($upload) $lines[] = "[{$mark($upload[0])}] File upload";
if ($dbResults) {
    $lines[] = '';
    $lines[] = 'Database:';
    foreach ($dbResults as [$ok, $msg]) $lines[] = "[{$mark($ok)}] $msg";
}
// mask every IPv4 address except loopback so reports never leak LAN/WAN addresses
$report = preg_replace_callback('/\b(?:\d{1,3}\.){3}\d{1,3}\b/',
    fn($m) => $m[0] === '127.0.0.1' ? $m[0] : 'x.x.x.x', implode("\n", $lines));
$issueUrl = REPO_URL . '/issues/new?' . http_build_query([
    'template' => 'compatibility-report.yml',
    'title' => '[Report] ' . ($syno['model'] ?: 'model?') . ' – DSM ' . ($syno['dsm'] ?: '?'),
    'model' => $syno['model'],
    'dsm' => $syno['dsm'],
    'cpu' => $syno['cpu'],
    'report' => $report,
], '', '&', PHP_QUERY_RFC3986);
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PHP 7.4 Test</title>
<style>
  :root { --bg:#f6f7f9; --card:#fff; --text:#1d2433; --muted:#667085; --ok:#16794c; --bad:#b42318; --line:#e4e7ec; }
  @media (prefers-color-scheme: dark) { :root { --bg:#111418; --card:#1a1f26; --text:#e6e9ef; --muted:#98a2b3; --ok:#4ade80; --bad:#f87171; --line:#2b323c; } }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--text); font:15px/1.5 system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
  main { max-width:880px; margin:0 auto; padding:24px 16px 48px; }
  h1 { font-size:22px; margin:0 0 4px; } h2 { font-size:17px; margin:0 0 12px; }
  .sub { color:var(--muted); margin:0 0 20px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:16px; margin-bottom:16px; }
  table { width:100%; border-collapse:collapse; } td { padding:6px 4px; border-top:1px solid var(--line); vertical-align:top; }
  td:first-child { width:34%; color:var(--muted); } .ok { color:var(--ok); font-weight:600; } .bad { color:var(--bad); font-weight:600; } .warn { color:var(--muted); font-weight:600; }
  .banner { padding:12px 16px; border-radius:10px; margin-bottom:16px; font-weight:600; }
  .banner.ok { background:color-mix(in srgb, var(--ok) 14%, transparent); } .banner.bad { background:color-mix(in srgb, var(--bad) 14%, transparent); }
  form { display:grid; grid-template-columns:repeat(auto-fit, minmax(180px, 1fr)); gap:10px; }
  label { display:flex; flex-direction:column; font-size:13px; color:var(--muted); gap:4px; }
  input { font:inherit; padding:7px 9px; border:1px solid var(--line); border-radius:6px; background:var(--bg); color:var(--text); }
  .actions { grid-column:1/-1; display:flex; gap:10px; flex-wrap:wrap; }
  button, a.button { font:inherit; padding:8px 14px; border-radius:6px; border:1px solid var(--line); background:var(--text); color:var(--card); cursor:pointer; text-decoration:none; display:inline-block; }
  button.secondary { background:transparent; color:var(--text); }
  code { font-size:13px; }
</style>
</head>
<body>
<main>
  <h1>PHP 7.4 test on Synology</h1>
  <p class="sub">Verification after installing the patched PHP 7.4.33 (PHP2Shell). This page answers from the local network only. Delete it after testing.</p>

  <div class="banner <?= $okAll ? 'ok' : 'bad' ?>"><?= $okAll ? '✔ All PHP checks passed' : '✘ Some checks failed – see the details in the table' ?></div>

  <section class="card">
    <h2>PHP</h2>
    <table>
      <?php foreach ($results as [$n, $ok, $msg]): ?>
        <tr><td><?= h($n) ?></td><td><span class="<?= $ok === null ? 'warn' : ($ok ? 'ok' : 'bad') ?>"><?= $ok === null ? 'ⓘ' : ($ok ? '✔' : '✘') ?></span> <?= h($msg) ?></td></tr>
      <?php endforeach; ?>
      <?php if ($img): ?><tr><td>GD image</td><td><img src="data:image/png;base64,<?= $img ?>" alt="image generated by GD" width="160" height="40"></td></tr><?php endif; ?>
      <?php if ($upload): ?><tr><td>File upload</td><td><span class="<?= $upload[0] ? 'ok' : 'bad' ?>"><?= $upload[0] ? '✔' : '✘' ?></span> <?= $upload[1] ?></td></tr><?php endif; ?>
    </table>
  </section>

  <section class="card">
    <h2>PHP configuration used by this site</h2>
    <table>
      <tr><td>Loaded php.ini</td><td><code><?= h($iniLoaded) ?></code></td></tr>
      <tr><td>Additional .ini files</td><td><?php if ($iniScanned): foreach ($iniScanned as $f): ?><code><?= h($f) ?></code><br><?php endforeach; else: ?>(none)<?php endif; ?></td></tr>
      <tr><td>Loaded extensions (<?= count($exts) ?>)</td><td><?= h(implode(', ', $exts)) ?></td></tr>
      <tr><td>Diagnostic command</td><td><code><?= h($diagCmd) ?></code></td></tr>
    </table>
  </section>

  <section class="card">
    <h2>Database (MariaDB) + upload</h2>
    <form method="post" enctype="multipart/form-data">
      <label>Host <input name="host" value="<?= h($db['host']) ?>"></label>
      <label>Port (TCP) <input name="port" value="<?= h($db['port']) ?>"></label>
      <label>Socket (for localhost) <input name="socket" value="<?= h($db['socket']) ?>"></label>
      <label>User <input name="user" value="<?= h($db['user']) ?>" autocomplete="off"></label>
      <label>Password <input name="pass" type="password" value="" autocomplete="new-password"></label>
      <label>Test database <input name="name" value="<?= h($db['name']) ?>"></label>
      <label style="grid-column:1/-1">Message to store <input name="message" placeholder="optional – defaults to a text with accents and emoji"></label>
      <label style="grid-column:1/-1">File for the upload test (optional) <input type="file" name="file"></label>
      <div class="actions">
        <button name="action" value="test">Test connection, write and read</button>
        <button name="action" value="drop" class="secondary">Drop test table</button>
      </div>
    </form>
    <?php if ($dbResults): ?>
      <table style="margin-top:14px">
        <?php foreach ($dbResults as [$ok, $msg]): ?>
          <tr><td>MariaDB</td><td><span class="<?= $ok === null ? 'warn' : ($ok ? 'ok' : 'bad') ?>"><?= $ok === null ? 'ⓘ' : ($ok ? '✔' : '✘') ?></span> <?= h($msg) ?></td></tr>
        <?php endforeach; ?>
      </table>
    <?php endif; ?>
    <?php if ($rows): ?>
      <table style="margin-top:14px">
        <?php foreach ($rows as $r): ?><tr><td>#<?= (int)$r['id'] ?> · <?= h($r['created']) ?></td><td><?= h($r['text']) ?></td></tr><?php endforeach; ?>
      </table>
    <?php endif; ?>
    <p class="sub" style="margin-top:12px">MariaDB 10 on DSM 6: socket <code>/run/mysqld/mysqld10.sock</code> or TCP port <code>3307</code>. MariaDB 5: socket <code>/run/mysqld/mysqld.sock</code>, port <code>3306</code>. The password is not stored anywhere.</p>
  </section>

  <section class="card">
    <h2>Share your result</h2>
    <p class="sub">Help others know which Synology models work: run the database test above first, then send this report. IP addresses are masked automatically; please check the text before submitting.</p>
    <?php if (!$syno['model'] || !$syno['dsm']): ?>
      <p class="sub">The model or DSM version could not be read (Web Station's <code>open_basedir</code> may block it) – please fill them in on GitHub. You can find them in DSM → Control Panel → Info Center.</p>
    <?php endif; ?>
    <textarea id="report" readonly rows="14" style="width:100%;font:13px/1.45 ui-monospace,Consolas,monospace;padding:10px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--text)"><?= h($report) ?></textarea>
    <div class="actions" style="margin-top:10px">
      <a class="button" href="<?= h($issueUrl) ?>" target="_blank" rel="noopener noreferrer">Report on GitHub</a>
      <button type="button" class="secondary" id="copy">Copy report</button>
    </div>
  </section>
  <script>
    document.getElementById('copy').addEventListener('click', function () {
      var t = document.getElementById('report');
      t.select();
      (navigator.clipboard ? navigator.clipboard.writeText(t.value) : Promise.reject()).catch(function () { document.execCommand('copy'); });
      this.textContent = 'Copied';
    });
  </script>
</main>
</body>
</html>
