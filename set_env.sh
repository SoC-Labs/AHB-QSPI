export SOCLABS_AHB_QSPI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SOCLABS_SOCTOOLS_FLOW_DIR=$SOCLABS_AHB_QSPI_DIR/soctools_flow

if [ ! -f $SOCLABS_AHB_QSPI_DIR/verif/VIP/SST26VF064B.v ]; then
    pushd $SOCLABS_AHB_QSPI_DIR
    make get_flash_model
    popd
fi