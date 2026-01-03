#!/bin/bash
# Create task list for all SPEI calculations

DATA_DIR="data"
TASK_FILE="spei_tasks.txt"

> "$TASK_FILE"

for zone in {1..5}; do
    for ensemble in $(seq -f "%02g" 1 25); do
        # Training files
        for month in "01_January" "02_February" "03_March" "04_April" "05_May" "06_June" \
                     "07_July" "08_August" "09_September" "10_October" "11_November" "12_December"; do
            
            # Training file
            training_file="${DATA_DIR}/zone${zone}/ens${ensemble}/water_balance_training_${month}_ens${ensemble}.nc"
            if [ -f "$training_file" ]; then
                output_dir="${DATA_DIR}/zone${zone}/ens${ensemble}/spei_training_${month}_ens${ensemble}"
                mkdir -p "$output_dir"
                echo "$training_file|$output_dir|training|${month}|zone${zone}|ens${ensemble}" >> "$TASK_FILE"
            fi
            
            # Testing file
            testing_file="${DATA_DIR}/zone${zone}/ens${ensemble}/water_balance_testing_${month}_ens${ensemble}.nc"
            if [ -f "$testing_file" ]; then
                output_dir="${DATA_DIR}/zone${zone}/ens${ensemble}/spei_testing_${month}_ens${ensemble}"
                mkdir -p "$output_dir"
                echo "$testing_file|$output_dir|testing|${month}|zone${zone}|ens${ensemble}" >> "$TASK_FILE"
            fi
        done
    done
done

echo "Total tasks: $(wc -l < "$TASK_FILE")"
echo "Task file created: $TASK_FILE"