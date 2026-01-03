#!/bin/bash
# Submit array jobs for SPEI calculation

TASK_FILE="spei_tasks.txt"
TOTAL_TASKS=$(wc -l < "$TASK_FILE")

# Submit 25 array jobs at a time (adjust based on your cluster limits)
CONCURRENT_JOBS=50
ARRAY_START=0
ARRAY_END=$((TOTAL_TASKS - 1))

echo "Submitting array job for $TOTAL_TASKS tasks"
echo "Array range: $ARRAY_START-$ARRAY_END"
echo "Concurrent jobs: $CONCURRENT_JOBS"

sbatch --array=${ARRAY_START}-${ARRAY_END}%${CONCURRENT_JOBS} << 'EOF'
#!/bin/bash
#SBATCH --job-name=spei_array
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --mail-type=END,FAIL
#SBATCH --account=bk1318
#SBATCH --output=logs/spei_%A_%a.log
#SBATCH --error=logs/spei_%A_%a.err

# Load modules
module purge
module load r/4.1.2-gcc-11.2.0
module load gcc/11.2.0-gcc-11.2.0
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/4.1/
module load pytorch
source activate
conda activate minu_80

# Get task
TASK_ID=$SLURM_ARRAY_TASK_ID
TASK_FILE="spei_tasks.txt"

if [ -z "$TASK_ID" ]; then
    echo "Error: No task ID provided"
    exit 1
fi

# Read task parameters
IFS='|' read -r INPUT_FILE OUTPUT_DIR SET_TYPE MONTH ZONE ENSEMBLE <<< "$(sed -n "$((TASK_ID + 1))p" "$TASK_FILE")"

echo "========================================"
echo "Task ID: $TASK_ID"
echo "Input: $INPUT_FILE"
echo "Output: $OUTPUT_DIR"
echo "Set: $SET_TYPE"
echo "Month: $MONTH"
echo "Zone: $ZONE"
echo "Ensemble: $ENSEMBLE"
echo "========================================"

# Check if output already exists (for restart capability)
if [ -f "$OUTPUT_DIR/metadata.json" ]; then
    echo "Output already exists, skipping..."
    exit 0
fi

# Run SPEI calculation
python np_spei_calculator.py "$INPUT_FILE" \
    -o "$OUTPUT_DIR" \
    -v "wb" \
    --scale 3 \
    -r "np_spei.R" \
    -rs 1981 \
    -re 2010 \
    -c "config/config.json"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "Successfully completed task $TASK_ID"
else
    echo "Failed task $TASK_ID with exit code $EXIT_CODE"
    exit $EXIT_CODE
fi
EOF

echo "Job submitted with ID: $JOB_ID"