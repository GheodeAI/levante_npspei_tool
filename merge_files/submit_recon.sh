#!/bin/bash
#SBATCH --job-name=recon_np_spei
#SBATCH --partition=interactive
#SBATCH --nodes=1
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=20G
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=END
#SBATCH --account=bb1245
#SBATCH --output=out_sh_np_spei_recon.log

module purge

module load pytorch
source activate
conda activate minu_80


python create_netcdf.py \
    --output-dir data/zone5/spei_output_0_0 \
    --output-file spei_final_0_0.nc