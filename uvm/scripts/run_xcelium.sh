#!/bin/bash
#
# run_xcelium.sh
# Pokretanje jednog testa u Xcelium simulatoru.
#     ./run_xcelium.sh                      -> vj_test_full
#     ./run_xcelium.sh vj_test_mode_a       -> zadati test
#     ./run_xcelium.sh vj_test_mode_a 7     -> zadati test i seed
# Skripta rjesava dvije stvari koje xrun sam ne radi:
#  1. classifier_rom.mem mora biti u direktorijumu iz kojeg se simulacija
#     pokrece. vj_classifier_rom.vhd ga otvara preko generika ROM_INIT_FILE
#     cija je podrazumijevana vrijednost prosto "classifier_rom.mem", bez
#     putanje. Zato se ovdje kopira u radni direktorijum.
#  2. tb_vectors.txt se pronalazi preko plusarga +VJ_DATA_DIR, koji je vec u
#     run.f i pokazuje na ../sim u odnosu na scripts direktorijum.
#

set -eu

TEST="${1:-vj_test_full}"
SEED="${2:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v xrun >/dev/null 2>&1; then
    echo "GRESKA: xrun nije u PATH-u. Ucitati Xcelium okruzenje (npr. module load xcelium)."
    exit 1
fi

# ROM init fajl mora biti u radnom direktorijumu
cp -f ../data/classifier_rom.mem ./classifier_rom.mem

mkdir -p ../logs
LOG="../logs/${TEST}_s${SEED}.log"

echo "==============================================================="
echo "Xcelium: $TEST (seed $SEED)"
echo "Log:     $LOG"
echo "==============================================================="

xrun -f run.f \
     +UVM_TESTNAME="$TEST" \
     -svseed "$SEED" \
     -l "$LOG"

echo
if grep -qE "UVM_ERROR *:? *0" "$LOG" && grep -qE "UVM_FATAL *:? *0" "$LOG"; then
    echo "REZULTAT: PASS"
else
    echo "REZULTAT: provjeriti $LOG"
    grep -E "UVM_ERROR|UVM_FATAL" "$LOG" | head -20 || true
fi
