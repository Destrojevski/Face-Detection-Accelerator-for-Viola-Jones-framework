#
# regression.tcl
#
# Regresija: pusta sve testove jedan za drugim, svaki u svoju coverage bazu,
# i na kraju ispisuje zbirni pregled.
# Pokretanje iz Vivado Tcl konzole, nakon sto je projekat vec kreiran run.tcl-om:
#     source regression.tcl
#
# Nasumicni test se pusta vise puta sa razlicitim seedovima - to je jedini
# nacin da nasumicni stimulus zaista popuni pokrivenost.
#

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize $script_dir/..]
set result_dir $root_dir/vivado_project
set sim_dir    $result_dir/vj_uvm.sim/sim_1/behav/xsim

# Lista testova: {ime_testa broj_seeda}
set vj_regression_list {
    {vj_test_reset       1}
    {vj_test_regs        1}
    {vj_test_ctrl        1}
    {vj_test_mode_a      1}
    {vj_test_mode_b      1}
    {vj_test_sweep_edge  1}
    {vj_test_rotation    1}
    {vj_test_full        1}
    {vj_test_random      5}
}

# Probing hipoteza (za diplomski). NISU dio regularne verifikacije: svaka
# namjerno gadja nedokumentovano stanje dizajna i ocekuje se da prijavi gresku
# ili cak prekine simulaciju. Pustaju se odvojeno, tek nakon sto regularna
# regresija prodje.
set vj_hazard_list {
    vj_test_h1_rotbase_25
    vj_test_h1_rotbase_31
    vj_test_h2_step_zero
    vj_test_h3_sweep_wrap
    vj_test_h4_start_busy
}

set total 0
set run_idx 0

file mkdir $sim_dir

foreach entry $vj_regression_list {
    set test_name [lindex $entry 0]
    set n_seeds   [lindex $entry 1]

    for {set s 1} {$s <= $n_seeds} {incr s} {
        incr run_idx
        incr total

        if {$n_seeds > 1} {
            set db_name "covdb_${test_name}_s${s}"
            set seed_opt "-sv_seed $s"
        } else {
            set db_name "covdb_${test_name}"
            set seed_opt "-sv_seed 1"
        }

        puts "==============================================================="
        puts "REGRESIJA \[$run_idx\]: $test_name  (coverage baza: $db_name)"
        puts "==============================================================="

        catch { close_sim }

        # Podaci moraju biti u radnom direktorijumu prije svakog pokretanja
        file copy -force $root_dir/data/classifier_rom.mem $sim_dir/classifier_rom.mem
        file copy -force $root_dir/sim/tb_vectors.txt      $sim_dir/tb_vectors.txt
        if {[file exists $root_dir/sim/tb_frame.txt]} { file copy -force $root_dir/sim/tb_frame.txt $sim_dir/tb_frame.txt }
# tb_frame.txt je opcion - potreban samo za vj_test_frame
if {[file exists $root_dir/sim/tb_frame.txt]} {
    file copy -force $root_dir/sim/tb_frame.txt $sim_dir/tb_frame.txt
}

        set opts "-testplusarg UVM_TESTNAME=$test_name"
        append opts " -testplusarg UVM_VERBOSITY=UVM_LOW"
        append opts " $seed_opt"
        append opts " -cov_db_name $db_name"

        set_property -name {xsim.simulate.xsim.more_options} -value $opts -objects [get_filesets sim_1]
        set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]

        launch_simulation
        run all
    }
}

catch { close_sim }

puts "==============================================================="
puts "REGRESIJA ZAVRSENA: $total pokretanja"
puts "Coverage baze se nalaze u:"
puts "  $sim_dir/xsim.covdb"
puts "Izvjestaj se generise sa: source coverage.tcl"
puts "==============================================================="
