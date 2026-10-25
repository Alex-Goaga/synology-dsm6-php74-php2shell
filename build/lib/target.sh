#!/bin/bash
# Selects the build target (platform / DSM version / reference package) for
# every build/*.sh script. Default = avoton/DSM6.2, today's behavior,
# unchanged. Override with:
#   SYNO_TARGET=evansport-dsm71 bash build/<script>.sh
LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TARGET_FILE=${SYNO_TARGET_FILE:-$LIB_DIR/../targets/${SYNO_TARGET:-avoton-dsm62}.env}
[ -f "$TARGET_FILE" ] || { echo "unknown build target file: $TARGET_FILE" >&2; exit 1; }
. "$TARGET_FILE"
TC=$W/root/usr/local/$HOST
SYSROOT=$TC/$HOST/sys-root
PKG=$W/syno/pkg
echo "== target: $PLATFORM / DSM $DSM_VER / host=$HOST build=$BUILD (W=$W)" >&2
