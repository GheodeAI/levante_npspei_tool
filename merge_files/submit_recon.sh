#!/bin/bash
#SBATCH --job-name=recon_np_spei_array
#SBATCH --partition=interactive
#SBATCH --nodes=1
#SBATCH --time=11:30:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=50G
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=END,FAIL
#SBATCH --account=bk1318
#SBATCH --output=logs/out_sh_np_spei_%A_%a.log
#SBATCH --array=1-50

module purge
module load pytorch
source activate
conda activate minu_80

# Calculate ensemble and type from array index
# Array indices 1-25: training, 26-50: testing
if [ $SLURM_ARRAY_TASK_ID -le 25 ]; then
    ENS=$(printf "%02d" $SLURM_ARRAY_TASK_ID)
    TYPE="training"
    YEARS="1993_2014"
else
    ENS=$(printf "%02d" $((SLURM_ARRAY_TASK_ID - 25)))
    TYPE="testing"
    YEARS="2015_2015"
fi

OUTPUT_DIR="data/zone5/ens${ENS}/spei_${TYPE}_ens${ENS}"
OUTPUT_FILE="npspei_${YEARS}_ens${ENS}.nc"

# Check if processing is already complete
if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
    # Check if file has the processing_complete attribute
    if ncdump -h "$OUTPUT_DIR/$OUTPUT_FILE" | grep -q "processing_complete.*True"; then
        echo "Processing already complete for ensemble $ENS, type $TYPE. Skipping."
        exit 0
    fi
fi

echo "Starting/resuming processing for ensemble $ENS, type $TYPE"
python create_netcdf.py \
    --output-dir "$OUTPUT_DIR" \
    --output-file "$OUTPUT_FILE"

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "Processing failed with exit code $EXIT_CODE"
    exit $EXIT_CODE
fi
