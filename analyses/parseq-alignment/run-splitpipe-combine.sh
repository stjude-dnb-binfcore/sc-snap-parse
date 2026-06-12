#!/bin/bash

set -e
set -o pipefail

########################################################################
# Standalone combine launcher
#
# Use when per-sublibrary alignments (Step 1) are already complete and you
# only need to run split-pipe --mode combine — for example after editing
# sublib_list.txt or rerunning combine without resubmitting alignments.
#
# Does not set LSF alignment dependencies; submits the combine job immediately.
########################################################################

cd "$(dirname "${BASH_SOURCE[0]}")"

unset LSF_DEPENDENCY
bash 02-splitpipe-combine.sh
