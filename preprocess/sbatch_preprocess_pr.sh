#!/bin/bash
#SBATCH --job-name=preprocess_pr
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --time=08:00:00
#SBATCH --mem=0
#SBATCH --mail-user=cosmin.marina@uah.es
#SBATCH --mail-type=END
#SBATCH --account=bk1318
#SBATCH --output=out_sh_pr2.log

module load cdo
module load pytorch
source activate
conda activate minu_80

python preprocess_pr_model.py -z 2

