#!/bin/bash
#SBATCH --job-name=water_balance
#SBATCH --output=logs/water_balance_%a_%A.out
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=08:00:00
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=END
#SBATCH --account=bb1481
#SBATCH --cpus-per-task=1
#SBATCH --array=1-12

# original account=bk1318
# original partition=interactive
# original 
module purge
module load r/4.1.2-gcc-11.2.0
module load gcc/11.2.0-gcc-11.2.0
module load netcdf-c
module load cdo
export R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/4.1
#export LD_LIBRARY_PATH_BACKUP=$LD_LIBRARY_PATH 
module load pytorch
source activate
conda activate minu_80
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH_BACKUP

# Check input argument
if [ $# -ne 1 ]; then
  echo "Usage: sbatch run_water_balance.sh <zone>"
  exit 1
fi

ZONE=$1
OUTPUT_DIR="data/zone${ZONE}"

# Create directories
mkdir -p ${OUTPUT_DIR}
mkdir -p logs

# Month names corresponding to directory structure
MONTHS=("01_January" "02_February" "03_March" "04_April" "05_May" "06_June" "07_July" "08_August" "09_September" "10_October" "11_November" "12_December")
MONTH=${MONTHS[$SLURM_ARRAY_TASK_ID-1]}

# Process specific month
echo "Processing zone ${ZONE}, month ${MONTH}"
echo "Starting at: $(date)"

# Run R script and capture exit code
Rscript compute_water_balance.R ${ZONE} ${MONTH} ${OUTPUT_DIR}
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "SUCCESS: Completed zone ${ZONE}, month ${MONTH}"
else
    echo "WARNING: Zone ${ZONE}, month ${MONTH} completed with exit code ${EXIT_CODE}"
    # Don't exit - let other months continue
fi

echo "Finished at: $(date)"