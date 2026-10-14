#
# coverage.tcl
#
# Objedinjuje coverage baze svih pokretanja iz regresije u jedan HTML izvjestaj:
#     source coverage.tcl
#
# xcrg spaja sve baze koje nadje u xsim.covdb direktorijumu, pa ukupna
# pokrivenost odgovara cijeloj regresiji, a ne pojedinacnom testu.
#

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize $script_dir/..]
set cov_db     $root_dir/vivado_project/vj_uvm.sim/sim_1/behav/xsim/xsim.covdb
set report_dir $root_dir/coverage

file mkdir $report_dir

if {![file isdirectory $cov_db]} {
    puts "vj: coverage baza nije pronadjena na $cov_db"
    puts "vj: prvo pokrenuti regresiju (source regression.tcl)"
} else {
    exec xcrg -report_format html -dir $cov_db -report_dir $report_dir
    puts "vj: coverage izvjestaj generisan u $report_dir/index.html"
}
