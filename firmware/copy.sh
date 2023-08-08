TARGET=$1 #xilinx@192.168.1.59:~/jupyter_notebooks/qick_fermilab/fermilab
OUTPUT=$2 #qick_111_rfbv2

PACKAGE_DIR=package

echo "=============================================================="
echo "Remote dir: $TARGET"
sshpass -p "xilinx" scp $PACKAGE_DIR/* $TARGET
FILES=`ls $PACKAGE_DIR`
for f in $FILES; do
    echo "File remotely copied: $f"
done
echo "=============================================================="

