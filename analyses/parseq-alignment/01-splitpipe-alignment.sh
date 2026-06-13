#!/bin/bash

set -euo pipefail

########################################################################
# Parse split-pipe alignment submission script
#
# What this script does
# - Reads project-level settings from project_parameters.Config.yaml
# - Reads the metadata file and identifies required columns:
#     ID, SAMPLE, FASTQ, kit, chemistry
# - Supports FASTQ entries that are:
#     1) one directory
#     2) multiple directories separated by commas
#     3) explicit FASTQ files separated by commas
# - Builds per-sublibrary FASTQ list files (R1 and R2)
# - Submits one split-pipe job per sublibrary/sample
# - Writes results/sublib_list.txt in metadata order for downstream combine
#
# Why use FASTQ list files?
# - Avoids very long command lines for large cohorts / many top-ups
# - Scales better when samples have many FASTQs
# - Leaves an explicit record of exactly which FASTQs were used
#
# IMPORTANT: sample naming consistency
# - split-pipe uses sample names from the sample loading table when creating
#   output folder names
# - If sample names differ between the sample loading table and the metadata
#   file, downstream loading/matching can break
# - Best practice:
#     * keep names identical across metadata and sample loading table
#     * or include a metadata column with the exact names used in the
#       sample loading table and use that consistently downstream
########################################################################

# Load modules
module load ParseBiosciences/1.6.0

# Set up running directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Read root path
rootdir=$(realpath "./../..")
echo "Root directory: $rootdir"

config_file="${rootdir}/project_parameters.Config.yaml"

########################################################################
# Helper functions
########################################################################

get_yaml_value() {
  local key="$1"
  local value
  value=$(grep "^${key}:" "$config_file" | awk '{print $2}')
  value=${value//\"/}
  echo "$value"
}

get_yaml_value_or_default() {
  local key="$1"
  local default="$2"
  local value
  value=$(get_yaml_value "$key")
  if [[ -z "$value" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}

trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  echo "$s"
}

########################################################################
# Read values from YAML configuration file
########################################################################

metadata_dir=$(get_yaml_value "metadata_dir")
metadata_file=$(get_yaml_value "metadata_file_parseq_alignment_module")
sample_loading_table_dir=$(get_yaml_value "sample_loading_table_dir")
sample_loading_table_file=$(get_yaml_value "sample_loading_table_file")
genome_reference_path=$(get_yaml_value "genome_reference_path")
analysis_folder=$(get_yaml_value "analysis_folder")
PROJECT_NAME=$(get_yaml_value "PROJECT_NAME")

echo "Metadata directory: $metadata_dir"
echo "Metadata file: $metadata_file"
echo "Sample loading table directory: $sample_loading_table_dir"
echo "Sample loading table file: $sample_loading_table_file"
echo "Genome reference path: $genome_reference_path"
echo "Analysis folder: $analysis_folder"
echo "Project name: $PROJECT_NAME"

# Define full paths
metadata_file="${metadata_dir}/${metadata_file}"
sample_loading_table_file="${sample_loading_table_dir}/${sample_loading_table_file}"

echo "Full metadata file path: $metadata_file"
echo "Full sample loading table file path: $sample_loading_table_file"

########################################################################
# Validate required inputs
########################################################################

[[ -f "$metadata_file" ]] || {
  echo "ERROR: metadata file not found: $metadata_file" >&2
  exit 1
}

[[ -f "$sample_loading_table_file" ]] || {
  echo "ERROR: sample loading table file not found: $sample_loading_table_file" >&2
  exit 1
}

[[ -d "$genome_reference_path" ]] || {
  echo "WARNING: genome_reference_path does not appear to be a directory: $genome_reference_path" >&2
}

########################################################################
# Create output and log directories
########################################################################

mkdir -p results/"$analysis_folder"/01_logs
mkdir -p results/"$analysis_folder"/02_split_pipe

########################################################################
# Parse metadata header and determine column indices
########################################################################

header=$(head -n 1 "$metadata_file")
IFS=$'\t' read -r -a cols <<< "$header"

id_col=""
sample_col=""
fastq_col=""
kit_col=""
chemistry_col=""

for i in "${!cols[@]}"; do
  case "${cols[$i]}" in
    ID)         id_col=$i ;;
    SAMPLE)     sample_col=$i ;;
    FASTQ)      fastq_col=$i ;;
    kit)        kit_col=$i ;;
    chemistry)  chemistry_col=$i ;;
  esac
done

# Validate required columns
[[ -n "$id_col" ]] || { echo "ERROR: column 'ID' not found in metadata file" >&2; exit 1; }
[[ -n "$sample_col" ]] || { echo "ERROR: column 'SAMPLE' not found in metadata file" >&2; exit 1; }
[[ -n "$fastq_col" ]] || { echo "ERROR: column 'FASTQ' not found in metadata file" >&2; exit 1; }
[[ -n "$kit_col" ]] || { echo "ERROR: column 'kit' not found in metadata file" >&2; exit 1; }
[[ -n "$chemistry_col" ]] || { echo "ERROR: column 'chemistry' not found in metadata file" >&2; exit 1; }

echo "Column indices (0-based):"
echo "  ID=$id_col"
echo "  SAMPLE=$sample_col"
echo "  FASTQ=$fastq_col"
echo "  kit=$kit_col"
echo "  chemistry=$chemistry_col"

########################################################################
# Initialize metadata-ordered sublibrary list for downstream combine
########################################################################

sublib_list="results/"$analysis_folder"/sublib_list.txt"
job_ids_file="results/${analysis_folder}/01_logs/alignment_job_ids.txt"
deps_file="results/${analysis_folder}/01_logs/alignment_dependencies.txt"
> "$sublib_list"
> "$job_ids_file"

extract_job_id() {
  awk '{print $2}' | sed 's/[<>]//g'
}

########################################################################
# Resource settings (override in project_parameters.Config.yaml)
########################################################################

THREADS=$(get_yaml_value_or_default "parseq_alignment_threads" "8")
MEM_PER_CORE_GB=$(get_yaml_value_or_default "parseq_alignment_mem_per_core_gb" "6")

if [[ ! "$THREADS" =~ ^[0-9]+$ ]] || (( THREADS < 1 )); then
  echo "ERROR: parseq_alignment_threads must be a positive integer (got: ${THREADS})" >&2
  exit 1
fi

if [[ ! "$MEM_PER_CORE_GB" =~ ^[0-9]+$ ]] || (( MEM_PER_CORE_GB < 1 )); then
  echo "ERROR: parseq_alignment_mem_per_core_gb must be a positive integer (got: ${MEM_PER_CORE_GB})" >&2
  exit 1
fi

TOTAL_MEM_MB=$((THREADS * MEM_PER_CORE_GB * 1024))

echo "Alignment resources per sublibrary: ${THREADS} threads, ${MEM_PER_CORE_GB} GB/core (${TOTAL_MEM_MB} MB total)"

########################################################################
# LSF email notifications (uses CONTACT_EMAIL from project_parameters.Config.yaml)
########################################################################

CONTACT_EMAIL=$(get_yaml_value "CONTACT_EMAIL")
PARSEQ_NOTIFY_ON_COMPLETE=$(get_yaml_value_or_default "parseq_notify_on_complete" "1")
PARSEQ_NOTIFY_ON_START=$(get_yaml_value_or_default "parseq_notify_on_start" "0")
PARSEQ_NOTIFY_ALIGNMENT_JOBS=$(get_yaml_value_or_default "parseq_notify_alignment_jobs" "0")

NOTIFY_ARGS=()
if [[ "$PARSEQ_NOTIFY_ON_COMPLETE" == "1" && -n "$CONTACT_EMAIL" && "$PARSEQ_NOTIFY_ALIGNMENT_JOBS" == "1" ]]; then
  NOTIFY_ARGS=(-N -u "$CONTACT_EMAIL")
  [[ "$PARSEQ_NOTIFY_ON_START" == "1" ]] && NOTIFY_ARGS=(-B "${NOTIFY_ARGS[@]}")
  echo "LSF email notifications enabled for alignment jobs: ${CONTACT_EMAIL}"
elif [[ "$PARSEQ_NOTIFY_ON_COMPLETE" == "1" && -z "$CONTACT_EMAIL" ]]; then
  echo "WARNING: parseq_notify_on_complete is enabled but CONTACT_EMAIL is not set" >&2
fi

########################################################################
# Submit one split-pipe job per metadata row
########################################################################

while IFS=$'\t' read -r -a row; do
  ID="${row[$id_col]}"
  SAMPLE="${row[$sample_col]}"
  FASTQ_FIELD="${row[$fastq_col]}"
  KIT="${row[$kit_col]}"
  CHEMISTRY="${row[$chemistry_col]}"

  # Preserve metadata order for downstream combine
  echo "$SAMPLE" >> "$sublib_list"

  echo "--------------------------------------------------"
  echo "Processing:"
  echo "  ID=$ID"
  echo "  SAMPLE=$SAMPLE"
  echo "  FASTQ=$FASTQ_FIELD"
  echo "  KIT=$KIT"
  echo "  CHEMISTRY=$CHEMISTRY"

  # Prepare output/log dirs for this sublibrary
  mkdir -p "results/"$analysis_folder"/01_logs/${ID}"
  mkdir -p "results/"$analysis_folder"/02_split_pipe/${ID}"

  # Split FASTQ field on commas
  # Each item may be:
  # - a directory containing FASTQs
  # - an explicit FASTQ file
  IFS=',' read -r -a fastq_items_raw <<< "$FASTQ_FIELD"

  fastq_items=()
  for item in "${fastq_items_raw[@]}"; do
    item=$(trim_whitespace "$item")
    [[ -z "$item" ]] && continue
    fastq_items+=("$item")
  done

  if [[ ${#fastq_items[@]} -eq 0 ]]; then
    echo "WARNING: no FASTQ entries found for $ID" >&2
    continue
  fi

  r1_files=()
  r2_files=()

  for item in "${fastq_items[@]}"; do
    if [[ -d "$item" ]]; then
      # Item is a directory: collect FASTQs inside it
      while IFS= read -r f; do
        [[ -n "$f" ]] && r1_files+=("$f")
      done < <(find "$item" -type f | grep '_R1_' | sort)

      while IFS= read -r f; do
        [[ -n "$f" ]] && r2_files+=("$f")
      done < <(find "$item" -type f | grep '_R2_' | sort)

    elif [[ -f "$item" ]]; then
      # Item is an explicit FASTQ file
      base=$(basename "$item")
      if [[ "$base" == *"_R1_"* ]]; then
        r1_files+=("$item")
      elif [[ "$base" == *"_R2_"* ]]; then
        r2_files+=("$item")
      else
        echo "WARNING: FASTQ file does not look like R1 or R2, skipping: $item" >&2
      fi

    else
      echo "WARNING: FASTQ entry not found for $ID: $item" >&2
    fi
  done

  if [[ ${#r1_files[@]} -eq 0 ]]; then
    echo "WARNING: no R1 FASTQ files found for $ID" >&2
    continue
  fi

  if [[ ${#r2_files[@]} -eq 0 ]]; then
    echo "WARNING: no R2 FASTQ files found for $ID" >&2
    continue
  fi

  if [[ ${#r1_files[@]} -ne ${#r2_files[@]} ]]; then
    echo "ERROR: unequal number of R1 and R2 files for $ID" >&2
    echo "  R1 files: ${#r1_files[@]}" >&2
    echo "  R2 files: ${#r2_files[@]}" >&2
    continue
  fi

  # Sort explicitly for reproducibility
  mapfile -t r1_files < <(printf "%s\n" "${r1_files[@]}" | sort)
  mapfile -t r2_files < <(printf "%s\n" "${r2_files[@]}" | sort)

  echo "  R1 files found: ${#r1_files[@]}"
  echo "  R2 files found: ${#r2_files[@]}"

  # Write explicit FASTQ list files to avoid long command lines
  fq1_list="results/"$analysis_folder"/01_logs/${ID}/fq1_list.txt"
  fq2_list="results/"$analysis_folder"/01_logs/${ID}/fq2_list.txt"

  printf "%s\n" "${r1_files[@]}" > "$fq1_list"
  printf "%s\n" "${r2_files[@]}" > "$fq2_list"

  echo "  FQ1 list: $fq1_list"
  echo "  FQ2 list: $fq2_list"

  # Optional per-sublibrary manifest
  {
    echo "ID=${ID}"
    echo "SAMPLE=${SAMPLE}"
    echo "KIT=${KIT}"
    echo "CHEMISTRY=${CHEMISTRY}"
    echo "FASTQ_INPUT=${FASTQ_FIELD}"
    echo "R1_COUNT=${#r1_files[@]}"
    echo "R2_COUNT=${#r2_files[@]}"
  } > "results/"$analysis_folder"/01_logs/${ID}/submission_manifest.txt"

  ######################################################################
  # Submit split-pipe alignment
  #
  # NOTE:
  # This assumes split-pipe accepts list-file references in the form:
  #   --fq1 @file
  #   --fq2 @file
  #
  # If your local build expects a different list-file syntax, adjust only
  # the two lines below that define --fq1 and --fq2.
  ######################################################################

  bsub_out=$(bsub \
    "${NOTIFY_ARGS[@]}" \
    -P "$PROJECT_NAME" \
    -J "splitpipe_Run_${ID}" \
    -q standard \
    -n "$THREADS" \
    -R "span[hosts=1] rusage[mem=${MEM_PER_CORE_GB}GB]" \
    -M "$TOTAL_MEM_MB" \
    -oo "results/"$analysis_folder"/01_logs/${ID}/splitpipe.%J.out" \
    -eo "results/"$analysis_folder"/01_logs/${ID}/splitpipe.%J.err" \
    split-pipe \
      --mode all \
      --nthreads "$THREADS" \
      --chemistry "$CHEMISTRY" \
      --kit "$KIT" \
      --genome_dir "$genome_reference_path" \
      --fq1 "${r1_files[@]}" \
      --fq2 "${r2_files[@]}" \
      --output_dir "$(realpath "results/"$analysis_folder"/02_split_pipe/${ID}")" \
      --samp_sltab "$sample_loading_table_file" \
    2>&1) || {
    echo "ERROR: bsub failed for ${ID}: ${bsub_out}" >&2
    exit 1
  }

  job_id=$(echo "$bsub_out" | extract_job_id)
  if [[ -z "$job_id" || ! "$job_id" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not parse job ID for ${ID}. bsub output: ${bsub_out}" >&2
    exit 1
  fi

  echo "$job_id" >> "$job_ids_file"
  echo "  Submitted split-pipe job ${job_id} for ${ID}"

done < <(tail -n +2 "$metadata_file")

########################################################################
# Build LSF dependency expression for the combine step
########################################################################

if [[ -s "$job_ids_file" ]]; then
  deps=""
  while IFS= read -r jid; do
    [[ -z "$jid" ]] && continue
    if [[ -z "$deps" ]]; then
      deps="done(${jid})"
    else
      deps="${deps} && done(${jid})"
    fi
  done < "$job_ids_file"

  echo "$deps" > "$deps_file"
  echo "Alignment jobs submitted. Combine dependency: ${deps}"
else
  > "$deps_file"
  echo "WARNING: No alignment jobs were submitted." >&2
fi

########################################################################

