#
# vj_bd_golden.tcl -- provjera generisanog blok dizajna prema poznato ispravnom
# dizajnu koji je rucno napravljen i radio je.
# Referentne vrijednosti su izvucene iz vj_system.bd verzije koja je stvarno
# radila na plocici.
# ocekivane veze (signalne mreze)
# Format: {opis} {pin1 pin2 ...}  - svi navedeni pinovi moraju biti na istoj mrezi
set VJ_GOLDEN_NETS {
    {podatak za upis u banke}
        {row_bram_ctrl/bram_wrdata_a vj_0/bram_wrdata_a}
    {prekid ka procesoru}
        {vj_0/irq zynq_ps/IRQ_F2P}
    {takt akceleratora}
        {zynq_ps/FCLK_CLK0 vj_0/s00_axi_aclk row_bram_ctrl/s_axi_aclk}
    {reset akceleratora}
        {rst_zynq_ps_100M/peripheral_aresetn vj_0/s00_axi_aresetn row_bram_ctrl/s_axi_aresetn}
}

# ---- ocekivane interfejsne veze
set VJ_GOLDEN_INTF {
    {BRAM port A}
        {row_bram_ctrl/BRAM_PORTA vj_0/BRAM_PORTA}
    {AXI ka akceleratoru}
        {zynq_ps_axi_periph/M00_AXI vj_0/s00_axi}
    {AXI ka BRAM kontroleru}
        {zynq_ps_axi_periph/M01_AXI row_bram_ctrl/S_AXI}
}

# ---- ocekivane adrese
# vrijednosti u bajtovima; poredi se broj, ne string
set VJ_GOLDEN_ADDR {
    row_bram_ctrl 0x42000000 65536
    vj_0          0x40000000  4096
}

# ---- ocekivana konfiguracija BRAM kontrolera 
set VJ_GOLDEN_BRAMC {
    DATA_WIDTH       32
    SINGLE_PORT_BRAM 1
}


proc vj_check_bd_against_golden {} {
    global VJ_GOLDEN_NETS VJ_GOLDEN_INTF VJ_GOLDEN_ADDR VJ_GOLDEN_BRAMC

    set bad 0
    puts "\n================ poredjenje sa ispravnim dizajnom ================"

    # --- signalne mreze
    foreach {opis pins} $VJ_GOLDEN_NETS {
        set nets {}
        set missing {}
        foreach pin $pins {
            set p [get_bd_pins -quiet $pin]
            if {[llength $p] == 0} {
                lappend missing "$pin (pin ne postoji)"
                continue
            }
            set n [get_bd_nets -quiet -of_objects $p]
            if {[llength $n] == 0} {
                lappend missing "$pin (nepovezan)"
            } else {
                lappend nets [get_property NAME $n]
            }
        }
        if {[llength $missing] > 0} {
            puts "  FAIL  $opis"
            foreach m $missing { puts "          $m" }
            incr bad
        } elseif {[llength [lsort -unique $nets]] != 1} {
            puts "  FAIL  $opis - pinovi nisu na istoj mrezi: [lsort -unique $nets]"
            incr bad
        } else {
            puts "  ok    $opis  ([lindex $nets 0])"
        }
    }

    # --- interfejsne veze
    foreach {opis pins} $VJ_GOLDEN_INTF {
        set ok 1
        foreach pin $pins {
            set p [get_bd_intf_pins -quiet $pin]
            if {[llength $p] == 0} { set ok 0 ; break }
            if {[llength [get_bd_intf_nets -quiet -of_objects $p]] == 0} { set ok 0 ; break }
        }
        if {$ok} {
            puts "  ok    $opis"
        } else {
            puts "  FAIL  $opis - interfejs nepovezan ili ne postoji"
            incr bad
        }
    }

    # --- adrese
    foreach {cell want_off want_bytes} $VJ_GOLDEN_ADDR {
        set seg {}
        foreach s [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces zynq_ps/Data]] {
            if {[string match "*${cell}*" $s]} { set seg $s ; break }
        }
        if {[llength $seg] == 0} {
            puts "  FAIL  adresa $cell - segment ne postoji"
            incr bad
            continue
        }
        set off [get_property offset $seg]
        set rng [get_property range  $seg]
        set bytes [vj_range_bytes $rng]
        if {$off ne $want_off || $bytes != $want_bytes} {
            puts "  FAIL  adresa $cell - $off / $rng ($bytes B),\
                  ocekuje se $want_off / $want_bytes B"
            incr bad
        } else {
            puts "  ok    adresa $cell  $off / [expr {$bytes/1024}] KB"
        }
    }

    # --- konfiguracija BRAM kontrolera
    foreach {prop want} $VJ_GOLDEN_BRAMC {
        set got [get_property CONFIG.$prop [get_bd_cells row_bram_ctrl]]
        if {$got ne $want} {
            puts "  FAIL  row_bram_ctrl CONFIG.$prop = $got, ocekuje se $want"
            incr bad
        } else {
            puts "  ok    row_bram_ctrl CONFIG.$prop = $got"
        }
    }

    puts "=================================================================="
    if {$bad > 0} {
        error "vj_bd_golden: $bad odstupanje(a) od poznato ispravnog dizajna.\
               Ne generisati bitstream dok se ne rijesi - dizajn se moze\
               uspjesno izgraditi i raditi pogresno."
    }
    puts "  blok dizajn se poklapa sa verzijom koja je radila na plocici.\n"
}
