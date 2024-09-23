export SOCLABS_AHB_QSPI_DIR=$(pwd)
export SOCLABS_SOCTOOLS_FLOW_DIR=$SOCLABS_AHB_QSPI_DIR/soctools_flow

if [ ! -f ./verif/VIP/SST26VF064B.v ]; then
    make get_flash_model
fi