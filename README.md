# Patched PHP 7.4 for Synology DSM 6.2 (PHP2Shell)

Unofficial drop-in replacement for the Synology **PHP7.4 7.4.30-0009** package on
**DSM 6.2 x86_64**. It fixes **PHP2Shell** (CVE-2026-109618 / CVE-2026-109619) and
backports 90 other PHP security fixes, so older NAS units that cannot run DSM 7 can still
run PHP 7.4 sites.

> Not affiliated with or endorsed by Synology. Use at your own risk, and keep the backup
> that `install.sh` creates.

## Status

| | |
|---|---|
| **Tested in production** | **Synology DS1815+** (Intel Atom C2538 "Avoton"), DSM 6.2, PHP7.4 package 7.4.30-0009, Web Station with a custom PHP 7.4 profile (PHP-FPM), MariaDB 5.5.68 |
| Expected to work | any x86_64 Synology on DSM 6.2 with PHP7.4 7.4.30-0009 (e.g. DS412+), not tested yet |
| Result on the DS1815+ | install OK, PHP-FPM reloaded with no downtime, test page all green (`PHP 7.4.33 (fpm-fcgi)`), 61 CLI modules / 43 site extensions loaded exactly as with the original, connection to MariaDB 5.5.68 OK |
## Why

- PHP2Shell allows **unauthenticated remote code execution** via `multipart/form-data`
  requests against PHP-FPM / mod_php. It affects PHP ≥ 5.4.
- The PHP project fixed it in 8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 (21 Oct 2026). For EOL 7.4
  there is only a "minimal mitigation" patch, shipped by Ondřej Surý in
  `php7.4 1:7.4.33-31`.
- Synology does not ship patched PHP 7.x packages. On DSM 6 the latest PHP7.4 package is
  7.4.30-0009 (2022).

## What is in this repository

```
deploy/        ready-to-install files (the exact build running on the DS1815+)
  php74, php74-cgi, php74-fpm      PHP 7.4.33 + security backports
  modules/*.so (12)                rebuilt extensions that carry security fixes
  install.sh / uninstall.sh        install with backup, automatic rollback, FPM reload
  diag-fpm.sh                      compare original vs new with a site's exact ini files
  SHA256SUMS
test-site/index.php  one-file test page (PHP, extensions, DNS, upload, MariaDB)
build/         scripts to rebuild and verify everything from source
```

### The build

- **Source:** php.net PHP 7.4.33 plus 90 patches from Ondřej Surý's `php7.4 1:7.4.33-31`
  (see [Credits](#credits))
  (backports up to PHP 8.2.35, including **0164 "Avoid state corruption via bailout"** =
  PHP2Shell). The exact list is in `build/applied-patches.txt`.
- **Excluded on purpose:**
  - Debian packaging patches (0001–0047), NEWS/README/credits/Windows-only patches;
  - **0128 "secure DNS telemetry"**: it sends version-check DNS queries to an external
    server, which is not a security fix.
- **Toolchain:** Synology's own DSM 6.2 avoton toolkit (gcc 4.9.3, glibc 2.20). The build
  links against the **same libraries** as the original: OpenSSL 1.0.2u, libxml2 2.9.4,
  PCRE2 10.40 (JIT), oniguruma 6.9.5, ICU 56.1, libpq 9.3.25, SQLite 3.10.2, libpng 1.6.28,
  FreeType 2.5.5, OpenLDAP 2.4.56, FreeTDS 1.1.20, libxslt 1.1.28. Max required symbol
  version: `GLIBC_2.14`.
- **Rebuilt extensions** (they contain fixes): openssl, soap, phar, gd, pgsql, pdo_pgsql,
  pdo_sqlite, pdo_dblib, ldap, intl, ftp, xsl. The other 31 Synology extensions (mysqli,
  pdo_mysql, curl, zip, opcache, …) have no fixes in the patch set and stay original;
  they are ABI-compatible (API 20190902, NTS).
- **Synology behaviour reproduced.** It was reverse-engineered from the original `php74-fpm`
  with [REA](https://github.com/morluto/rea), Rizin and objdump:
  - bare `extension=` names are looked up first in
    `/var/packages/PHP7.4/target/usr/local/lib/php74/modules` (patch 9001);
  - `extension_dir` is hard-coded to `/usr/local/lib/php74/modules/` (patch 9002);
  - duplicate `extension=` lines are ignored silently (patch 9003);
  - `/usr/local/etc/php74/cli/conf.d` is scanned by default; same `include_path`, bindir and
    localstatedir.
- **API parity:** a full inventory with all extensions loaded is identical to the original
  (8502 functions, classes, methods, constants, ini settings, stream wrappers, hash
  algorithms, ciphers). The only addition is the security setting `max_multipart_body_parts`.

## Install

Requirements: DSM 6.2 x86_64, PHP7.4 package **7.4.30-0009** installed, SSH access.

1. DSM → Control Panel → Terminal & SNMP → **Enable SSH service** (temporarily).
2. Copy the whole `deploy/` folder to the NAS, including `modules/`, e.g.
   `/volume1/homes/<user>/php74-fix`.
3. Run as root:

   ```bash
   sudo -i
   cd /volume1/homes/<user>/php74-fix
   sh install.sh
   ```

4. Check your sites (or use the test page below), then disable SSH again.

`install.sh` stops **without changing anything** if any step fails. It:

1. checks the architecture, the package version and `SHA256SUMS`;
2. loads the new binaries with your real `php.ini` + `conf.d`, compares startup warnings and
   module count against the **original** binary (warnings caused by your own config are
   ignored), and loads every new extension;
3. backs up the originals to `/var/packages/PHP7.4/target/.orig-7.4.30-0009`; the first
   backup is never overwritten;
4. replaces files by copy + rename, so running workers keep the old inode and nothing mapped
   in memory is overwritten in place;
5. re-checks and **rolls back automatically** if extensions no longer load;
6. sends `USR2` to every php74-fpm master: graceful re-exec with the new binary, no downtime.

Running it again over a previous install is safe; the original backup is kept.

**Roll back:** `sh uninstall.sh` restores the original files byte for byte.

Reinstalling or updating the PHP7.4 package from Package Center brings back the vulnerable
files; run `install.sh` again afterwards.

## Test page

`test-site/index.php` is a single-file page that only answers from the local network
(returns 403 otherwise, also behind DSM's reverse proxy). Use it to check that the patched
PHP really runs on your NAS and that your sites' extensions and database still work.

1. Copy it to e.g. `/volume1/web/php74-test/index.php`.
2. Make sure the site uses PHP 7.4 in Web Station, then open `http://<NAS-IP>/php74-test/`.
3. It checks automatically:
   - the PHP version and SAPI, and the PHP2Shell setting;
   - the common extensions (ones your profile disables show as ⓘ, not as errors);
   - DNS functions, `fnmatch()`, OpenSSL, outbound HTTPS, mbstring, intl, sessions, GD;
   - which `php.ini` / `.ini` files the site really uses (plus a ready `diag-fpm.sh` command).
4. Fill in the MariaDB form to test connect / create / insert / select with accents and
   emoji (mysqli, plus PDO if `pdo_mysql` is enabled) and an optional file upload, which
   goes through the code path patched for PHP2Shell.
   - MariaDB 10 on DSM 6: socket `/run/mysqld/mysqld10.sock` or TCP `127.0.0.1:3307`.
   - MariaDB 5: socket `/run/mysqld/mysqld.sock` or TCP `127.0.0.1:3306`.
5. **Delete it after testing.** The password is never stored.

## Behaviour changes (intended, from the PHP2Shell mitigation)

- **Session upload progress is disabled completely**, whatever
  `session.upload_progress.enabled` says.
- When a script exceeds `memory_limit`, the worker logs `Fatal error` and exits
  immediately. The client gets 502/500, FPM spawns a new worker, and
  `register_shutdown_function` callbacks do not run in that case.

## Verification

Done in WSL with the DSM 6.2 sysroot libraries, plus on the DS1815+:

- **Core:** 669 upstream phpt tests, new vs original. The only differences are 9 tests that
  reflect the intended behaviour changes above; 2 security tests that failed on 7.4.30
  now pass.
- **Rebuilt extensions:** identical `NEEDED` libraries and `phpinfo()` features. Upstream
  tests show 0 regressions, and 13 security tests that failed with the originals now pass
  (6 soap, 5 phar, 1 gd, 1 pdo_sqlite).
- **Symbols:** every undefined symbol of all 43 extensions resolves against the new core.
- **MariaDB 10.3** (same series as DSM 6.2's MariaDB 10 package): mysqli + PDO over TCP and
  socket, prepared statements, utf8mb4, 5 MB BLOBs, 50k rows, multi-query, transactions.
  28/28 OK, identical to the original.
- **Real PHP-FPM:** GET, POST and multipart upload over FastCGI, plus `USR2` reload.
- **install.sh / uninstall.sh:** simulated end to end, including a negative test where an
  extra warning must abort the install.
- **CPU:** `addslashes`/`base64` have SSE4.2/AVX2 variants chosen at runtime (ifunc), so
  CPUs without them (e.g. Atom D2700 in the DS412+) use the plain path. This was not run
  on such a CPU; `install.sh` exercises the binaries on the NAS before replacing anything.

## Limitations

- `imap.so` is not rebuilt; its only change is a cosmetic `unsigned char` cast, not a CVE.
- The PHP2Shell patch for 7.4 is a minimal mitigation, and one mysqlnd backport is marked
  "partial" by its maintainer.
- DSM 6.2's own libraries (OpenSSL 1.0.2u, libxml2 2.9.4, …) and MariaDB 5.5 are old and
  have their own vulnerabilities, outside PHP.
- Synology's phpMyAdmin package puts `phpMyAdmin.ini` into
  `/usr/local/etc/php74/cli/conf.d`, which asks for `mcrypt.so` and `mysql.so` (they do not
  exist for PHP 7.4). The resulting startup warnings are harmless and identical with the
  original binary.
- PHP 7.4 is end-of-life. The long-term fix is PHP 8.2+ on DSM 7.

## Building from source

On Linux or WSL (Ubuntu 22.04 tested), no root needed; everything goes to `~/synobuild`:

```bash
bash build/setup-env.sh          # Synology toolkit + sysroot, original package, re2c, PCRE2/onig sources
bash build/prepare-source.sh     # PHP 7.4.33 + patches + Synology compatibility patches
bash build/build-php74-dsm62.sh  # php74, php74-cgi, php74-fpm  -> ~/synobuild/out
bash build/build-ext-deps.sh     # libxslt 1.1.28 / FreeTDS 1.1.20 headers missing from the sysroot
bash build/build-ext-dsm62.sh    # the 12 extensions           -> ~/synobuild/out/modules
bash build/verify-all.sh         # parity, symbols, extension + core tests, FPM, MariaDB
bash build/test-site-check.sh    # serves test-site/ with the new build + MariaDB and checks it
```

Lessons learned while building:

- Configure is run natively (target binaries run on the x86_64 host) so its run-tests
  work. Those run-tests link DSM libraries (readline 6, OpenSSL 1.0, …), so
  `LD_LIBRARY_PATH` must point at the sysroot during configure. Without it, checks fail
  silently and features disappear. A first build lost `dns_get_record()`, `checkdnsrr()`,
  `getmxrr()` and `fnmatch()` this way; `build/parity.sh` catches that.
- Synology's binary scans `/usr/local/etc/php74/cli/conf.d` by default
  (`--with-config-file-scan-dir`); without it the CLI loads no extensions.
- PHP-FPM overwrites its argv/environ with the process title, so the ini files a pool uses
  cannot be read from `/proc`. The test page reports them instead.

## Checksums (`deploy/SHA256SUMS`)

```
c64a700991ba54c54769b132d1eba803f881e9d7708d573539efbf91723c5b3d  php74
052e0e531c382a8d1e608168ce112637af85e16a7ffd37543497823bb73dcdd8  php74-cgi
d8cc2d08e684373a99ebd60b34607b180420a61acfc645f3a571cf5ac7c151e0  php74-fpm
```

The extension checksums are listed in `deploy/SHA256SUMS`.

## Credits

This project only packages and verifies other people's work for an old Synology platform.
The hard part was done by:

- **[Ondřej Surý](https://deb.sury.org/)**, who keeps PHP 7.4 alive long after its end of
  life. His `php7.4` packages for Debian/Ubuntu ([PPA](https://launchpad.net/~ondrej/+archive/ubuntu/php))
  carry the security backports used here (90 patches up to PHP 8.2.35), and he published the
  PHP2Shell backport for 7.4 on the day of the upstream release (21 October 2026). Without his series this
  build would not exist. If it helps you, consider
  [supporting his work](https://deb.sury.org/).
- **Arnaud Le Blanc and Ilija Tovilo** – authors of the PHP2Shell fix
  ("Avoid state corruption via bailout"), including the minimal mitigation for EOL branches.
- **The PHP security team and the individual patch authors**. Each patch in the series keeps
  its original author in its header.
- **Synology** – for publishing the DSM 6.2 toolchain and development environment used to
  build the binaries.
- **[REA](https://github.com/morluto/rea)**, [Rizin](https://rizin.re/) and GNU binutils –
  used to reverse-engineer Synology's changes to the original `php74-fpm`.

## Sources

- PHP Foundation – [Today's PHP security release](https://thephp.foundation/blog/2026/10/21/todays-php-security-release-and-how-were-strengthening-php-security/)
- Sansec – [PHP2Shell analysis and mitigations](https://sansec.io/research/php2shell)
- NCSC – [Critical security issue affecting PHP](https://www.ncsc.gov.uk/news/critical-security-issue-affecting-php)
- Ondřej Surý's PPA – [php7.4 builds](https://launchpad.net/~ondrej/+archive/ubuntu/php/+builds?build_text=7.4&build_state=built)
- Synology – [PHP7.4 package archive](https://archive.synology.com/download/Package/PHP7.4)
- Synology Community – [PHP vulnerabilities and patched DSM packages](https://community.synology.com/enu/forum/1/post/231423)

## License

The PHP binaries and the patches under `build/patches` and in the Debian series are
derived from PHP, which is distributed under the [PHP License 3.01](https://www.php.net/license/3_01.txt).
No license has been chosen yet for the scripts in this repository.
