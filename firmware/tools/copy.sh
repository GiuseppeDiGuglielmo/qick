#!/bin/bash
# Copy a design's build results to a remote directory.
#
# Usage: ./copy.sh <target> <source_dir>
#
# <source_dir> is normally a design's out/ directory, which holds symlinks into
# the build tree. scp follows them, so the real artifacts are transferred.
#
# The remote directory is created if it does not exist.
#
# Authentication is by SSH key/agent. If SSHPASS is set in the environment,
# the password is used instead, via sshpass -e (it never appears on the command
# line).
#
# If DRYRUN is set in the environment, no ssh/scp commands are run; the
# commands that would have run are printed instead.

TARGET=$1 #xilinx@192.168.1.59:~/jupyter_notebooks/qick_fermilab/fermilab
SOURCE_DIR=$2 #../projects/qick_tprocv2_216_standard_1ch/out

if [ -z "$TARGET" ] || [ -z "$SOURCE_DIR" ]; then
    echo "Usage: $0 <target> <source_dir>" >&2
    exit 2
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: $SOURCE_DIR does not exist" >&2
    exit 1
fi

# -e resolves symlinks, so a link left dangling by an unbuilt design is caught
# here rather than as an obscure scp failure
FILES=()
MISSING=()
for f in "$SOURCE_DIR"/*; do
    if [ -e "$f" ]; then
        FILES+=("$f")
    elif [ -L "$f" ]; then
        MISSING+=("$(basename "$f")")
    fi
done

if [ ${#FILES[@]} -eq 0 ]; then
    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "ERROR: $SOURCE_DIR has nothing to copy: ${MISSING[*]} point into a build tree that does not exist yet" >&2
        echo "Run 'make bitstream' first." >&2
    else
        echo "ERROR: $SOURCE_DIR is empty" >&2
    fi
    exit 1
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "WARNING: skipping unbuilt artifacts: ${MISSING[*]}" >&2
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
if [ -n "$DRYRUN" ]; then
    echo "Dry run: no files will be copied"
fi

# Create the remote directory (skipped for a local target without host:)
MKDIR_OK=1
if [[ "$TARGET" == *:* ]]; then
    if [ -n "$DRYRUN" ]; then
        echo "Would run: ${SSH[*]} ${TARGET%%:*} mkdir -p -- ${TARGET#*:}"
    else
        "${SSH[@]}" "${TARGET%%:*}" mkdir -p -- "${TARGET#*:}" || MKDIR_OK=0
    fi
fi

if [ -n "$DRYRUN" ]; then
    echo "Would run: ${SCP[*]} ${FILES[*]} $TARGET"
    for f in "${FILES[@]}"; do
        echo "File would be copied: $(basename "$f")"
    done
    echo "Remote copy: DRY RUN"
    echo "=============================================================="
    exit 0
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
