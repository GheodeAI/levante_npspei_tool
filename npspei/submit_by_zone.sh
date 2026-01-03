#!/bin/bash
# Process one zone at a time with all ensembles and months

ZONE=$1
if [ -z "$ZONE" ]; then
    echo "Usage: $0 <zone_number>"
    echo "Example: $0 1"
    exit 1
fi

# Create task file for this zone
TASK_FILE="tasks_zone${ZONE}.txt"
> "$TASK_FILE"

for ensemble in $(seq -f "%02g" 1 3); do
    for month in "01_January" "02_February" "03_March" "04_April" "05_May" "06_June" \
                 "07_July" "08_August" "09_September" "10_October" "11_November" "12_December"; do
        
        # Training
        training_file="data/zone${ZONE}/ens${ensemble}/water_balance_training_${month}_ens${ensemble}.nc"
        if [ -f "$training_file" ]; then
            output_dir="data/zone${ZONE}/ens${ensemble}/spei_training_${month}_ens${ensemble}"
            mkdir -p "$output_dir"
            echo "$training_file|$output_dir" >> "$TASK_FILE"
        fi
        
        # Testing
        testing_file="data/zone${ZONE}/ens${ensemble}/water_balance_testing_${month}_ens${ensemble}.nc"
        if [ -f "$testing_file" ]; then
            output_dir="data/zone${ZONE}/ens${ensemble}/spei_testing_${month}_ens${ensemble}"
            mkdir -p "$output_dir"
            echo "$testing_file|$output_dir" >> "$TASK_FILE"
        fi
    done
done

TOTAL_TASKS=$(wc -l < "$TASK_FILE")
echo "Zone $ZONE has $TOTAL_TASKS tasks"

# Submit array job for this zone
sbatch --array=0-$((TOTAL_TASKS-1))%25 << EOF
#!/bin/bash
#SBATCH --job-name=spei_zone${ZONE}
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --mail-type=END
#SBATCH --account=bb1245
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

IFS='|' read -r INPUT_FILE OUTPUT_DIR <<< "\$(sed -n "\$((TASK_ID + 1))p" "\$TASK_FILE")"

echo "Processing zone ${ZONE}, task \$TASK_ID"
echo "Input: \$INPUT_FILE"

python np_spei_calculator.py "\$INPUT_FILE" \\
    -o "\$OUTPUT_DIR" \\
    -v "wb" \\
    --scale 3 \\
    -r "np_spei.R" \\
    -rs 1981 \\
    -re 2010 \\
    -c "config/config.json"
EOF