TARGET=$1 #xilinx@192.168.1.59:~/jupyter_notebooks/qick_fermilab/fermilab
OUTPUT=$2 #qick_111_rfbv2
PASSWORD=$3 # xilinx
PACKAGE_DIR=package

echo "=============================================================="
echo "Remote dir: $TARGET"
sshpass -p "$PASSWORD" scp $PACKAGE_DIR/* $TARGET
if [ $? -eq 0 ]; then
    FILES=`ls $PACKAGE_DIR`
    for f in $FILES; do
        echo "File remotely copied: $f"
    done
    echo "Remote copy: PASS"
else
    echo "Remote copy: FAIL"
fi
echo "=============================================================="

