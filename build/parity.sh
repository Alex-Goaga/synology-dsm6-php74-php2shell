#!/bin/bash
# API inventory diff: original Synology php74 vs rebuilt php74, all extensions
# loaded (rebuilt ones from out/modules, the rest from the package).
W=$HOME/synobuild
export LC_ALL=C
SYSROOT=$W/root/usr/local/x86_64-pc-linux-gnu/x86_64-pc-linux-gnu/sys-root
ORIG_MOD=$W/syno/pkg/usr/local/lib/php74/modules
NEW_MOD=$W/out/modules
export LD_LIBRARY_PATH=$W/deps/lib:$W/extdeps/xslt/lib:$SYSROOT/usr/lib:$W/syno/pkg/usr/lib

cat > /tmp/inv.php <<'PHP'
<?php
$o = [];
foreach (get_loaded_extensions() as $e) $o[] = "module $e";
foreach (get_loaded_extensions(true) as $e) $o[] = "zend_ext $e";
foreach (get_defined_functions()['internal'] as $f) $o[] = "function $f";
foreach (array_merge(get_declared_classes(), get_declared_interfaces(), get_declared_traits()) as $c) {
    $o[] = "class $c";
    foreach ((new ReflectionClass($c))->getMethods() as $m) if ($m->class === $c) $o[] = "method $c::{$m->name}";
}
foreach (get_defined_constants(true) as $grp => $cs) if ($grp !== 'user')
    foreach ($cs as $k => $v) $o[] = "const $k" . (in_array($k, ['PHP_VERSION','PHP_RELEASE_VERSION','PHP_EXTRA_VERSION','PHP_VERSION_ID','PHP_BINARY','PHP_OS','PHP_OS_FAMILY']) ? '' : (is_scalar($v) ? '=' . var_export($v, true) : ''));
foreach (ini_get_all(null, false) as $k => $v) $o[] = "ini $k=" . var_export($v, true);
foreach (stream_get_wrappers() as $w) $o[] = "wrapper $w";
foreach (stream_get_filters() as $f) $o[] = "filter $f";
foreach (stream_get_transports() as $t) $o[] = "transport $t";
foreach (hash_algos() as $h) $o[] = "hash $h";
if (function_exists('openssl_get_cipher_methods')) foreach (openssl_get_cipher_methods() as $c) $o[] = "cipher $c";
foreach (PDO::getAvailableDrivers() as $d) $o[] = "pdo_driver $d";
sort($o);
echo implode("\n", array_unique($o)), "\n";
PHP

ini() { # module dir for the 12 rebuilt ones
  for so in "$ORIG_MOD"/*.so; do
    n=$(basename "$so"); p="$ORIG_MOD/$n"
    [ -f "$1/$n" ] && p="$1/$n"
    case $n in opcache.so|xdebug.so) echo "-d zend_extension=$p";; *) echo "-d extension=$p";; esac
  done
}
"$W/syno/pkg/usr/local/bin/php74" -n $(ini "$ORIG_MOD") /tmp/inv.php 2>/tmp/inv-orig.err | sort -u > /tmp/inv-orig.txt
"$W/out/php74" -n $(ini "$NEW_MOD") /tmp/inv.php 2>/tmp/inv-new.err | sort -u > /tmp/inv-new.txt
echo "entries: original=$(wc -l < /tmp/inv-orig.txt) new=$(wc -l < /tmp/inv-new.txt)"
echo "startup errors: orig=$(grep -c . /tmp/inv-orig.err) new=$(grep -c . /tmp/inv-new.err)"
echo "===== ONLY IN ORIGINAL (missing from the new build)"
comm -23 /tmp/inv-orig.txt /tmp/inv-new.txt
echo "===== ONLY IN NEW"
comm -13 /tmp/inv-orig.txt /tmp/inv-new.txt
