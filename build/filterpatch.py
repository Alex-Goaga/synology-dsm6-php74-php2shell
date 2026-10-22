"""Drop the NEWS and tests/ sections from a git-format patch (stdout)."""
import re
import sys

txt = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
parts = re.split(r"(?m)^(?=diff --git )", txt)
out = []
for p in parts:
    m = re.match(r"diff --git a/(\S+)", p)
    if m and (m.group(1) == "NEWS" or "/tests/" in m.group(1)):
        continue
    out.append(p)
sys.stdout.write("".join(out))
