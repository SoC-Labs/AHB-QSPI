#-----------------------------------------------------------------------------
# lc_shell helper — compile the FF (fast-min) Liberty files for the
# precompiled flash_cache_data / flash_cache_tag macros into .db format.
#
# /research/precompiled_mems/TSMC65 ships the SS .db plus FF .lib files,
# but no FF .db. fc_shell's link_library wants .db, so without these the
# scen_fast scenario in the FC flow has to be skipped (no hold-corner
# coverage). This script regenerates the four missing .db files into
# the project's local syn/asic/libs/mem_ff/ tree so we don't write
# anywhere outside the repo.
#
# Run with: lc_shell -f scripts/build_mem_ff_db.tcl
# Output  : syn/asic/libs/mem_ff/flash_cache_{data,tag}_ff_1p32v_1p32v_{m40c,125c}.db
#-----------------------------------------------------------------------------

set src_root  "/research/precompiled_mems/TSMC65"
set dst_root  $::env(MEM_FF_DB_DIR)

file mkdir $dst_root

set jobs [list \
    [list flash_cache_data flash_cache_data_ff_1p32v_1p32v_m40c FLASH_CACHE_DATA_ff_1p32v_1p32v_m40c] \
    [list flash_cache_data flash_cache_data_ff_1p32v_1p32v_125c FLASH_CACHE_DATA_ff_1p32v_1p32v_125c] \
    [list flash_cache_tag  flash_cache_tag_ff_1p32v_1p32v_m40c  FLASH_CACHE_TAG_ff_1p32v_1p32v_m40c]  \
    [list flash_cache_tag  flash_cache_tag_ff_1p32v_1p32v_125c  FLASH_CACHE_TAG_ff_1p32v_1p32v_125c]]

foreach job $jobs {
    lassign $job dir base libname
    set lib_in  "${src_root}/${dir}/${base}.lib"
    set db_out  "${dst_root}/${base}.db"
    puts "INFO: read_lib  $lib_in"
    read_lib $lib_in
    puts "INFO: write_lib $libname -> $db_out"
    write_lib $libname -output $db_out
    remove_lib $libname
}

puts "INFO: all FF .db files written under $dst_root"
exit
