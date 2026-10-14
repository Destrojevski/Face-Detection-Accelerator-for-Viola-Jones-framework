#!/bin/bash
#
# regression_xcelium.sh
# Regresija u Xcelium simulatoru. Pokretanje iz scripts direktorijuma:
#     ./regression_xcelium.sh
#
# Svaki test pise u zajednicku coverage bazu, pa se na kraju generise jedan
# objedinjeni izvjestaj preko imc-a.
#

set -u

TESTS_SINGLE="vj_test_reset vj_test_regs vj_test_ctrl vj_test_mode_a vj_test_mode_b vj_test_sweep_edge vj_test_rotation vj_test_full"

# Probing hipoteza (za diplomski, ako bude potrebno). Puste se samo sa argumentom --hazards,
# odvojeno od regularnog pokretanja: svaka namjerno gadja nedokumentovano stanje
# dizajna, ocekuje se da prijavi gresku, a neka od njih moze prekinuti
# simulaciju.
TESTS_HAZARD="vj_test_h1_rotbase_25 vj_test_h1_rotbase_31 vj_test_h2_step_zero vj_test_h3_sweep_wrap vj_test_h4_start_busy"
RANDOM_SEEDS="1 2 3 4 5"

# ROM init fajl mora biti u radnom direktorijumu prije bilo kakvog pokretanja
cp -f ../data/classifier_rom.mem ./classifier_rom.mem

COV_DIR="../coverage_xcelium"
LOG_DIR="../logs"
mkdir -p "$LOG_DIR"

fail_count=0
run_count=0

run_one () {
    local test_name="$1"
    local seed="$2"
    local tag="$3"

    echo "==============================================================="
    echo "REGRESIJA: $test_name (seed $seed)"
    echo "==============================================================="

    xrun -f run.f \
         +UVM_TESTNAME="$test_name" \
         -svseed "$seed" \
         -coverage all \
         -covoverwrite \
         -covworkdir "$COV_DIR" \
         -covtest "$tag" \
         -l "$LOG_DIR/${tag}.log"

    run_count=$((run_count + 1))

    if grep -q "UVM_ERROR *: *0" "$LOG_DIR/${tag}.log" && \
       grep -q "UVM_FATAL *: *0" "$LOG_DIR/${tag}.log"; then
        echo "  -> PASS"
    else
        echo "  -> FAIL (detalji u $LOG_DIR/${tag}.log)"
        fail_count=$((fail_count + 1))
    fi
}

for t in $TESTS_SINGLE; do
    run_one "$t" 1 "$t"
done

for s in $RANDOM_SEEDS; do
    run_one "vj_test_random" "$s" "vj_test_random_s${s}"
done

# Probing hipoteza samo na eksplicitan zahtjev
if [ "${1:-}" = "--hazards" ]; then
    echo
    echo "==============================================================="
    echo "PROBE HIPOTEZA IZ STATICKE ANALIZE"
    echo "Ocekuje se da ovi testovi prijave greske - to je njihova svrha."
    echo "==============================================================="
    for t in $TESTS_HAZARD; do
        run_one "$t" 1 "$t" || true
    done
fi

echo "==============================================================="
echo "REGRESIJA ZAVRSENA: $run_count pokretanja, $fail_count neuspjelih"
echo "Coverage baza: $COV_DIR"
echo "Izvjestaj:     imc -load $COV_DIR"
echo "==============================================================="

exit $fail_count
