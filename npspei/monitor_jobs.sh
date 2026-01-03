#!/bin/bash
# Monitor the progress of SPEI jobs

echo "=== Job Monitoring ==="
echo "Current time: $(date)"
echo ""

# Check squeue for SPEI jobs
echo "Active SPEI jobs:"
squeue -u $USER -o "%.10i %.9P %.20j %.8u %.8T %.10M %.9l %.6D %R" | grep spei

echo ""
echo "=== Completed Jobs ==="

# Check for completed output directories
TOTAL_FILES=0
COMPLETED=0

for zone in {1..5}; do
    for ensemble in $(seq -f "%02g" 1 25); do
        for set_type in training testing; do
            for month in "01_January" "02_February" "03_March" "04_April" "05_May" "06_June" \
                         "07_July" "08_August" "09_September" "10_October" "11_November" "12_December"; do
                
                file="data/zone${zone}/ens${ensemble}/water_balance_${set_type}_${month}_ens${ensemble}.nc"
                if [ -f "$file" ]; then
                    TOTAL_FILES=$((TOTAL_FILES + 1))
                    output_dir="data/zone${zone}/spei_${set_type}_${month}_ens${ensemble}"
                    if [ -f "$output_dir/metadata.json" ]; then
                        COMPLETED=$((COMPLETED + 1))
                    fi
                fi
            done
        done
    done
done

echo "Total files to process: $TOTAL_FILES"
echo "Completed: $COMPLETED"
echo "Remaining: $((TOTAL_FILES - COMPLETED))"
PERCENTAGE=$((COMPLETED * 100 / TOTAL_FILES))
echo "Progress: ${PERCENTAGE}%"

# Show failed jobs if any
echo ""
echo "=== Checking for failed jobs ==="
find data -name "*.log" -type f | xargs grep -l "ERROR\|FAILED\|Error" | head -10