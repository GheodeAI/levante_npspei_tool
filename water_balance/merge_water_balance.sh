#!/bin/bash
# Merge monthly water balance into 1 file (non-SLURM version)

ZONE=$1
if [ -z "$ZONE" ]; then
    echo "Usage: $0 <zone_number>"
    echo "Example: $0 1"
    exit 1
fi

# Load CDO if your system uses environment modules
if command -v module &> /dev/null; then
    module purge
    module load cdo
fi

# Process training and testing datasets for each ensemble member
for j in training testing; do
    for i in {01..25}; do
        for month in {01..12}; do
            # Extract a single month from the original file
            cdo selmon,${month#0} "data/zone${ZONE}/ens${i}/water_balance_${j}_${month}_*_ens${i}.nc" \
                "data/zone${ZONE}/ens${i}/water_balance_${j}_month_${month}_filtered.nc"
        done
        # Merge all monthly files for this ensemble and dataset
        cdo mergetime "data/zone${ZONE}/ens${i}/water_balance_${j}"*"_filtered.nc" \
            "data/zone${ZONE}/ens${i}/water_balance_${j}_ens${i}.nc"
        # Clean up temporary monthly files
        rm "data/zone${ZONE}/ens${i}/water_balance_${j}"*"_filtered.nc"
    done
done

# Extend testing data with training years (1993–2010)
for i in {01..20}; do
    cdo selyear,1993/2010 "data/zone${ZONE}/ens${i}/water_balance_training_ens${i}.nc" \
        "data/zone${ZONE}/ens${i}/temp_1993_2010.nc"
    cdo mergetime "data/zone${ZONE}/ens${i}/temp_1993_2010.nc" \
        "data/zone${ZONE}/ens${i}/water_balance_testing_ens${i}.nc" \
        "data/zone${ZONE}/ens${i}/water_balance_testing_extended_ens${i}.nc"
    rm -v "data/zone${ZONE}/ens${i}/temp_1993_2010.nc"
    rm -v "data/zone${ZONE}/ens${i}/water_balance_testing_ens${i}.nc"
done
