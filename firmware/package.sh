#!/bin/bash
# Collect the BIT, HWH, and LTX files of a Vivado project into package/<output>/,
# and archive them as package/<output>.tar.gz and package/<output>.zip.
#
# Usage: ./package.sh <project> <design> <project_dir> <output>
#
# Only package/<output>/ and its archives are recreated, so each build keeps its
# own package next to the others (e.g. package/qick_216_nn/, package/qick_216_nn_ila/).
set -e

PROJECT=$1 #top_111_rfbv2
DESIGN=$2 #d_1
PROJECT_DIR=$3 #top_111_rfbv2
OUTPUT=$4 #qick_111_rfbv2

if [ $# -ne 4 ]; then
    echo "Usage: $0 <project> <design> <project_dir> <output>" >&2
    exit 2
fi

PACKAGE_ROOT=package
PACKAGE_DIR=$PACKAGE_ROOT/$OUTPUT
PROJECT_BIT=${DESIGN}_wrapper.bit
PROJECT_HWH=${DESIGN}.hwh
PROJECT_LTX=${DESIGN}_wrapper.ltx

echo "=============================================================="
rm -rf "$PACKAGE_DIR" "$PACKAGE_DIR.tar.gz" "$PACKAGE_DIR.zip"
mkdir -p "$PACKAGE_DIR"
echo "cp $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_BIT $PACKAGE_DIR/$OUTPUT.bit"
cp "$PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_BIT" "$PACKAGE_DIR/$OUTPUT.bit"
# The LTX file only exists if the design has debug cores (e.g. ILAs)
if [ -f "$PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_LTX" ]; then
    echo "cp $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_LTX $PACKAGE_DIR/$OUTPUT.ltx"
    cp "$PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_LTX" "$PACKAGE_DIR/$OUTPUT.ltx"
else
    echo "WARNING: $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_LTX not found, skipping LTX"
fi
echo "cp $PROJECT_DIR/$PROJECT.gen/sources_1/bd/$DESIGN/hw_handoff/$PROJECT_HWH $PACKAGE_DIR/$OUTPUT.hwh"
cp "$PROJECT_DIR/$PROJECT.gen/sources_1/bd/$DESIGN/hw_handoff/$PROJECT_HWH" "$PACKAGE_DIR/$OUTPUT.hwh"
tar cvfz "$PACKAGE_DIR.tar.gz" -C "$PACKAGE_ROOT" "$OUTPUT"
(cd "$PACKAGE_ROOT" && zip -r "$OUTPUT.zip" "$OUTPUT")
echo "Package: $PACKAGE_DIR.tar.gz"
echo "Package: $PACKAGE_DIR.zip"
echo "=============================================================="
