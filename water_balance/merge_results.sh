#!/bin/bash
#SBATCH --job-name=water_balance_merge
#SBATCH --output=water_balance_merge.out
#SBATCH --partition=interactive
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=END
#SBATCH --account=bb1478

module load cdo

# Check input argument
if [ $# -ne 1 ]; then
  echo "Usage: sbatch merge_results.sh <zone>"
  exit 1
fi

ZONE=$1
OUTPUT_DIR="./data/zone${ZONE}"
TMP_DIR="${OUTPUT_DIR}/tmp"

# Merge training datasets
cdo mergetime ${TMP_DIR}/water_balance_training_*.nc ${OUTPUT_DIR}/water_balance_training_zone${ZONE}.nc

# Merge testing datasets
cdo mergetime ${TMP_DIR}/water_balance_testing_*.nc ${OUTPUT_DIR}/water_balance_testing_zone${ZONE}.nc

# Cleanup temporary files
rm -rf ${TMP_DIR}
echo "Merging completed for zone ${ZONE}"