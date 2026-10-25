#!/bin/bash
# Every undefined symbol of each module must be provided by php74-fpm or by a
# library the module itself (transitively) depends on.
B=$(cd "$(dirname "$0")" && pwd)
. "$B/lib/target.sh"
DIRS="$W/syno/pkg/usr/lib $SYSROOT/usr/lib $SYSROOT/lib $W/extdeps/xslt/lib"
find_lib() { for d in $DIRS; do [ -e "$d/$1" ] && { echo "$d/$1"; return; }; done; }
deps() { # transitive NEEDED closure
  local todo="$1" seen=""
  while [ -n "$todo" ]; do
    set -- $todo; local f=$1; shift; todo="$*"
    for n in $(readelf -d "$f" 2>/dev/null | awk '/NEEDED/{gsub(/[\[\]]/,"",$5); print $5}'); do
      case " $seen " in *" $n "*) continue;; esac
      seen="$seen $n"; p=$(find_lib $n); [ -n "$p" ] && { echo "$p"; todo="$todo $p"; }
    done
  done
}
# the core binary and the libraries it links are always present in the process
( nm -D --defined-only "$W/out/php74-fpm" | awk '{print $3}'
  for l in $(deps "$W/out/php74-fpm"); do nm -D --defined-only "$l" | awk '{print $3}'; done ) | sed 's/@.*//' > /tmp/core.syms
bad=0
for so in "${@:-$W/out/modules/*.so}"; do
  for so1 in $so; do
    ( cat /tmp/core.syms; for l in $(deps "$so1"); do nm -D --defined-only "$l" | awk '{print $3}'; done ) | sed 's/@.*//' | sort -u > /tmp/prov.syms
    miss=$(nm -D --undefined-only "$so1" | awk '$1=="U"{print $2}' | sed 's/@.*//' | sort -u | comm -23 - /tmp/prov.syms)
    if [ -n "$miss" ]; then bad=1; echo "$(basename $so1): $(echo $miss | cut -c1-200)"; fi
  done
done
[ $bad = 0 ] && echo "OK: all symbols resolve"
