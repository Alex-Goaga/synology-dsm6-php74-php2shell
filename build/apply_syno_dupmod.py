"""Silence the duplicate-module warning like Synology's PHP7.4 7.4.30-0009.

Synology's zend_register_module_ex() returns NULL for an already registered
module without emitting "Module '%s' already loaded" (the string is absent
from their php74-fpm; reconstructed from the disassembly).
"""
import sys

path = sys.argv[1].rstrip("/") + "/Zend/zend_API.c"
src = open(path, encoding="utf-8").read()
old = ('\t\tzend_error(E_CORE_WARNING, "Module \'%s\' already loaded", module->name);\n'
       '\t\tzend_string_release(lcname);\n'
       '\t\treturn NULL;\n')
new = ('\t\t/* Synology: duplicate extension= lines are ignored silently */\n'
       '\t\tzend_string_release(lcname);\n'
       '\t\treturn NULL;\n')
if "duplicate extension= lines are ignored silently" in src:
    print("already patched")
else:
    assert src.count(old) == 1
    open(path, "w", encoding="utf-8", newline="\n").write(src.replace(old, new, 1))
    print("patched Zend/zend_API.c")
