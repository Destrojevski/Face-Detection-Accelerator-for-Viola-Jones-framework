#
# rerun.tcl
# Ponovno pokretanje drugog testa nad vec kreiranim projektom.
#
#     set ::vj_test vj_test_mode_b
#     source rerun.tcl
#
# close_sim je obavezan pri promjeni testa - bez njega xsim ponovo koristi
# kesirani snapshot sa starim UVM_TESTNAME plusargom.
#

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize $script_dir/..]
set result_dir $root_dir/vivado_project

if {![info exists ::vj_test]} {
    set ::vj_test vj_test_full
}
if {![info exists ::vj_seed]} {
    set ::vj_seed 1
}

# Zatvaranje prethodne simulacije i brisanje kesa
catch { close_sim }

set opts "-testplusarg UVM_TESTNAME=$::vj_test"
append opts " -testplusarg UVM_VERBOSITY=UVM_LOW"
append opts " -sv_seed $::vj_seed"
append opts " -cov_db_name covdb_$::vj_test"

set_property -name {xsim.simulate.xsim.more_options} -value $opts -objects [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]

# Fajlovi sa podacima moraju postojati i poslije brisanja radnog direktorijuma
set sim_dir $result_dir/vj_uvm.sim/sim_1/behav/xsim
file mkdir $sim_dir
file copy -force $root_dir/data/classifier_rom.mem $sim_dir/classifier_rom.mem
file copy -force $root_dir/sim/tb_vectors.txt      $sim_dir/tb_vectors.txt
# tb_frame.txt je opcion - potreban samo za vj_test_frame
if {[file exists $root_dir/sim/tb_frame.txt]} {
    file copy -force $root_dir/sim/tb_frame.txt $sim_dir/tb_frame.txt
}

puts "vj: pokrecem $::vj_test (seed $::vj_seed)"
launch_simulation
run all
