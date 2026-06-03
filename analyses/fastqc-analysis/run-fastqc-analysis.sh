#!/bin/bash

set -e
set -o pipefail

# Parallel FastQC: MAX_PARALLEL jobs × FASTQC_THREADS threads each (should match LSF -n)
MAX_PARALLEL="${MAX_PARALLEL:-4}"
FASTQC_THREADS="${FASTQC_THREADS:-4}"

# set up running directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Read root path
rootdir=$(realpath "./../..")
echo "$rootdir"

########################################################################
# Read metadata_dir from YAML configuration file
metadata_dir=$(cat ${rootdir}/project_parameters.Config.yaml | grep 'metadata_dir:' | awk '{print $2}')
metadata_dir=${metadata_dir//\"/}  # Removes all double quotes
echo "Metadata directory: $metadata_dir"  # Output

metadata_file=$(cat ${rootdir}/project_parameters.Config.yaml | grep 'metadata_file_fastqc_module:' | awk '{print $2}')
metadata_file=${metadata_file//\"/}  # Removes all double quotes
echo "Metadata file: $metadata_file"  # Output

# Define the path to the metadata file (adjust to your actual file)
metadata_file="$metadata_dir/$metadata_file"

# Check if metadata file exists
if [ ! -f "$metadata_file" ]; then
  echo "Error: Metadata file '$metadata_file' does not exist."
  exit 1
fi

run_one_fastqc() {
  local file="$1" sample="$2" rep="$3"
  local original_base unique_name temp_fastq

  original_base=$(basename "$file" .fastq.gz)
  unique_name="${sample}_rep${rep}_${original_base}"
  temp_fastq="${unique_name}.fastq.gz"

  ln -sf "$file" "$temp_fastq"
  fastqc -o results/01-fastqc-reports "$temp_fastq" --threads "$FASTQC_THREADS"
  rm -f "$temp_fastq"
}

wait_for_slot() {
  while (( $(jobs -rp | wc -l) >= MAX_PARALLEL )); do
    if ! wait -n 2>/dev/null; then
      sleep 1
    fi
  done
}

################################################################################################################
# Extract sample names and fastq paths; run FastQC in parallel across files
sample_column="ID"
fastq_column="FASTQ"

sample_col_num=$(head -n 1 "$metadata_file" | tr '\t' '\n' | grep -n "^$sample_column$" | cut -d: -f1)
fastq_col_num=$(head -n 1 "$metadata_file" | tr '\t' '\n' | grep -n "^$fastq_column$" | cut -d: -f1)

echo "Sample column: $sample_col_num, FASTQ column: $fastq_col_num"
echo "FastQC parallelism: ${MAX_PARALLEL} jobs, ${FASTQC_THREADS} threads each"

mkdir -p results/01-fastqc-reports

# Process substitution keeps the loop in the main shell (background jobs + wait work correctly)
while IFS=$'\t' read -r -a fields; do
  sample="${fields[$((sample_col_num - 1))]}"
  fastq_field="${fields[$((fastq_col_num - 1))]}"

  # Split on commas to handle technical replicates
  IFS=',' read -ra paths <<< "$fastq_field"

  rep=1
  for raw_path in "${paths[@]}"; do
    clean_path=$(echo "$raw_path" | tr -d '\r' | sed 's/^["'\'']//; s/["'\'']$//')

    echo "Processing sample: $sample, replicate: $rep"

    for file in "$clean_path"/*R1*.fastq.gz; do
      [[ -e "$file" ]] || continue
      echo "  Queuing FastQC on: $file"
      wait_for_slot
      run_one_fastqc "$file" "$sample" "$rep" &
    done

    ((rep++))
  done
done < <(tail -n +2 "$metadata_file" | sort -t$'\t' -k"$sample_col_num")

wait

################################################################################################################
###### STEP 2 ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ######
################################################################################################################
# Run multiqc for all samples in the `results` dir
# to summarize results

cd results/01-fastqc-reports
multiqc .

# rename folder
mv multiqc_data 02-multiqc-reports

# move the files related to multiqc in the main `results` dir
mv 02-multiqc-reports ../
mv multiqc_report.html ../

################################################################################################################
###### THE END ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ###### ######
################################################################################################################
