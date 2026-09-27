#!/bin/bash
# Copy packaged builds (package/<output>/, created by package.sh) to a remote
# directory.
#
# Usage: ./copy.sh <target> [<output>...]
#
# With no <output>, every build in package/ is copied; otherwise only the named
# ones (e.g. qick_216_nn). The files of all builds land in the same remote
# directory; their names (qick_216_<build>.*) keep them apart. The remote
# directory is created if it does not exist.
#
# Authentication is by SSH key/agent. If SSHPASS is set in the environment,
# the password is used instead, via sshpass -e (it never appears on the command
# line).

TARGET=$1 #xilinx@192.168.1.59:~/jupyter_notebooks/qick_fermilab/fermilab
PACKAGE_ROOT=package

if [ -z "$TARGET" ]; then
    echo "Usage: $0 <target> [<output>...]" >&2
    exit 2
fi
shift

# Builds to copy: the ones given, or every package/<output>/ directory
if [ $# -gt 0 ]; then
    OUTPUTS=("$@")
else
    OUTPUTS=()
    for d in "$PACKAGE_ROOT"/*/; do
        [ -d "$d" ] && OUTPUTS+=("$(basename "$d")")
    done
fi
if [ ${#OUTPUTS[@]} -eq 0 ]; then
    echo "ERROR: no packaged builds in $PACKAGE_ROOT/, run a package-* target first" >&2
    exit 1
fi

# Files to copy
FILES=()
for o in "${OUTPUTS[@]}"; do
    if ! ls "$PACKAGE_ROOT/$o"/* > /dev/null 2>&1; then
        echo "ERROR: $PACKAGE_ROOT/$o/ is missing or empty, run its package-* target first" >&2
        exit 1
    fi
    FILES+=("$PACKAGE_ROOT/$o"/*)
done

SSH=(ssh)
SCP=(scp)
if [ -n "$SSHPASS" ]; then
    if ! command -v sshpass > /dev/null; then
        echo "ERROR: SSHPASS is set but sshpass is not installed" >&2
        exit 1
    fi
    SSH=(sshpass -e ssh)
    SCP=(sshpass -e scp)
fi

echo "=============================================================="
echo "Remote dir: $TARGET"

# Create the remote directory (skipped for a local target without host:)
MKDIR_OK=1
if [[ "$TARGET" == *:* ]]; then
    "${SSH[@]}" "${TARGET%%:*}" mkdir -p -- "${TARGET#*:}" || MKDIR_OK=0
fi

if [ $MKDIR_OK -eq 1 ] && "${SCP[@]}" "${FILES[@]}" "$TARGET"; then
    for f in "${FILES[@]}"; do
        echo "File remotely copied: $(basename "$f")"
    done
    echo "Remote copy: PASS"
    STATUS=0
else
    echo "Remote copy: FAIL"
    STATUS=1
fi
echo "=============================================================="
exit $STATUS
