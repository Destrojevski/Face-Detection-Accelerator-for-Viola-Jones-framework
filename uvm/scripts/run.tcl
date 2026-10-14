#
# run.tcl
# Kreira Vivado projekat, ubacuje RTL i verifikaciono okruzenje, kopira fajlove
# sa podacima u radni direktorijum simulatora i pokrece izabrani test.
# Pokretanje iz Vivado Tcl konzole:
#     source run.tcl
# Promjena testa bez ponovnog kreiranja projekta:
#     set ::vj_test vj_test_mode_b
#     source rerun.tcl
#

# Direktorijum projekta
set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize $script_dir/..]
set result_dir $root_dir/vivado_project

# Test koji se pokrece prvi put. Moze se prepisati prije source-ovanja skripte.
if {![info exists ::vj_test]} {
    set ::vj_test vj_test_full
}

file mkdir $result_dir

create_project vj_uvm $result_dir -part xc7z010clg400-1 -force
set_property board_part digilentinc.com:zybo-z7-10:part0:1.2 [current_project]

# RTL (VHDL). Paketi idu prvi jer ih ostale komponente koriste.
add_files -norecurse [list \
    $root_dir/rtl/vj_pkg.vhd \
    $root_dir/rtl/vj_stage_pkg.vhd \
    $root_dir/rtl/vj_bank_array.vhd \
    $root_dir/rtl/vj_classifier_rom.vhd \
    $root_dir/rtl/vj_datapath.vhd \
    $root_dir/rtl/vj_controlpath.vhd \
    $root_dir/rtl/vj_cascade_core.vhd \
    $root_dir/rtl/vj_cascade_v1_0_S00_AXI.vhd \
    $root_dir/rtl/vj_cascade_v1_0.vhd \
]

# Svi RTL fajlovi su VHDL-93 ili noviji
set_property file_type {VHDL} [get_files -filter {FILE_TYPE == VHDL}]

update_compile_order -fileset sources_1


# Verifikaciono okruzenje (SystemVerilog).
#
# Redoslijed je bitan: paketi se moraju kompajlirati onim redom kojim se
# medjusobno uvoze.
#   vj_defs_pkg  ->  vj_config_pkg  ->  agentski paketi  ->  vj_seq_pkg
#                ->  vj_test_pkg    ->  interfejs i top

set_property SOURCE_SET sources_1 [get_filesets sim_1]

add_files -fileset sim_1 -norecurse [list \
    $root_dir/verif/config/vj_defs_pkg.sv \
    $root_dir/verif/config/vj_config_pkg.sv \
    $root_dir/verif/agent_axil/vj_axil_agent_pkg.sv \
    $root_dir/verif/agent_bram/vj_bram_agent_pkg.sv \
    $root_dir/verif/seq/vj_seq_pkg.sv \
    $root_dir/verif/tests/vj_test_pkg.sv \
    $root_dir/verif/vj_if.sv \
    $root_dir/verif/vj_top.sv \
]

set_property file_type {SystemVerilog} [get_files -of [get_filesets sim_1] -filter {FILE_TYPE =~ *Verilog*}]
set_property top vj_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1


# Include putanje. Svaki paket ukljucuje fajlove iz svog direktorijuma, pa
# xvlog mora znati gdje da ih trazi.

set inc_dirs [list \
    $root_dir/verif \
    $root_dir/verif/config \
    $root_dir/verif/agent_axil \
    $root_dir/verif/agent_bram \
    $root_dir/verif/seq \
    $root_dir/verif/tests \
]

set inc_opts "-L uvm"
foreach d $inc_dirs { append inc_opts " -i $d" }

set_property -name {xsim.compile.xvlog.more_options}   -value $inc_opts    -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.xelab.more_options} -value {-L uvm}     -objects [get_filesets sim_1]


# Kopiranje fajlova sa podacima u radni direktorijum simulatora.
# classifier_rom.mem cita vj_classifier_rom.vhd preko generika ROM_INIT_FILE,
# a tb_vectors.txt cita vj_config.sv. Oba se otvaraju relativno u odnosu na
# radni direktorijum xsim-a, pa moraju biti tamo.
proc vj_copy_data {root_dir result_dir} {
    set sim_dir $result_dir/vj_uvm.sim/sim_1/behav/xsim
    file mkdir $sim_dir
    file copy -force $root_dir/data/classifier_rom.mem $sim_dir/classifier_rom.mem
    file copy -force $root_dir/sim/tb_vectors.txt      $sim_dir/tb_vectors.txt
        if {[file exists $root_dir/sim/tb_frame.txt]} { file copy -force $root_dir/sim/tb_frame.txt $sim_dir/tb_frame.txt }
# tb_frame.txt je opcion - potreban samo za vj_test_frame
if {[file exists $root_dir/sim/tb_frame.txt]} {
    file copy -force $root_dir/sim/tb_frame.txt $sim_dir/tb_frame.txt
}
    puts "vj: podaci kopirani u $sim_dir"
    return $sim_dir
}


# Opcije simulacije
proc vj_set_test {test_name {seed 1} {cov_db ""}} {
    set opts "-testplusarg UVM_TESTNAME=$test_name"
    append opts " -testplusarg UVM_VERBOSITY=UVM_LOW"
    append opts " -sv_seed $seed"
    if {$cov_db ne ""} {
        append opts " -cov_db_name $cov_db"
    }
    set_property -name {xsim.simulate.xsim.more_options} -value $opts -objects [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
    puts "vj: test = $test_name, seed = $seed"
}

vj_copy_data $root_dir $result_dir
vj_set_test $::vj_test 1 covdb_$::vj_test


# Pokretanje. Simulacija se vodi objection mehanizmom - run all staje kada UVM
# spusti posljednju objection i pozove $finish.
launch_simulation
run all

puts "vj: simulacija zavrsena. Za drugi test:"
puts "vj:   set ::vj_test <ime_testa>; source $script_dir/rerun.tcl"
