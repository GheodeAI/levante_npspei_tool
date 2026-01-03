#!/bin/bash
#SBATCH --job-name=spei_all
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --time=08:00:00
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=ALL
#SBATCH --account=bk1318
#SBATCH --output=logs/spei_all_%A_%a.log

module purge
module load r/4.1.2-gcc-11.2.0
module load gcc/11.2.0-gcc-11.2.0
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/4.1/
module load pytorch
source activate
conda activate minu_80

# Base directories
DATA_DIR="data"
R_SCRIPT="np_spei.R"
PY_SCRIPT="np_spei_calculator.py"
CONFIG="config/config.json"

# Parameters
SCALE=3
REF_START=1981
REF_END=2010
VAR_NAME="wb"

# Create logs directory
mkdir -p logs

# Get task ID if running as array job
if [ -n "$SLURM_ARRAY_TASK_ID" ]; then
    TASK_ID=$SLURM_ARRAY_TASK_ID
else
    TASK_ID=0
fi

# Create a task file if it doesn't exist
TASK_FILE="tasks.txt"
if [ ! -f "$TASK_FILE" ]; then
    echo "Creating task list..."
    > "$TASK_FILE"
    
    for zone in {1..1}; do
        for ensemble in $(seq -f "%02g" 1 25); do
            # Find all water balance files for this zone and ensemble
            find "${DATA_DIR}/zone${zone}/ens${ensemble}" -name "water_balance_*.nc" | while read file; do
                # Extract set (training/testing) and month from filename
                filename=$(basename "$file" .nc)
                set_type=$(echo "$filename" | cut -d'_' -f3)  # training or testing
                month_part=$(echo "$filename" | cut -d'_' -f4)  # e.g., "01_January"
                
                # Create output directory
                output_dir="${DATA_DIR}/zone${zone}/ens${ensemble}/spei_output_${month_part}_ens${ensemble}_${set_type}"
                mkdir -p "$output_dir"
                
                # Add to task file
                echo "$file|$output_dir|$set_type|$month_part|zone${zone}|ens${ensemble}" >> "$TASK_FILE"
            done
        done
    done
    echo "Total tasks created: $(wc -l < "$TASK_FILE")"
fi

# Get total tasks
TOTAL_TASKS=$(wc -l < "$TASK_FILE")

# If running as array job, process specific task
if [ -n "$SLURM_ARRAY_TASK_ID" ]; then
    # Read the specific task
    IFS='|' read -r input_file output_dir set_type month_part zone_name ensemble_name <<< "$(sed -n "${TASK_ID}p" "$TASK_FILE")"
    
    echo "Processing task $TASK_ID of $TOTAL_TASKS"
    echo "Input file: $input_file"
    echo "Output dir: $output_dir"
    echo "Set: $set_type"
    echo "Month: $month_part"
    echo "Zone: $zone_name"
    echo "Ensemble: $ensemble_name"
    
    # Run the SPEI calculation
    python "$PY_SCRIPT" "$input_file" \
        -o "$output_dir" \
        -v "$VAR_NAME" \
        --scale "$SCALE" \
        -r "$R_SCRIPT" \
        -rs "$REF_START" \
        -re "$REF_END" \
        -c "$CONFIG"
    
    echo "Completed task $TASK_ID"
else
    # Submit array job
    echo "Submitting array job with $TOTAL_TASKS tasks..."
    sbatch --array=0-$((TOTAL_TASKS-1))%50 << 'EOF'
#!/bin/bash
#SBATCH --job-name=spei_array_%A_%a
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --mail-type=END
#SBATCH --account=bk1318
#SBATCH --output=logs/spei_array_%A_%a.log

module purge
module load r/4.1.2-gcc-11.2.0
module load gcc/11.2.0-gcc-11.2.0
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/4.1/
module load pytorch
source activate
conda activate minu_80

# Read the task
IFS='|' read -r input_file output_dir set_type month_part zone_name ensemble_name <<< "$(sed -n "${SLURM_ARRAY_TASK_ID}p" tasks.txt)"

echo "Processing array task $SLURM_ARRAY_TASK_ID"
echo "Input: $input_file"
echo "Output: $output_dir"

# Run SPEI calculation
python np_spei_calculator.py "$input_file" \
    -o "$output_dir" \
    -v "wb" \
    --scale 3 \
    -r "np_spei.R" \
    -rs 1981 \
    -re 2010 \
    -c "config/config.json"

echo "Completed array task $SLURM_ARRAY_TASK_ID"
EOF
fi