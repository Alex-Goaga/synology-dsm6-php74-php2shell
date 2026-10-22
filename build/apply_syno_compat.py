"""Apply Synology PHP7.4 package compatibility changes to main/php_ini.c.

Behaviour reconstructed from Synology's php74-fpm (7.4.30-0009): bare
extension names are looked up first in the package's own modules dir.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

helper = r'''#ifndef SYNO_PKG_MODULES_DIR
# define SYNO_PKG_MODULES_DIR "/var/packages/PHP7.4/target/usr/local/lib/php74/modules"
#endif

#ifdef HAVE_LIBDL
/* emalloc'ed path inside the package modules dir if the bare name exists there */
static char *syno_pkg_module_path(const char *filename)
{
	char *path = NULL;

	if (strchr(filename, '/')) {
		return NULL;
	}
	spprintf(&path, 0, "%s/%s", SYNO_PKG_MODULES_DIR, filename);
	if (access(path, F_OK) != 0) {
		efree(path);
		return NULL;
	}
	return path;
}

static int syno_load_pkg_zend_extension(const char *filename)
{
	char *pkg_path = syno_pkg_module_path(filename);
	char *err = NULL;
	DL_HANDLE handle;

	if (!pkg_path) {
		return 0;
	}
	handle = (DL_HANDLE)php_load_shlib(pkg_path, &err);
	if (!handle) {
		if (err) {
			efree(err);
		}
		efree(pkg_path);
		return 0;
	}
	zend_load_extension_handle(handle, pkg_path);
	efree(pkg_path);
	return 1;
}
#endif

/* {{{ php_load_php_extension_cb
'''
anchor = "/* {{{ php_load_php_extension_cb\n"
assert src.count(anchor) == 1
src = src.replace(anchor, helper, 1)

old_php = "\tphp_load_extension(*((char **) arg), MODULE_PERSISTENT, 0);\n"
new_php = ("\tchar *pkg_path = syno_pkg_module_path(*((char **) arg));\n\n"
           "\tif (pkg_path) {\n"
           "\t\tphp_load_extension(pkg_path, MODULE_PERSISTENT, 0);\n"
           "\t\tefree(pkg_path);\n"
           "\t} else {\n"
           "\t\tphp_load_extension(*((char **) arg), MODULE_PERSISTENT, 0);\n"
           "\t}\n")
assert src.count(old_php) == 1
src = src.replace(old_php, new_php, 1)

old_zend = "\t\tzend_load_extension(filename);\n\t} else {\n\t\tDL_HANDLE handle;\n"
new_zend = ("\t\tzend_load_extension(filename);\n"
            "\t} else if (syno_load_pkg_zend_extension(filename)) {\n"
            "\t\t/* loaded from the Synology package modules dir */\n"
            "\t} else {\n\t\tDL_HANDLE handle;\n")
assert src.count(old_zend) == 1
src = src.replace(old_zend, new_zend, 1)

open(path, "w", encoding="utf-8", newline="\n").write(src)
print("patched", path)
