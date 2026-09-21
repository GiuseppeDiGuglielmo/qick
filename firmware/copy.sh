#!/bin/bash
# Copy the files in package/ (created by package.sh) to a remote directory.
#
# Usage: ./copy.sh <target>
#
# The remote directory is created if it does not exist.
#
# Authentication is by SSH key/agent. If SSHPASS is set in the environment,
# the password is used instead, via sshpass -e (it never appears on the command
# line).

TARGET=$1 #xilinx@192.168.1.59:~/jupyter_notebooks/qick_fermilab/fermilab
PACKAGE_DIR=package

if [ -z "$TARGET" ]; then
    echo "Usage: $0 <target>" >&2
    exit 2
fi

if ! ls "$PACKAGE_DIR"/* > /dev/null 2>&1; then
    echo "ERROR: $PACKAGE_DIR/ is missing or empty, run a package-* target first" >&2
    exit 1
fi

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

if [ $MKDIR_OK -eq 1 ] && "${SCP[@]}" "$PACKAGE_DIR"/* "$TARGET"; then
    for f in "$PACKAGE_DIR"/*; do
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
