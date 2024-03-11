PROJECT=$1 #top_111_rfbv2
DESIGN=$2 #d_1
PROJECT_DIR=$3 #top_111_rfbv2
OUTPUT=$4 #qick_111_rfbv2

PACKAGE_DIR=package
PROJECT_BIT=$DESIGN\_wrapper.bit
PROJECT_HWH=$DESIGN\.hwh
PROJECT_LTX=$DESIGN\_wrapper.ltx

echo "=============================================================="
rm -rf $PACKAGE_DIR $PACKAGE_DIR\.tar.gz
mkdir -p $PACKAGE_DIR
echo "cp $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_BIT $PACKAGE_DIR/$OUTPUT.bit"
cp $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_BIT $PACKAGE_DIR/$OUTPUT.bit
echo "cp $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_LTX $PACKAGE_DIR/$OUTPUT.ltx"
cp $PROJECT_DIR/$PROJECT.runs/impl_1/$PROJECT_LTX $PACKAGE_DIR/$OUTPUT.ltx
echo "cp $PROJECT_DIR/$PROJECT.gen/sources_1/bd/$DESIGN/hw_handoff/$PROJECT_HWH $PACKAGE_DIR/$OUTPUT.hwh"
cp $PROJECT_DIR/$PROJECT.gen/sources_1/bd/$DESIGN/hw_handoff/$PROJECT_HWH $PACKAGE_DIR/$OUTPUT.hwh
tar cvfz $PACKAGE_DIR\.tar.gz $PACKAGE_DIR
zip $PACKAGE_DIR\.zip $PACKAGE_DIR/*
echo "Package: $PACKAGE_DIR.tar.gz"
echo "Package: $PACKAGE_DIR.zip"
echo "=============================================================="
