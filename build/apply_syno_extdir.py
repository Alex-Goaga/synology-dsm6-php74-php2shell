"""Hard-code extension_dir like Synology's PHP7.4 7.4.30-0009 build.

Synology's php_load_extension() (ext/standard/dl.c) and
php_load_zend_extension_cb() (main/php_ini.c) use the constant
"/usr/local/lib/php74/modules/" instead of the extension_dir INI value
(reconstructed from the php74-fpm disassembly). Run after apply_syno_compat.py.
"""
import sys

root = sys.argv[1].rstrip("/")
CONST = 'SYNO_EXTENSION_DIR'
define = ('#ifndef SYNO_EXTENSION_DIR\n'
          '# define SYNO_EXTENSION_DIR "/usr/local/lib/php74/modules/"\n'
          '#endif\n')


def patch(rel, pairs, anchor):
    path = f"{root}/{rel}"
    src = open(path, encoding="utf-8").read()
    if CONST in src:
        print("already patched", rel)
        return
    for old, new in pairs:
        assert src.count(old) == 1, (rel, old)
        src = src.replace(old, new, 1)
    assert src.count(anchor) == 1, (rel, anchor)
    src = src.replace(anchor, define + "\n" + anchor, 1)
    open(path, "w", encoding="utf-8", newline="\n").write(src)
    print("patched", rel)


patch("ext/standard/dl.c",
      [('\t\textension_dir = INI_STR("extension_dir");\n',
        '\t\textension_dir = (char *) SYNO_EXTENSION_DIR;\n'),
       ('\t\textension_dir = PG(extension_dir);\n',
        '\t\textension_dir = (char *) SYNO_EXTENSION_DIR;\n')],
      "/* {{{ php_load_shlib")
patch("main/php_ini.c",
      [('\t\tchar *extension_dir = INI_STR("extension_dir");\n',
        '\t\tchar *extension_dir = (char *) SYNO_EXTENSION_DIR;\n')],
      "#ifndef SYNO_PKG_MODULES_DIR")
