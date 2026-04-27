#!/bin/bash
###############################################################################
# Script:        launch_full_pipeline.sh
# Purpose:       Launch the full sc-snap-parse pipeline on LSF as a dependency-
#                aware job chain, with fully OPTIONAL steps and adaptive waits.
#
# Summary:
#   - Submits the end-to-end sc-snap-parse workflow (A→J) to LSF.
#   - Every step can be toggled on/off independently.
#   - Dependencies automatically wire up only between ENABLED steps.
#   - Parse-seq-aligner runs in parallel with FastQC.
#   - Email notifications are sent on job start, completion, and/or failure.
#   - Note: The Parse-seq-aligner step sends an email notification on job start but not on completion.
#           Successful submission of the upstream-analysis step indicates that the
#           Parse-seq-aligner alignments completed successfully.
# Key Features:
#   • Full workflow coverage with modular, optional steps:
#       A: FastQC
#       B: Parse-seq-aligner
#       C: Upstream analysis
#       D: Integrative analysis
#       E: Cluster cell calling
#       F: Remove contamination
#       G: Cell types annotation
#       H: Clone Phylogeny Analysis
#       I: DE GO analysis
#       J: R/Shiny app packaging
#   • Optional per-step execution via RUN_* flags.
#   • Adaptive dependencies: each enabled step depends on the last enabled predecessor.
#   • LSF email notifications with a single NOTIFY_EMAIL value for all jobs.
#
# Usage:
#   1) Edit the configuration section near the top:
#        - NOTIFY_EMAIL="user.name@stjude.org"
#        - NOTIFY_ON_START=0|1
#        - RUN_FASTQC / RUN_Parseseqaligner / ... / RUN_RSHINY = 0|1
#   2) Ensure each module directory has its LSF script:
#        analyses/<module>/lsf-script.txt
#        (Parse-seq-aligner may use submit-multiple-jobs.sh to fan out internal jobs.)
#   3) Run from anywhere:
#        bash launch_full_pipeline.sh
#
# Notifications:
#   - Completion emails: enabled by default via `-N -u "$NOTIFY_EMAIL"`.
#   - Start emails: set NOTIFY_ON_START=1 to add `-B` to all bsubs.
#   - Cluster defaults like LSB_MAILTO may be honored but are overridden by -u.
#
# Dependencies Semantics:
#   - The chain uses `done(<JOBID>)` so downstream steps start only if upstream
#     succeeded. If you want downstream steps to run regardless of status,
#     switch to `ended(<JOBID>)` where appropriate.
#   - If you need a step to wait on multiple predecessors, combine expressions:
#       -w "done(<JOB_A>) && done(<JOB_B>)"
#
# Logs:
#   - Each step writes to <module>/job.out and <module>/job.err.
#   - LSF submission output is parsed to capture Job IDs for a final summary.
#
# Requirements:
#   - LSF (bsub) available on PATH.
#   - Module directories exist with their respective LSF scripts.
#
# Maintainer:    Antonia Chroni (DNB Bioinformatics, St. Jude Children's Research Hospital)
# Last updated:  2026-02-19
###############################################################################

set -e
set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(pwd)"

# ------------------------------------------------------------------------------
# Notifications
# ------------------------------------------------------------------------------
# All jobs will notify on completion (-N) to this email.
# Set NOTIFY_ON_START=1 to also get a mail when a job starts (-B).
NOTIFY_EMAIL="user.name@stjude.org"
NOTIFY_ON_START=1   # 1 = include -B (mail on start); 0 = Skip start notifications

# Compose common bsub notification flags
BSUB_NOTIFY_FLAGS=(-N -u "${NOTIFY_EMAIL}")
if [[ "${NOTIFY_ON_START}" -eq 1 ]]; then
  BSUB_NOTIFY_FLAGS=(-B "${BSUB_NOTIFY_FLAGS[@]}")
fi

# ------------------------------------------------------------------------------
# Feature toggles — make EVERY step optional
# 1 = run step; 0 = skip step
# ------------------------------------------------------------------------------
RUN_FASTQC=1                # A: FastQC: `fastqc-analysis`
RUN_Parseseqaligner=1       # B: Parse-seq-aligner: `split-pipe-analysis`
RUN_UPSTREAM=1              # C: Upstream: `upstream-analysis`
RUN_INTEGRATIVE=1           # D: Integrative: `integrative-analysis`
RUN_CLUSTER=1               # E: Cluster cell calling: `cluster-cell-calling`
RUN_CELL_CONTAMINATION=0    # F: Remove contamination: `cell-contamination-removal-analysis`
RUN_CELL_TYPES=1            # G: Integration with scRNA-seq: `cell-types-annotation`
RUN_CLONE_PHYLOGENY=0       # H: Clone Phylogeny Analysis: `clone-phylogeny-analysis`
RUN_DE_GO=1                 # I: DE GO analysis: `de-go-analysis`
RUN_RSHINY=1                # J: R/Shiny app: `rshiny-app`

# ------------------------------------------------------------------------------
# Heading
# ------------------------------------------------------------------------------
echo "============================================================"
echo " Launching sc-snap-parse pipeline (LSF job chain) — optional steps"
echo " Working directory: ${PROJECT_DIR}"
echo "============================================================"

# ------------------------------------------------------------------------------
# Helper: extract LSF job ID from 'Job <12345> is submitted ...'
# ------------------------------------------------------------------------------
extract_job_id() { awk '{print $2}' | sed 's/[<>]//g'; }

# ------------------------------------------------------------------------------
# Helper: bsub wrapper to reduce repetition
#   args:
#     1 = workdir
#     2 = stdin script path
#     3 = dependency expression (may be empty)
#     4 = label for logs
#   echoes job id
# ------------------------------------------------------------------------------
submit_job() {
  local _cwd="$1"
  local _in="$2"
  local _dep="${3:-}"
  local _label="${4:-job}"

  mkdir -p "${_cwd}"
  local out
  if ! out=$(bsub -cwd "${_cwd}" \
                  ${_dep:+-w "${_dep}"} \
                  "${BSUB_NOTIFY_FLAGS[@]}" \
                  < "${_in}" 2>&1); then
    echo "ERROR: bsub failed for ${_label} in ${_cwd}" >&2
    echo "${out}" >&2
    exit 1
  fi
  local jid
  jid="$(echo "${out}" | extract_job_id)"
  if [[ -z "${jid}" ]]; then
    echo "ERROR: Could not parse job ID for ${_label}. bsub output:" >&2
    echo "${out}" >&2
    exit 1
  fi
  echo "${jid}"
}

# ------------------------------------------------------------------------------
# Helper: bsub wrapper for Parse-seq-aligner's submit-multiple-jobs.sh, which may print multiple lines of output.

# submit_job WORKDIR LAUNCHER_SCRIPT UPSTREAM_DEP JOBNAME
# Example:
#   JOB_B=$(submit_job "${B_DIR}" "${B_DIR}/submit-multiple-jobs.sh" "${B_DEP}" "Parse-seq-aligner")
#
# Contract:
#   - LAUNCHER_SCRIPT runs LOCALLY (not as an LSF job).
#   - It is responsible for submitting all internal LSF jobs and their own waiter.
#   - It must print ONLY the final waiter job ID (numeric) to stdout.
submit_job_split_pipe() {
  local workdir="$1"           # e.g., ${B_DIR}
  local launcher="$2"          # e.g., ${B_DIR}/submit-multiple-jobs.sh
  local upstream_dep="$3"      # e.g., "done(${JOB_A})" or ""
  local jobname="$4"           # logical prefix, e.g., "Parse-seq-aligner"

  (
    set -euo pipefail
    cd "$workdir"

    # Run launcher LOCALLY. Capture ALL output.
    local raw
    raw="$("${launcher}" "${upstream_dep}" "${jobname}" 2>&1)"

    # Extract the LAST numeric token from output (the waiter job ID)
    local waiter_id
    waiter_id="$(echo "${raw}" | grep -Eo 'Job <[0-9]+>' | grep -Eo '[0-9]+' | tail -n 1)"

    # Validate
    if [[ -z "${waiter_id}" || ! "${waiter_id}" =~ ^[0-9]+$ ]]; then
      echo "ERROR: ${launcher} did not emit a numeric job ID." >&2
      echo "       Raw launcher output was:" >&2
      echo "-----------------------------------------------" >&2
      echo "${raw}" >&2
      echo "-----------------------------------------------" >&2
      exit 1
    fi

    # Return ONLY the numeric waiter job ID
    echo "${waiter_id}"
  )
}

# ------------------------------------------------------------------------------
# Module directories
# ------------------------------------------------------------------------------
A_DIR="${PROJECT_DIR}/analyses/fastqc-analysis"
B_DIR="${PROJECT_DIR}/analyses/split-pipe-analysis"
C_DIR="${PROJECT_DIR}/analyses/upstream-analysis"
D_DIR="${PROJECT_DIR}/analyses/integrative-analysis"
E_DIR="${PROJECT_DIR}/analyses/cluster-cell-calling"
F_DIR="${PROJECT_DIR}/analyses/cell-contamination-removal-analysis"
G_DIR="${PROJECT_DIR}/analyses/cell-types-annotation"
H_DIR="${PROJECT_DIR}/analyses/clone-phylogeny-analysis"
I_DIR="${PROJECT_DIR}/analyses/de-go-analysis"
J_DIR="${PROJECT_DIR}/analyses/rshiny-app"

# ------------------------------------------------------------------------------
# Dynamic progress counter (counts only enabled steps)
# ------------------------------------------------------------------------------
count_enabled() {
  local n=0
  (( RUN_FASTQC ))           && ((n++))
  (( RUN_Parseseqaligner ))       && ((n++))
  (( RUN_UPSTREAM ))         && ((n++))
  (( RUN_INTEGRATIVE ))      && ((n++))
  (( RUN_CLUSTER ))          && ((n++))
  (( RUN_CELL_CONTAMINATION ))     && ((n++))
  (( RUN_CELL_TYPES ))  && ((n++))
  (( RUN_CLONE_PHYLOGENY ))            && ((n++))
  (( RUN_DE_GO ))            && ((n++))
  (( RUN_RSHINY ))           && ((n++))
  echo "${n}"
}
TOTAL_STEPS="$(count_enabled)"
STEP=0

bump_step() { STEP=$((STEP+1)); }

# ------------------------------------------------------------------------------
# Submission chain
# ------------------------------------------------------------------------------
LAST_JOB=""
JOB_A=""; JOB_B=""; JOB_C=""; JOB_D=""; JOB_E=""; JOB_F=""; JOB_G=""; JOB_H=""; JOB_I=""; JOB_J=""

# A) FastQC
if (( RUN_FASTQC )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting FastQC (A)..."
  JOB_A=$(submit_job "${A_DIR}" "${A_DIR}/lsf-script.txt" "" "FastQC")
  echo "  A(FastQC) = ${JOB_A}"
else
  echo "[–/–] FastQC (A): SKIPPED"
fi


# B) Parse-seq-aligner 
if (( RUN_Parseseqaligner )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Parse-seq-aligner (B)..."
  B_DEP=""

  # submit-multiple-jobs.sh 
  JOB_B=$(submit_job_split_pipe "${B_DIR}" "${B_DIR}/submit-multiple-jobs.sh" "${B_DEP}" "Parse-seq-aligner")
  # Email me when the Parse-seq-aligner job (JOB_B) is submitted.
  echo "  B(Parse-seq-aligner) = ${JOB_B} ${B_DEP:+(dep: ${B_DEP})}" | mail -s "Parse-seq-aligner submitted" "${NOTIFY_EMAIL}"
else
  echo "[–/–] Parse-seq-aligner (B): SKIPPED"
fi


# Maintain a simple linear chain among *enabled* steps after B:
# The next step depends on the most recent ENABLED job. If B ran, chain from B; else if A ran, chain from A; else no dep.
if   (( RUN_Parseseqaligner )); then LAST_JOB="${JOB_B}"
elif (( RUN_FASTQC    )); then LAST_JOB="${JOB_A}"
else                            LAST_JOB=""
fi

# C) Upstream
if (( RUN_UPSTREAM )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Upstream (C)..."
  C_DEP=""
  [[ -n "${LAST_JOB}" ]] && C_DEP="done(${LAST_JOB})"
  JOB_C=$(submit_job "${C_DIR}" "${C_DIR}/lsf-script.txt" "${C_DEP}" "Upstream")
  echo "  C(Upstream) = ${JOB_C} ${C_DEP:+(dep: ${C_DEP})}"
  LAST_JOB="${JOB_C}"
else
  echo "[–/–] Upstream (C): SKIPPED"
fi

# D) Integrative
if (( RUN_INTEGRATIVE )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Integrative (D)..."
  D_DEP=""
  [[ -n "${LAST_JOB}" ]] && D_DEP="done(${LAST_JOB})"
  JOB_D=$(submit_job "${D_DIR}" "${D_DIR}/lsf-script.txt" "${D_DEP}" "Integrative")
  echo "  D(Integrative) = ${JOB_D} ${D_DEP:+(dep: ${D_DEP})}"
  LAST_JOB="${JOB_D}"
else
  echo "[–/–] Integrative (D): SKIPPED"
fi

# E) Cluster cell calling
if (( RUN_CLUSTER )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Cluster cell calling (E)..."
  E_DEP=""
  [[ -n "${LAST_JOB}" ]] && E_DEP="done(${LAST_JOB})"
  JOB_E=$(submit_job "${E_DIR}" "${E_DIR}/lsf-script.txt" "${E_DEP}" "Cluster cell calling")
  echo "  E(Cluster) = ${JOB_E} ${E_DEP:+(dep: ${E_DEP})}"
  LAST_JOB="${JOB_E}"
else
  echo "[–/–] Cluster cell calling (E): SKIPPED"
fi

# F) Cell contamination removal analysis
if (( RUN_CELL_CONTAMINATION )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Cell contamination removal analysis (F)..."
  F_DEP=""
  [[ -n "${LAST_JOB}" ]] && F_DEP="done(${LAST_JOB})"
  JOB_F=$(submit_job "${F_DIR}" "${F_DIR}/lsf-script.txt" "${F_DEP}" "cell-contamination-removal-analysis")
  echo "  F(Cell Contamination) = ${JOB_F} ${F_DEP:+(dep: ${F_DEP})}"
  LAST_JOB="${JOB_F}"
else
  echo "[–/–] Cell contamination removal analysis (F): SKIPPED"
fi

# G) Cell types annotation 
if (( RUN_CELL_TYPES )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Cell types annotation (G)..."
  G_DEP=""
  [[ -n "${LAST_JOB}" ]] && G_DEP="done(${LAST_JOB})"
  JOB_G=$(submit_job "${G_DIR}" "${G_DIR}/lsf-script.txt" "${G_DEP}" "cell-types-annotation")
  echo "  G(Cell types annotation) = ${JOB_G} ${G_DEP:+(dep: ${G_DEP})}"
  LAST_JOB="${JOB_G}"
else
  echo "[–/–] Cell types annotation (G): SKIPPED"
fi

# H) Clone Phylogeny Analysis
if (( RUN_CLONE_PHYLOGENY )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting Clone Phylogeny Analysis (H)..."
  H_DEP=""
  [[ -n "${LAST_JOB}" ]] && H_DEP="done(${LAST_JOB})"
  JOB_H=$(submit_job "${H_DIR}" "${H_DIR}/lsf-script.txt" "${H_DEP}" "Clone Phylogeny Analysis")
  echo "  H(Clone Phylogeny) = ${JOB_H} ${H_DEP:+(dep: ${H_DEP})}"
  LAST_JOB="${JOB_H}"
else
  echo "[–/–] Clone Phylogeny Analysis (H): SKIPPED"
fi

# I) DE GO analysis
if (( RUN_DE_GO )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting DE GO analysis (I)..."
  I_DEP=""
  [[ -n "${LAST_JOB}" ]] && I_DEP="done(${LAST_JOB})"
  JOB_I=$(submit_job "${I_DIR}" "${I_DIR}/lsf-script.txt" "${I_DEP}" "DE GO analysis")
  echo "  I(DE GO) = ${JOB_I} ${I_DEP:+(dep: ${I_DEP})}"
  LAST_JOB="${JOB_I}"
else
  echo "[–/–] DE GO analysis (I): SKIPPED"
fi

# J) R/Shiny app
if (( RUN_RSHINY )); then
  bump_step
  echo "[${STEP}/${TOTAL_STEPS}] Submitting R/Shiny app (J)..."
  J_DEP=""
  [[ -n "${LAST_JOB}" ]] && J_DEP="done(${LAST_JOB})"
  JOB_J=$(submit_job "${J_DIR}" "${J_DIR}/lsf-script.txt" "${J_DEP}" "R/Shiny app")
  echo "  J(R/Shiny) = ${JOB_J} ${J_DEP:+(dep: ${J_DEP})}"
  LAST_JOB="${JOB_J}"
else
  echo "[–/–] R/Shiny app (J): SKIPPED"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo "============================================================"
if (( TOTAL_STEPS == 0 )); then
  echo " No steps were enabled — nothing submitted."
else
  echo " All enabled steps submitted."
fi
printf "  A(FastQC)   : %s\n"   "${RUN_FASTQC:+${JOB_A:-SKIPPED}}"
printf "  B(Parse-seq-aligner): %s\n"   "${RUN_Parseseqaligner:+${JOB_B:-SKIPPED}}"
printf "  C(Upstream) : %s\n"    "${RUN_UPSTREAM:+${JOB_C:-SKIPPED}}"
printf "  D(Integrative): %s\n"  "${RUN_INTEGRATIVE:+${JOB_D:-SKIPPED}}"
printf "  E(Cluster)  : %s\n"    "${RUN_CLUSTER:+${JOB_E:-SKIPPED}}"
printf "  F(Cell contamination): %s\n" "${RUN_CELL_CONTAMINATION:+${JOB_F:-SKIPPED}}"
printf "  G(Cell types annotation)  : %s\n"    "${RUN_CELL_TYPES:+${JOB_G:-SKIPPED}}"
printf "  H(Clone Phylogeny)    : %s\n"    "${RUN_CLONE_PHYLOGENY:+${JOB_H:-SKIPPED}}"
printf "  I(DE GO)    : %s\n"    "${RUN_DE_GO:+${JOB_I:-SKIPPED}}"
printf "  J(R/Shiny)  : %s\n"    "${RUN_RSHINY:+${JOB_J:-SKIPPED}}"
echo " Final job in chain: ${LAST_JOB:-NONE}"
echo "============================================================"
