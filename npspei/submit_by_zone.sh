#!/bin/bash
# submit_by_zone.sh
# Usage: ./submit_by_zone.sh <zone_number>

ZONE=$1
if [ -z "$ZONE" ]; then
    echo "Usage: $0 <zone_number>"
    exit 1
fi

# Define task file
TASK_FILE="tasks_zone${ZONE}.txt"
> "$TASK_FILE"

# Build Task List
# Format: InputFile | OutputFile
for ensemble in $(seq -f "%02g" 14 14); do
    ENS_DIR="data/zone${ZONE}/ens${ensemble}"
    
    # Training
    TRAIN_IN="${ENS_DIR}/water_balance_training_ens${ensemble}.nc"
    TRAIN_OUT="${ENS_DIR}/spei_training_ens${ensemble}.nc"
    if [ -f "$TRAIN_IN" ]; then
        echo "$TRAIN_IN|$TRAIN_OUT" >> "$TASK_FILE"
    fi
    
    # Testing
    TEST_IN="${ENS_DIR}/water_balance_testing_ens${ensemble}.nc"
    TEST_OUT="${ENS_DIR}/spei_testing_ens${ensemble}.nc"
    if [ -f "$TEST_IN" ]; then
        echo "$TEST_IN|$TEST_OUT" >> "$TASK_FILE"
    fi
done

TOTAL_TASKS=$(wc -l < "$TASK_FILE")
echo "Zone $ZONE has $TOTAL_TASKS files to process."

# Submit Array Job
sbatch --array=0-$((TOTAL_TASKS-1))%25 << EOF
#!/bin/bash
#SBATCH --job-name=spei_z${ZONE}
#SBATCH --partition=interactive
#SBATCH --nodes=1
#SBATCH --time=12:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=1
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=END,FAIL
#SBATCH --account=bk1318
#SBATCH --output=logs/spei_zone${ZONE}_%A_%a.log

module purge
module load r/4.1.2-gcc-11.2.0
module load gcc/11.2.0-gcc-11.2.0
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/4.1/
module load pytorch
source activate
conda activate minu_80

TASK_ID=\$SLURM_ARRAY_TASK_ID
TASK_FILE="tasks_zone${ZONE}.txt"

IFS='|' read -r INPUT_FILE OUTPUT_FILE <<< "\$(sed -n "\$((TASK_ID + 1))p" "\$TASK_FILE")"

echo "Processing Task \$TASK_ID"
echo "In: \$INPUT_FILE"
echo "Out: \$OUTPUT_FILE"

# Call the NEW fast runner
python spei_fast_runner.py \\
    --input "\$INPUT_FILE" \\
    --output "\$OUTPUT_FILE" \\
    --r-script "np_spei_optimized.R" \\
    --scale 3 \\
    --ref-start 1981 \\
    --ref-end 2010

echo "Done."
EOF