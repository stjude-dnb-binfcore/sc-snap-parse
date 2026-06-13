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
# Helper function
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
# Determine sublibrary list
########################################################################

sublib_list="${base_dir}/sublib_list.txt"

if [[ -f "$sublib_list" ]]; then
  echo "Using metadata-defined sublibrary list: $sublib_list"
else
  echo "WARNING: sublib_list.txt not found — generating from directory listing"

  ls "$splitpipe_dir" > "$sublib_list"
fi

echo "Sublibraries:"
cat "$sublib_list"

########################################################################
# Submit combine job
########################################################################

dep_args=()
if [[ -n "${LSF_DEPENDENCY:-}" ]]; then
  dep_args=(-w "$LSF_DEPENDENCY")
  echo "Combine job will wait for: ${LSF_DEPENDENCY}"
fi

bsub_out=$(bsub \
  "${NOTIFY_ARGS[@]}" \
  "${dep_args[@]}" \
  -J "parseq_combine" \
  -q standard \
  -n 6 \
  -R "span[hosts=1] rusage[mem=6GB]" \
  -M 36864 \
  -oo "${log_dir}/parse_combine.%J.out" \
  -eo "${log_dir}/parse_combine.%J.err" \
  split-pipe \
    --mode combine \
    --sublib_list "$sublib_list" \
    --output_dir "$(realpath "$combined_dir")" \
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
# End
########################################################################