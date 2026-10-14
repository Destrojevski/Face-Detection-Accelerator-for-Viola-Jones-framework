#vj_project.tcl
# pokrenuti iz scripts/ direktorijuma:
#
#     vivado -mode batch -source vj_project.tcl (ili sa dodatkom -tclargs full)
#
# 'full' dodatno pravi i podesava projekat za simulaciju (project/vj_sim), ali
# simulaciju NE pokrece - ona se pokrece rucno iz Vivado GUI-ja.
# 'sim' pravi samo taj projekat i staje.
# Ostali argumenti ostavljeni radi debagovanja i nisu od interesa

cd ..
set root_dir [pwd]
cd scripts

set part_name    "xc7z010clg400-1"
set board_part   "digilentinc.com:zybo-z7-10:part0:1.0"
set ip_name      "vj_cascade"
set ip_version   "1.0"
set ip_vendor    "ftn.uns.ac.rs"

set ip_proj_dir  "$root_dir/project/${ip_name}_ip"
set ip_repo_dir  "$root_dir/project/ip_repo"
set bd_proj_dir  "$root_dir/project/${ip_name}_system"
set release_dir  "$root_dir/release"

file mkdir $ip_proj_dir
file mkdir $ip_repo_dir
file mkdir $bd_proj_dir
file mkdir $release_dir

# odabir faze pokretanja
set stage "all"
if {$argc > 0} { set stage [lindex $argv 0] }
if {[lsearch -exact {check ip bd impl all sim full procs} $stage] < 0} {
    puts "ERROR: unknown stage '$stage'."
    puts "       Use: sim | check | ip | bd | impl | all | full | procs"
    return
}
set vj_t_start [clock seconds]
puts "INFO: stage = $stage"

set rtl_files [list \
    $root_dir/rtl/vj_pkg.vhd \
    $root_dir/rtl/vj_stage_pkg.vhd \
    $root_dir/rtl/vj_bank_array.vhd \
    $root_dir/rtl/vj_classifier_rom.vhd \
    $root_dir/rtl/vj_datapath.vhd \
    $root_dir/rtl/vj_controlpath.vhd \
    $root_dir/rtl/vj_cascade_core.vhd \
    $root_dir/rtl/vj_cascade_v1_0_S00_AXI.vhd \
    $root_dir/rtl/vj_cascade_v1_0.vhd ]


# Podesavanja UARTa
proc vj_apply_zybo_z7_uart_config {ps} {
    set_property -dict [list \
        CONFIG.PCW_PRESET_BANK1_VOLTAGE     {LVCMOS 1.8V} \
        CONFIG.PCW_UART1_PERIPHERAL_ENABLE  {1} \
        CONFIG.PCW_UART1_UART1_IO           {MIO 48 .. 49} \
        CONFIG.PCW_UART1_BAUD_RATE          {115200} \
        CONFIG.PCW_UART1_GRP_FULL_ENABLE    {0} \
        CONFIG.PCW_UART_PERIPHERAL_CLKSRC   {IO PLL} \
        CONFIG.PCW_UART_PERIPHERAL_FREQMHZ  {100} \
    ] $ps

}

# Podesavanja DDR (Radi postovanja forme)
proc vj_apply_zybo_z7_ddr_config {ps} {
    set_property -dict [list \
        CONFIG.PCW_UIPARAM_DDR_ENABLE               {1} \
        CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE          {DDR 3 (Low Voltage)} \
        CONFIG.PCW_UIPARAM_DDR_PARTNO               {MT41K256M16 RE-125} \
        CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY      {4096 MBits} \
        CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH           {16 Bits} \
        CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH            {32 Bit} \
        CONFIG.PCW_UIPARAM_DDR_SPEED_BIN            {DDR3_1066F} \
        CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ             {533.333333} \
        CONFIG.PCW_UIPARAM_DDR_ECC                  {Disabled} \
        CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP            {Normal (0-85)} \
        CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE           {0} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN        {0} \
        CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF    {0} \
        \
        CONFIG.PCW_UIPARAM_DDR_ROW_ADDR_COUNT       {15} \
        CONFIG.PCW_UIPARAM_DDR_COL_ADDR_COUNT       {10} \
        CONFIG.PCW_UIPARAM_DDR_BANK_ADDR_COUNT      {3} \
        CONFIG.PCW_UIPARAM_DDR_BL                   {8} \
        CONFIG.PCW_UIPARAM_DDR_AL                   {0} \
        CONFIG.PCW_UIPARAM_DDR_CL                   {7} \
        CONFIG.PCW_UIPARAM_DDR_CWL                  {6} \
        CONFIG.PCW_UIPARAM_DDR_T_RCD                {7} \
        CONFIG.PCW_UIPARAM_DDR_T_RP                 {7} \
        CONFIG.PCW_UIPARAM_DDR_T_RC                 {48.75} \
        CONFIG.PCW_UIPARAM_DDR_T_RAS_MIN            {35.0} \
        CONFIG.PCW_UIPARAM_DDR_T_FAW                {40.0} \
        \
        CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL    {1} \
        CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE      {1} \
        CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE       {1} \
        \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0         {0.221} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1         {0.222} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2         {0.217} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3         {0.244} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0   {-0.050} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1   {-0.044} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2   {-0.035} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3   {-0.100} \
        \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM        {18.8} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM        {18.8} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM        {18.8} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM        {18.8} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH   {80.4535} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH   {80.4535} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH   {80.4535} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH   {80.4535} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY {160} \
        \
        CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM      {22.8} \
        CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM      {27.9} \
        CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM      {22.9} \
        CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM      {29.4} \
        CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH {105.056} \
        CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH {66.904} \
        CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH {89.1715} \
        CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH {113.63} \
        CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY {160} \
        \
        CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM       {22.8} \
        CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM       {27.9} \
        CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM       {22.9} \
        CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM       {29.4} \
        CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH  {98.503} \
        CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH  {68.5855} \
        CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH  {90.295} \
        CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH  {103.977} \
        CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY {160} \
        CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY {160} \
    ] $ps

}

# Dodatna podesavanja
proc vj_apply_project_ps7_config {ps} {
    set_property -dict [list \
        CONFIG.PCW_USE_FABRIC_INTERRUPT     {1} \
        CONFIG.PCW_IRQ_F2P_INTR             {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_USE_M_AXI_GP0            {1} \
    ] $ps

}

# Pokretanje svih podesavanja + verifikacija
proc vj_apply_zybo_z7_ps7_config {ps {do_ddr 1}} {
    vj_apply_zybo_z7_uart_config $ps
    if {$do_ddr} { vj_apply_zybo_z7_ddr_config $ps }
    vj_apply_project_ps7_config $ps
    vj_verify_ps7_config $ps $do_ddr
}

proc vj_verify_ps7_config {ps {check_ddr 1}} {
    set expect [list \
        PCW_UART1_UART1_IO        {MIO 48 .. 49} \
        PCW_PRESET_BANK1_VOLTAGE  {LVCMOS 1.8V} \
        PCW_UART1_BAUD_RATE       {115200} \
        PCW_FPGA0_PERIPHERAL_FREQMHZ {100} ]

    if {$check_ddr} {
        lappend expect \
            PCW_UIPARAM_DDR_PARTNO          {MT41K256M16 RE-125} \
            PCW_UIPARAM_DDR_DEVICE_CAPACITY {4096 MBits} \
            PCW_UIPARAM_DDR_BUS_WIDTH       {32 Bit} \
            PCW_DDR_RAM_HIGHADDR            {0x3FFFFFFF}
    }

    set bad 0
    foreach {prop want} $expect {
        set got [get_property CONFIG.$prop $ps]
        if {[string is double -strict $got] && [string is double -strict $want]} {
            set match [expr {abs($got - $want) < 1e-6}]
        } else {
            set match [string equal $got $want]
        }

        if {$match} {
            puts "VJ-CHECK ok:   $prop = $got"
        } else {
            puts "VJ-CHECK FAIL: $prop = '$got' (expected '$want')"
            incr bad
        }
    }
    if {$bad} {
        error "vj_verify_ps7_config: $bad PS7 property/properties are wrong"
    }
    puts "VJ-CHECK: PS7 configuration matches the Zybo Z7 board preset."
}

if {$stage eq "procs"} {
    puts "INFO: board configuration procedures defined; no stage run."
    puts "INFO: available: [lsort [info procs vj_*]]"
    return
}

# faza sim: pravi i podesava zaseban projekat za simulaciju.
# simulacija se NE pokrece odavde - pokrece se rucno iz Vivado GUI-ja
if {$stage eq "sim" || $stage eq "full"} {

set sim_proj_dir "$root_dir/project/vj_sim"
file mkdir $sim_proj_dir

set sim_tb "$root_dir/tb/tb_vj_cascade_v1_0.vhd"
if {![file exists $sim_tb]} {
    error "vj_project.tcl: nema $sim_tb"
}
foreach f [list "$root_dir/sim/tb_vectors.txt" "$root_dir/data/classifier_rom.mem"] {
    if {![file exists $f]} {
        error "vj_project.tcl: nedostaje datoteka sa podacima za simulaciju: $f"
    }
}

create_project -force vj_sim $sim_proj_dir -part $part_name
set_property target_language VHDL [current_project]

add_files -norecurse $rtl_files

# dva test okruzenja, svako u svom simulacionom fajlsetu:
#   sim_1 - tb_vj_cascade_v1_0  (IP jezgro u integrisanom sistemu sa AXI magistralom)
#   sim_2 - tb_vj_cascade_core  (samo IP jezgro, bez magistrale)
#
# odvojeni fajlsetovi su potrebni jer se razlikuju top modul, generici i
# potrebno vrijeme simulacije,  u GUI-ju se bira desnim klikom na fajlset pa
# Make Active, ili u Sources prozoru padajucim menijem iznad liste.
add_files -fileset sim_1 -norecurse $sim_tb

set core_tb "$root_dir/tb/tb_vj_cascade_core.vhd"
if {[file exists $core_tb]} {
    if {[llength [get_filesets -quiet sim_2]] == 0} {
        create_fileset -simset sim_2
    }
    add_files -fileset sim_2 -norecurse $core_tb
} else {
    puts "WARNING: nema $core_tb - pravi se samo sim_1"
}


set_property file_type {VHDL 2008} [get_files -quiet *.vhd]

# sim_1: AXI test okruzenje
set_property top tb_vj_cascade_v1_0 [get_filesets sim_1]
set_property top_lib xil_defaultlib  [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {2ms} \
    -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {false} \
    -objects [get_filesets sim_1]
set_property -name {generic} -value \
    "VECTOR_FILE=$root_dir/sim/tb_vectors.txt ROM_FILE=$root_dir/data/classifier_rom.mem CASES=5" \
    -objects [get_filesets sim_1]

# sim_2: test okruzenje jezgra
# simulacija traje krace nego u citavom AXI okruzenju
if {[llength [get_filesets -quiet sim_2]] > 0} {
    set_property top tb_vj_cascade_core [get_filesets sim_2]
    set_property top_lib xil_defaultlib  [get_filesets sim_2]
    set_property -name {xsim.simulate.runtime} -value {1ms} \
        -objects [get_filesets sim_2]
    set_property -name {xsim.simulate.log_all_signals} -value {false} \
        -objects [get_filesets sim_2]
    set_property -name {generic} -value \
        "VECTOR_FILE=$root_dir/sim/tb_vectors.txt ROM_FILE=$root_dir/data/classifier_rom.mem" \
        -objects [get_filesets sim_2]
}

# aktivan je AXI fajlset - on pokriva i jezgro i magistralu
current_fileset -simset [get_filesets sim_1]

# provera da su oba test okruzenja stvarno u fajlsetu, da se ne desi da
# projekat izgleda ispravno a top modul ne postoji
foreach fs [get_filesets -quiet sim_*] {
    if {[llength [get_files -quiet -of_objects $fs]] == 0} {
        error "vj_project.tcl: fajlset $fs je prazan - test okruzenje nije dodato"
    }
}

puts ""
puts "================ projekat za simulaciju ================"
puts "  lokacija     : $sim_proj_dir/vj_sim.xpr"
puts "  sim_1 (aktivan) : tb_vj_cascade_v1_0   runtime 2ms   ocekivano 127 provjera"
puts "  sim_2           : tb_vj_cascade_core    runtime 1ms   ocekivano  96 provjera"
puts "  VECTOR_FILE  : $root_dir/sim/tb_vectors.txt"
puts "  ROM_FILE     : $root_dir/data/classifier_rom.mem"
puts "  CASES        : 5  (sim_1)"
puts "  ocekivano u Tcl konzoli:  errors : 0  u oba slucaja"
puts "========================================================"
puts ""

close_project

if {$stage ne "full"} {
    puts "INFO: faza 'sim' zavrsena."
    if {[info exists ::env(VJ_BATCH)]} { exit 0 }
    return
}

# 'full': projekat za simulaciju je napravljen, nastavlja se sa buildovanjem
set stage "all"
puts "INFO: nastavak."
}

if {$stage eq "check"} {
    create_project -in_memory -part $part_name
    set_property target_language VHDL [current_project]

    read_vhdl -vhdl2008 $rtl_files
    read_xdc $root_dir/scripts/vj_ooc.xdc

    #Rom cita odavdje u fazi elaboracije
    synth_design -top vj_cascade_core -part $part_name -mode out_of_context \
        -generic ROM_INIT_FILE=$root_dir/data/classifier_rom.mem

    puts "\n======================= CHECK RESULTS ======================="
    report_utilization -file $release_dir/ooc_utilization.rpt
    report_timing_summary -delay_type max -max_paths 10 \
        -file $release_dir/ooc_timing.rpt


    proc vj_util_used {rpt_text label} {

        foreach pat [list $label "CLB $label" "Slice $label"] {
            if {[regexp "\\| *$pat\[^|0-9\]*\\| *(\[0-9\]+)" $rpt_text -> n]} {
                return $n
            }
        }
        return "?"
    }

    set fh [open $release_dir/ooc_utilization.rpt r]
    set util_text [read $fh]
    close $fh

    set luts  [vj_util_used $util_text "LUTs"]
    set ffs   [vj_util_used $util_text "Registers"]
    set brams [vj_util_used $util_text "Block RAM Tile"]
    set dsps  [vj_util_used $util_text "DSPs"]

    puts [format "  LUT   %6s of 17600" $luts]
    puts [format "  FF    %6s of 35200" $ffs]
    puts [format "  BRAM  %6s of 60" $brams]
    puts [format "  DSP   %6s of 80" $dsps]
    puts "  (full breakdown, including the RAMB18E1/RAMB36E1 split, is in ooc_utilization.rpt)"

    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    puts [format "\n  WNS = %.3f ns" $wns]
    if {$wns >= 0} {
        puts [format "  Timing MET at 100 MHz. Post-synthesis Fmax approx %.1f MHz" \
              [expr {1000.0 / (10.0 - $wns)}]]
    } else {
        puts [format "  Timing MISSED by %.3f ns. Post-synthesis Fmax approx %.1f MHz" \
              [expr {-$wns}] [expr {1000.0 / (10.0 - $wns)}]]
        puts "  Look at ooc_timing.rpt: if the failing path is in u_dp/u_sqrt,"
        puts "  change vj_isqrt to one iteration per clock (call step() once"
        puts "  instead of twice, and count to 15 instead of 7)."
    }
    puts "  Full reports in $release_dir/"
    puts "============================================================\n"
    puts "Note: out-of-context synthesis estimates only. The real numbers come"
    puts "from stage 'impl' after place-and-route."
    return
}


#Kreiranje projekta i pakovanje jezgra
if {$stage eq "ip" || $stage eq "all"} {
create_project ${ip_name}_ip $ip_proj_dir -part $part_name -force
set_property target_language VHDL [current_project]

add_files -norecurse $rtl_files

# ROM dio se inicijalizuje sa IPjem
add_files -fileset sources_1 -norecurse $root_dir/data/classifier_rom.mem
set_property file_type {Memory Initialization Files} \
    [get_files $root_dir/data/classifier_rom.mem]

add_files -fileset sim_1 -norecurse [list \
    $root_dir/tb/tb_vj_cascade_core.vhd \
    $root_dir/sim/tb_vectors.txt ]

set_property top vj_cascade_v1_0 [current_fileset]
set_property top tb_vj_cascade_core [get_filesets sim_1]
update_compile_order -fileset sources_1


set_property file_type {VHDL 2008} [get_files *.vhd]

puts "INFO: packaging IP ..."
ipx::package_project -root_dir $ip_repo_dir -vendor $ip_vendor \
    -library user -taxonomy /UserIP -import_files -set_current false
ipx::unload_core $ip_repo_dir/component.xml
ipx::edit_ip_in_project -upgrade true -name edit_${ip_name}_v1_0 \
    -directory $ip_repo_dir $ip_repo_dir/component.xml
update_compile_order -fileset sources_1

set_property vendor        $ip_vendor                        [ipx::current_core]
set_property name          $ip_name                          [ipx::current_core]
set_property version       $ip_version                       [ipx::current_core]
set_property display_name  "Viola-Jones Cascade Accelerator"  [ipx::current_core]
set_property description \
    "24x24 Viola-Jones kaskadni akcelerator: 25 faza, 2913 slabih klasifikatora, upakovani 112-bitni klasifikacioni ROM, row-banked integralna slika, interni x sweep" \
    [ipx::current_core]
set_property supported_families {zynq Production} [ipx::current_core]

ipx::infer_bus_interface {bram_clk_a bram_en_a bram_we_a bram_addr_a bram_wrdata_a bram_rddata_a} \
    xilinx.com:interface:bram_rtl:1.0 [ipx::current_core]

set bram_if {}
foreach bi [ipx::get_bus_interfaces -of_objects [ipx::current_core]] {
    if {[get_property BUS_TYPE_VLNV $bi] eq "xilinx.com:interface:bram:1.0"} {
        set bram_if $bi
        break
    }
}
if {$bram_if eq ""} {
    foreach guess {bram bram_a BRAM bram_porta} {
        set cand [ipx::get_bus_interfaces -of_objects [ipx::current_core] -quiet $guess]
        if {[llength $cand] > 0} { set bram_if $cand; break }
    }
}

set bram_if_renamed 0
if {$bram_if ne ""} {
    set bram_if_orig_name [get_property NAME $bram_if]
    set_property NAME BRAM_PORTA $bram_if
    set bram_if_renamed 1
    puts "INFO: renamed inferred bus interface '$bram_if_orig_name' -> 'BRAM_PORTA'"
} else {
    puts "WARNING: could not find the inferred BRAM bus interface, by bus type"
    puts "  or by any of the guessed names (bram, bram_a, BRAM, bram_porta)."
    puts "  Run 'ipx::get_bus_interfaces -of_objects \[ipx::current_core\]' to"
    puts "  see what it was actually named, then either rename it to"
    puts "  BRAM_PORTA by hand or update the get_bd_intf_pins reference in the"
    puts "  bd stage to match. Continuing without it: the packaged IP will"
    puts "  still build, but the bd stage's BRAM_PORTA connection will fail"
    puts "  until this is resolved."
}

set bram_param_fail 0
if {$bram_if_renamed} {
    set bram_if [ipx::get_bus_interfaces -quiet BRAM_PORTA \
                     -of_objects [ipx::current_core]]
    if {[llength $bram_if] > 0} {
        # Kompletan skup parametara koje AXI BRAM kontroler ocekuje na
        # BRAM interfejsu.Cim se postavi MASTER_TYPE = BRAM_CTRL,
        # kontroler u svojoj post_propagate proceduri trazi i ostale, pa
        # nepotpun skup daje:
        #   ERROR: [axi_bram_cntlr-1] Port-A interface property <CONFIG.READ_WRITE_MODE> is not defined
        # i validate_bd_design pada.  Ili se postave svi, ili nijedan.
        # READ_WRITE_MODE je READ_WRITE iako se sa strane magistrale samo
        # upisuje: kontroler je taj koji odlucuje smjer, a interfejs samo
        # opisuje sta je fizicki moguce.
        foreach {pname pval} {
            MASTER_TYPE     BRAM_CTRL
            MEM_SIZE        65536
            MEM_WIDTH       32
            MEM_ECC         NONE
            READ_WRITE_MODE READ_WRITE
            READ_LATENCY    1
        } {
            if {[catch {
                if {[llength [ipx::get_bus_parameters -quiet $pname \
                                  -of_objects $bram_if]] == 0} {
                    ipx::add_bus_parameter $pname $bram_if
                }
                set_property value $pval \
                    [ipx::get_bus_parameters $pname -of_objects $bram_if]
                puts "INFO: BRAM_PORTA bus parameter $pname = $pval"
            } err]} {
                puts "WARNING: could not set BRAM_PORTA parameter $pname: $err"
                incr bram_param_fail
            }
        }

        # Ako je MASTER_TYPE postavljen a neki od ostalih
        # parametara nije, AXI BRAM kontroler ce u bd fazi pasti sa
        # "Port-A interface property <CONFIG.XXX> is not defined".  U tom
        # slucaju je bolje ukloniti MASTER_TYPE i vratiti se na stanje prije
        # ove optimizacije: bd faza tada prolazi, uz dva bezopasna upozorenja
        # (BD 41-237 i BD 41-926), umjesto da buildovanje stane.
        if {$bram_param_fail > 0} {
            puts "WARNING: $bram_param_fail BRAM_PORTA parametar(a) nije postavljeno."
            puts "  Uklanjam MASTER_TYPE da bd faza ne bi pala u post_propagate."
            puts "  Posljedica su samo upozorenja BD 41-237 i BD 41-926."
            catch {
                ipx::remove_bus_parameter MASTER_TYPE $bram_if
            }
        }
    }
}


if {$bram_if_renamed} {

    catch {
        ipx::infer_bus_interface bram_clk_a xilinx.com:signal:clock:1.0 [ipx::current_core]
    }
    if {[catch {
        ipx::associate_bus_interfaces -busif BRAM_PORTA -clock bram_clk_a [ipx::current_core]
    } err]} {
        puts "WARNING: could not associate BRAM_PORTA with clock bram_clk_a: $err"
        puts "  Continuing without it -- the packaged IP still builds and"
        puts "  functions correctly either way. If you want this cosmetic"
        puts "  metadata set, do it by hand: open the IP in the Vivado IP"
        puts "  packager GUI, go to Ports and Interfaces, select bram_clk_a,"
        puts "  and set its Associated Bus Interface to BRAM_PORTA."
    }
} else {
    puts "WARNING: skipping BRAM_PORTA clock association -- see the warning"
    puts "  above. bram_clk_a will show as unassociated in the packaged IP."
}

ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums  [ipx::current_core]
ipx::save_core         [ipx::current_core]
close_project -delete
puts "INFO: IP packaged into $ip_repo_dir"
}

#Blok dizajn
if {$stage eq "bd" || $stage eq "all"} {
puts "INFO: building block design ..."
create_project ${ip_name}_system $bd_proj_dir -part $part_name -force
set_property target_language VHDL [current_project]

set bp_found [get_board_parts -quiet "digilentinc.com:zybo-z7-10:part0:*"]
if {[llength $bp_found] > 0} {
    set board_part [lindex $bp_found 0]
    set_property board_part $board_part [current_project]
    puts "INFO: board part $board_part found and applied."
} else {
    puts "INFO: no Zybo Z7-10 board part installed.  This is fine -- the PS7"
    puts "      configuration is applied explicitly below and does not depend"
    puts "      on the board files being present."
}
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog -rebuild

create_bd_design "vj_system"


set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 zynq_ps]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} $ps

set vj_apply_ddr 1
vj_apply_zybo_z7_ps7_config $ps $vj_apply_ddr

# akcelerator
set vj [create_bd_cell -type ip -vlnv ${ip_vendor}:user:${ip_name}:${ip_version} vj_0]


# AXI BRAM kontroler za rad s integralnim slikama
set bramc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl row_bram_ctrl]
set_property -dict [list \
    CONFIG.SINGLE_PORT_BRAM {1} \
    CONFIG.DATA_WIDTH {32} ] $bramc

connect_bd_intf_net [get_bd_intf_pins row_bram_ctrl/BRAM_PORTA] \
                    [get_bd_intf_pins vj_0/BRAM_PORTA]

# bram_wrdata_a se MORA povezati rucno preko skripte.Vivado BRAM_PORTA posmatra kao
# SLAVE interfejs (upozorenje IP_Flow 19-5462 u ip fazi), a na slave BRAM
# interfejsu je wrdata IZLAZ - memorija vraca podatak.Nas bram_wrdata_a je
# ULAZ, pa nije uslo u interfejs i ostaje nepovezano.
# Vivado ce zbog ove linije javiti BD 41-1306 ("overridden by the user").  To
# upozorenje je OCEKIVANO i bezopasno: pin ionako nije bio dio interfejsne veze.
connect_bd_net [get_bd_pins row_bram_ctrl/bram_wrdata_a] \
               [get_bd_pins vj_0/bram_wrdata_a]


#interconnect i clocking
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config [list Master {/zynq_ps/M_AXI_GP0} Clk {Auto}] \
    [get_bd_intf_pins vj_0/S00_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config [list Master {/zynq_ps/M_AXI_GP0} Clk {Auto}] \
    [get_bd_intf_pins row_bram_ctrl/S_AXI]

connect_bd_net [get_bd_pins vj_0/irq] [get_bd_pins zynq_ps/IRQ_F2P]

assign_bd_address

set row_seg {}
foreach s [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces zynq_ps/Data]] {
    if {[string match "*row_bram_ctrl*" $s]} { set row_seg $s ; break }
}
if {[llength $row_seg] == 0} {
    error "vj_project.tcl: no address segment for row_bram_ctrl in\
           zynq_ps/Data -- assign_bd_address did not map the BRAM controller."
}

set_property offset 0x42000000 $row_seg
set_property range  64K        $row_seg

# Vivado prijavljuje opseg u razlicitim oblicima zavisno od toga kako je
# postavljen: "64K" ako je tako upisan, ali "0x00010000" nakon set_property.
# Zato se poredi BROJ BAJTOVA, a ne string - inace ispravan opseg pada na
# provjeri samo zato sto je ispisan heksadecimalno.
proc vj_range_bytes {r} {
    if {[regexp {^0[xX][0-9a-fA-F]+$} $r]} {
        return [expr {$r}]
    }
    if {[regexp {^([0-9]+)([KMG]?)$} $r -> num suf]} {
        switch -- $suf {
            K       { return [expr {$num * 1024}] }
            M       { return [expr {$num * 1024 * 1024}] }
            G       { return [expr {$num * 1024 * 1024 * 1024}] }
            default { return $num }
        }
    }
    return -1
}

set row_range [get_property range $row_seg]
set row_bytes [vj_range_bytes $row_range]
puts "INFO: $row_seg  offset=[get_property offset $row_seg]\
      range=$row_range ([expr {$row_bytes / 1024}] KB)"
if {$row_bytes != 65536} {
    report_property $row_seg
    error "vj_project.tcl: opseg adresa za row_bram_ctrl je $row_range\
           ([expr {$row_bytes / 1024}] KB), a ocekuje se 64 KB (65536).  Pri\
           manjem opsegu dostupne su samo banke 0-3 od 27, a svi upisi u banke\
           4-26 se neprimjetno gube.  Ispraviti prije generisanja bitstreama\
           u adresnom editoru, pa ponoviti\
           ovu fazu."
}

set vj_seg {}
foreach s [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces zynq_ps/Data]] {
    if {[string match "*vj_0*" $s]} { set vj_seg $s ; break }
}
if {[llength $vj_seg] > 0} {
    set_property offset 0x40000000 $vj_seg
    puts "INFO: $vj_seg  offset=[get_property offset $vj_seg]\
          range=[get_property range $vj_seg]"
} else {
    puts "WARNING: no address segment found for vj_0 -- check that M_AXI_GP0\
          reached the accelerator."
}


puts "\n================ vj_project bd stage summary ================"
puts [format "  %-28s %s" "UART1 routing"  [get_property CONFIG.PCW_UART1_UART1_IO $ps]]
puts [format "  %-28s %s" "MIO bank 1 voltage" [get_property CONFIG.PCW_PRESET_BANK1_VOLTAGE $ps]]
puts [format "  %-28s %s" "DDR part" [get_property CONFIG.PCW_UIPARAM_DDR_PARTNO $ps]]
puts [format "  %-28s %s" "DDR high address" [get_property CONFIG.PCW_DDR_RAM_HIGHADDR $ps]]
puts [format "  %-28s %s" "Fabric clock (MHz)" [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps]]
puts [format "  %-28s %s / %s (%d KB)" "row_bram_ctrl" \
          [get_property offset $row_seg] [get_property range $row_seg] \
          [expr {$row_bytes / 1024}]]
if {[llength $vj_seg] > 0} {
    puts [format "  %-28s %s / %s" "vj_0" \
              [get_property offset $vj_seg] [get_property range $vj_seg]]
}
puts "  Expected: MIO 48 .. 49 | LVCMOS 1.8V | MT41K256M16 RE-125 |"
puts "            0x3FFFFFFF | 100 | 0x42000000 / 64K | 0x40000000 / 4K"
puts "=============================================================\n"

validate_bd_design

# Provjera da bram_wrdata_a stvarno ima source.  Ovo je jedini signal u dizajnu
# koji, ako ostane nepovezan, ne daje nikakvu gresku: Vivado ga veze na nulu,
# bitstream se napravi, ploca proradi i UART ispisuje - a sve sto se upise u
# banke su nule.
set wr_net [get_bd_nets -quiet -of_objects [get_bd_pins vj_0/bram_wrdata_a]]
if {[llength $wr_net] == 0} {
    error "vj_project.tcl: vj_0/bram_wrdata_a nije povezan.  Vivado bi ga vezao\
           na nulu i svi upisi u banke bili bi nule - detekcija ne bi nasla\
           nista, bez ijedne poruke o gresci.  Provjeriti connect_bd_net liniju\
           iznad."
}
puts "INFO: vj_0/bram_wrdata_a povezan preko mreze $wr_net"

# Kompletno poredjenje sa blok dizajnom koji je radio na plocici: sve veze,
# interfejsi, adrese i konfiguracija BRAM kontrolera.
set golden "$root_dir/scripts/vj_bd_golden.tcl"
if {[file exists $golden]} {
    source $golden
    vj_check_bd_against_golden
} else {
    puts "WARNING: nema $golden - preskace se poredjenje sa ispravnim dizajnom"
}

vj_verify_ps7_config $ps $vj_apply_ddr

save_bd_design


make_wrapper -files [get_files vj_system.bd] -top
add_files -norecurse \
    $bd_proj_dir/${ip_name}_system.gen/sources_1/bd/vj_system/hdl/vj_system_wrapper.vhd
set_property top vj_system_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "INFO: block design built and validated"
}

#Sinteza, implementacija, bitstream
if {$stage eq "impl" || $stage eq "all"} {
if {[llength [current_project -quiet]] == 0} {
    open_project $bd_proj_dir/${ip_name}_system.xpr
}


catch { reset_run synth_1 }
catch { reset_run impl_1  }

puts "INFO: synthesising ..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

open_run synth_1 -name synth_1
puts "---- post-synthesis utilisation ----"
report_utilization -file $release_dir/utilization_synth.rpt
report_timing_summary -file $release_dir/timing_synth.rpt

puts "INFO: implementing ..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

open_run impl_1
puts "---- post-implementation reports ----"
report_utilization        -file $release_dir/utilization_impl.rpt
report_timing_summary     -file $release_dir/timing_impl.rpt
report_clock_utilization  -file $release_dir/clock_util.rpt

# wns i Fmax
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set tclk 10.0
puts "INFO: WNS = $wns ns   WHS = $whs ns"
if {$wns > -$tclk} {
    puts [format "INFO: Fmax = %.2f MHz" [expr {1000.0 / ($tclk - $wns)}]]
}

if {$wns < 0.0} {
    error "vj_project.tcl: setup timing NOT met (WNS = $wns ns). Bitstream\
           exported? No. Fix timing before programming the board."
}
if {$whs < 0.0} {
    error "vj_project.tcl: HOLD timing NOT met (WHS = $whs ns). This cannot be\
           fixed by slowing the clock -- it is a placement/routing problem."
}

#Export u Vitis
write_hw_platform -fixed -include_bit -force \
    -file $release_dir/vj_system_wrapper.xsa
puts "INFO: exported $release_dir/vj_system_wrapper.xsa"

}

close_project

set vj_elapsed [expr {[clock seconds] - $vj_t_start}]
puts ""
puts "================================================================"
puts [format "  stage '%s' complete in %d min %02d s" \
          $stage [expr {$vj_elapsed / 60}] [expr {$vj_elapsed % 60}]]
puts "  outputs in $release_dir"
puts "================================================================"

# Izlaz iz Vivada u batch rezimu.
set vj_batch 0
if {[info exists ::env(VJ_BATCH)]} { set vj_batch 1 }
if {[catch {rdi::get_mode} m] == 0 && $m eq "batch"} { set vj_batch 1 }
if {$vj_batch} {
    exit 0
}