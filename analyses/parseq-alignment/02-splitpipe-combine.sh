#!/bin/bash

set -euo pipefail

########################################################################
# Parse split-pipe combine script (Step 2)
#
# Submits split-pipe --mode combine for existing per-sublibrary outputs.
# Called by:
#   - run-parseq-alignment.sh (with LSF_DEPENDENCY set)
#   - run-splitpipe-combine.sh (standalone combine, no alignment wait)
#
# Requires:
#   - YAML config
#   - results/<analysis_folder>/02_split_pipe/ alignments
#   - results/<analysis_folder>/sublib_list.txt (or auto-generated from dirs)
########################################################################

# Load modules
module load ParseBiosciences/1.6.0

# Set working directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Root + config
rootdir=$(realpath "./../..")
config_file="${rootdir}/project_parameters.Config.yaml"

########################################################################
# Load helper functions
script_dir="$(dirname "${BASH_SOURCE[0]}")"
source "${script_dir}/util/parse_utils.sh"

########################################################################
# Read config
########################################################################
analysis_folder=$(get_yaml_value "analysis_folder")
CONTACT_EMAIL=$(get_yaml_value "CONTACT_EMAIL")
PARSEQ_NOTIFY_ON_COMPLETE=$(get_yaml_value_or_default "parseq_notify_on_complete" "1")
PARSEQ_NOTIFY_ON_START=$(get_yaml_value_or_default "parseq_notify_on_start" "0")

NOTIFY_ARGS=()
if [[ "$PARSEQ_NOTIFY_ON_COMPLETE" == "1" && -n "$CONTACT_EMAIL" ]]; then
  NOTIFY_ARGS=(-N -u "$CONTACT_EMAIL")
  [[ "$PARSEQ_NOTIFY_ON_START" == "1" ]] && NOTIFY_ARGS=(-B "${NOTIFY_ARGS[@]}")
  echo "LSF email notifications enabled for combine job: ${CONTACT_EMAIL}"
elif [[ "$PARSEQ_NOTIFY_ON_COMPLETE" == "1" && -z "$CONTACT_EMAIL" ]]; then
  echo "WARNING: parseq_notify_on_complete is enabled but CONTACT_EMAIL is not set" >&2
fi

echo "Analysis folder: $analysis_folder"

# Define paths
base_dir="results/${analysis_folder}"
splitpipe_dir="${base_dir}/02_split_pipe"
combined_dir="${base_dir}/03_combined"
log_dir="${base_dir}/01_logs/combined"

mkdir -p "$combined_dir"
mkdir -p "$log_dir"

########################################################################
# Combine step resource defaults (I/O-bound; do not over-allocate)
########################################################################
DEFAULT_COMBINE_THREADS=4
DEFAULT_COMBINE_MEM_GB=24

PARSEQ_COMBINE_THREADS=$(get_yaml_value_or_default "parseq_combine_threads" "$DEFAULT_COMBINE_THREADS")
PARSEQ_COMBINE_MEM_GB=$(get_yaml_value_or_default "parseq_combine_mem_gb" "$DEFAULT_COMBINE_MEM_GB")

echo "Combine resources:"
echo "  Threads: ${PARSEQ_COMBINE_THREADS}"
echo "  Memory (GB): ${PARSEQ_COMBINE_MEM_GB}"

# Convert to MB for LSF
PARSEQ_COMBINE_MEM_MB=$((PARSEQ_COMBINE_MEM_GB * 1024))

# Memory per core (for rusage)
PARSEQ_COMBINE_MEM_PER_CORE_MB=$((PARSEQ_COMBINE_MEM_MB / PARSEQ_COMBINE_THREADS))

########################################################################
# Determine sublibrary list
########################################################################

sublib_list="${base_dir}/sublib_list.txt"

if [[ -f "$sublib_list" ]]; then
  echo "Using metadata-defined sublibrary list: $sublib_list"
else
  echo "WARNING: sublib_list.txt not found — generating from directory listing"
  ls -1 "$splitpipe_dir" | xargs -I{} basename "{}" > "$sublib_list"
  cat "$sublib_list"
fi

echo "Sublibraries:"
cat "$sublib_list"

########################################################################
# Determine sublibrary list filepaths
sublib_list_filepaths="${base_dir}/sublib_list_filepaths.txt"

if [[ -f "$sublib_list_filepaths" ]]; then
  echo "Using metadata-defined sublibrary list: $sublib_list_filepaths"
else
  echo "WARNING: sublib_list_filepaths.txt not found — generating from directory listing"
  ls -d "$splitpipe_dir"/* > "$sublib_list_filepaths"
  cat "$sublib_list_filepaths"
fi

echo "Sublibraries filepaths:"
cat "$sublib_list_filepaths"


########################################################################
# Combine job
########################################################################

dep_args=()
if [[ -n "${LSF_DEPENDENCY:-}" ]]; then
  dep_args=(-w "$LSF_DEPENDENCY")
  echo "Combine job will wait for: ${LSF_DEPENDENCY}"
fi

export OMP_NUM_THREADS=${PARSEQ_COMBINE_THREADS}
export OPENBLAS_NUM_THREADS=${PARSEQ_COMBINE_THREADS}
export MKL_NUM_THREADS=${PARSEQ_COMBINE_THREADS}

# Add splitpipe_cmd
splitpipe_cmd=(
  split-pipe
  --mode combine
  --sublib_list "$sublib_list_filepaths"
  --output_dir "$(realpath "$combined_dir")"
)

########################################################################
# Handle large number of sublibraries (split-pipe limit tuning)
########################################################################

SUBLIB_COUNT=$(wc -l < "$sublib_list" | tr -d ' ')

echo "Detected sublibraries: ${SUBLIB_COUNT}"

PARFILE_ARGS=()

# Add parfile only when sublib count > 16
if (( SUBLIB_COUNT > 16 )); then
  echo "Sublibrary count > 16 — enabling comb_max_sublibs override"

  sublib_size_file="${base_dir}/sublib_size.txt"

  #echo "comb_max_sublibs 16" > "$sublib_size_file"
  echo "comb_max_sublibs ${SUBLIB_COUNT}"> "$sublib_size_file"
  
  echo "Created parfile: $sublib_size_file"
  cat "$sublib_size_file"

  echo "✅ Using --parfile flag"
  echo "Command will include: --parfile $(realpath "$sublib_size_file")"

else
  echo "Sublibrary count <= 16 — NOT using comb_max_sublibs override"
  echo "✅ Running combine WITHOUT --parfile"
fi



########################################################################
# Submit job
########################################################################

bsub_out=$(bsub \
  "${NOTIFY_ARGS[@]}" \
  "${dep_args[@]}" \
  -J "parseq_combine" \
  -q standard \
  -n "${PARSEQ_COMBINE_THREADS}" \
  -R "span[hosts=1] rusage[mem=${PARSEQ_COMBINE_MEM_PER_CORE_MB}MB]" \
  -M "${PARSEQ_COMBINE_MEM_MB}" \
  -oo "${log_dir}/parse_combine.out" \
  -eo "${log_dir}/parse_combine.err" \
  "${splitpipe_cmd[@]}" \
  2>&1) || {
  echo "ERROR: bsub failed for combine job: ${bsub_out}" >&2
  exit 1
}


combine_job_id=$(echo "$bsub_out" | awk '{print $2}' | sed 's/[<>]//g')
if [[ -z "$combine_job_id" || ! "$combine_job_id" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Could not parse combine job ID. bsub output: ${bsub_out}" >&2
  exit 1
fi

echo "Submitted combine job ${combine_job_id}"

########################################################################
