//
// run.f
//
// Komandni fajl za Xcelium (xrun). Implementirane dvije opcije pokretanja:
// Pokretanje preko wrapper skripte (preporuceno - ona rjesava fajlove sa
// podacima i radni direktorijum):
//     ./run_xcelium.sh vj_test_mode_a
//
// Direktno pokretanje, iz direktorijuma u kojem se nalazi classifier_rom.mem:
//     xrun -f run.f +UVM_TESTNAME=vj_test_mode_a
//
// PRIJE PRVOG POKRETANJA provjeriti -uvmhome ispod. Vrijednost se dobija sa:
//     xrun -version
//     ls $(dirname $(dirname $(which xrun)))/tools/methodology/UVM
//

//
// UVM biblioteka
//
// Ako Xcelium ima ugradjeni UVM, dovoljan je samo -uvm i -uvmhome se moze
// zakomentarisati. Ako elaboracija prijavi da ne moze naci uvm_pkg, odkomentarisati
// i ispraviti putanju.
//
-uvmhome "/eda/cadence/2019-20/RHELx86/XCELIUM_19.03.013/tools/methodology/UVM/CDNS-1.2/"
-uvm

//
// Podrazumijevani test i verbosity. Prepisuju se iz komandne linije.
//
//+UVM_TESTNAME=vj_test_full
+UVM_VERBOSITY=UVM_LOW

//
// Putanja do fajla sa zlatnim vektorima.
// Vrijednost vazi kada se xrun pokrece iz scripts direktorijuma.
//
+VJ_DATA_DIR=../sim

//
// Include putanje za 'include direktive u paketima
//
+incdir+../verif
+incdir+../verif/config
+incdir+../verif/agent_axil
+incdir+../verif/agent_bram
+incdir+../verif/seq
+incdir+../verif/tests

//
// RTL (VHDL). Paketi prvi - ostale komponente ih koriste.
//
-v93
../rtl/vj_pkg.vhd
../rtl/vj_stage_pkg.vhd
../rtl/vj_bank_array.vhd
../rtl/vj_classifier_rom.vhd
../rtl/vj_datapath.vhd
../rtl/vj_controlpath.vhd
../rtl/vj_cascade_core.vhd
../rtl/vj_cascade_v1_0_S00_AXI.vhd
../rtl/vj_cascade_v1_0.vhd

//
// Verifikaciono okruzenje. Redoslijed paketa mora pratiti zavisnosti:
//   vj_defs_pkg -> vj_config_pkg -> agentski paketi -> vj_seq_pkg -> vj_test_pkg
//
-sv ../verif/config/vj_defs_pkg.sv
-sv ../verif/config/vj_config_pkg.sv
-sv ../verif/agent_axil/vj_axil_agent_pkg.sv
-sv ../verif/agent_bram/vj_bram_agent_pkg.sv
-sv ../verif/seq/vj_seq_pkg.sv
-sv ../verif/tests/vj_test_pkg.sv

-sv ../verif/vj_if.sv
-sv ../verif/vj_top.sv

//
// Elaboracija i simulacija
//
-top vj_top
-access +rwc
-timescale 1ns/1ps

//
// Opcije koje mogu zatrebati, zavisno od verzije Xcelium-a. Odkomentarisati
// samo ako elaboracija to trazi:
//   -v200x        ako neki VHDL fajl koristi konstrukcije novije od VHDL-93
//   -relax        blaza provjera pri mjesovitom jezickom povezivanju
//   -nowarn CUVWSP  gasi upozorenje o sirini porta na VHDL/SV granici
//
