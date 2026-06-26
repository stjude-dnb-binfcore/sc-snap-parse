#!/bin/bash

set -e
set -o pipefail

# set up running directory
cd "$(dirname "${BASH_SOURCE[0]}")"

rootdir=$(realpath "./../..")
config_file="${rootdir}/project_parameters.Config.yaml"

########################################################################
# Load helper functions
script_dir="$(dirname "${BASH_SOURCE[0]}")"
source "${script_dir}/util/parse_utils.sh"

analysis_folder=$(get_yaml_value "analysis_folder")
deps_file="results/${analysis_folder}/01_logs/alignment_dependencies.txt"

################################################################################################################
# Step 1: submit one split-pipe alignment job per metadata row
################################################################################################################
bash 01-splitpipe-alignment.sh

################################################################################################################
# Step 2: submit combine only after all Step 1 jobs complete successfully
################################################################################################################
if [[ ! -s "$deps_file" ]]; then
  echo "No alignment jobs were submitted; skipping combine step."
  exit 0
fi

export LSF_DEPENDENCY
LSF_DEPENDENCY="$(cat "$deps_file")"
echo "Submitting combine step with dependency: ${LSF_DEPENDENCY}"

bash 02-splitpipe-combine.sh
