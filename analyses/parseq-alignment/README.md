# Pipeline for running and combining Parse Biosciences split-pipe alignment for multiple sublibraries

## Usage

`run-parseq-alignment.sh` is designed to be run as if it were called from this module directory, even when called from outside of this directory.

The module runs the following steps:

- **Step 1:** `01-splitpipe-alignment.sh` submits one `split-pipe --mode all` job per metadata row (sublibrary) in parallel on LSF.
- **Step 2:** `02-splitpipe-combine.sh` submits a single `split-pipe --mode combine` job to merge per-sublibrary outputs into one combined dataset.

### Which script to run

| Goal | Script | LSF launcher |
|------|--------|--------------|
| Align all sublibraries, then combine | `run-parseq-alignment.sh` | `bsub < lsf-script.txt` |
| Align only (no combine) | `01-splitpipe-alignment.sh` | — |
| Combine only (alignments already done) | `run-splitpipe-combine.sh` | `bsub < lsf-script-combine.txt` |

`run-parseq-alignment.sh` runs both steps in one launch. Step 1 records LSF job IDs from each alignment submission and Step 2 is submitted with an LSF dependency (`done(<jobid>) && ...`) so the combine job starts only after all alignment jobs finish successfully.

`run-splitpipe-combine.sh` is for reruns or combine-only workflows. It calls the same combine logic as Step 2 but does not wait on alignment jobs — use it only when all per-sublibrary outputs in `results/<analysis_folder>/02_split_pipe/` are already complete.

Parameters according to the project and analysis strategy will need to be specified in the following files:

- `../../project_parameters.Config.yaml`: define paths and project-level settings used by both steps.

- **Metadata file** (`sublibrary_metadata.tsv`): must be a tab-separated file with at least the following columns: `sublibrary_ID`, `FASTQ`, `kit`, and `chemistry`. 
- **Sample loading table** (`sample_loading_table.xlsm`): Parse Biosciences sample loading table (`.xlsm`) passed to `split-pipe` via `--samp_sltab`. 

#### Sample Loading Table

Please note that the **sample loading table** input file varies across different Parse Biosciences kits.
Ensure that the correct template corresponding to the sequencing kit is used.

- Parse provides **kit-specific template sample loading tables** 
    - For guidance on which table to choose depending on kit, please see [Evercode WT v3 User Guide](https://support.parsebiosciences.com/hc/en-us/articles/23911840786196-Evercode-WT-v3-User-Guides).
    - For access to the tables, please see [kit-specific tables](https://support.parsebiosciences.com/hc/en-us/articles/9482740811924-Evercode-v3-Sample-Loading-Tables) (requires a Parse user account).
- This table is **completed by the biologist** during sample and sublibrary preparation for sequencing.
- The sample loading table captures how samples are organized and loaded for the run.

> **Important:** The sample loading table is **not modified by the analyst**. It should be used exactly as provided after being completed by the wet lab.


### Tuning alignment speed

Each sublibrary is aligned in its own LSF job (parallel across the cohort). Within each job, speed is controlled by:

- `parseq_alignment_threads`: passed to LSF as `-n` and to `split-pipe` as `--nthreads`.
- `parseq_alignment_mem_per_core_gb`: memory requested per core from LSF. Total memory per job is `threads × mem_per_core_gb`.

Keep `parseq_alignment_threads` equal to the LSF core count so allocated CPUs are fully used. Increase threads only if jobs have enough memory and you have tested runtime on a representative sublibrary.


### Sample naming consistency

`split-pipe` uses sample names from the sample loading table when creating output folder names. If sample names differ between the `ID` column in the `sample_metadata.tsv` file and the sample loading table, downstream loading and matching can break.


Best practice:

- Keep `ID` and sample names identical across the `sample_metadata.tsv` and `sample_loading_table.xlsm` files, or
- Add a column to the `sample_metadata.tsv` file with the exact names used in the `sample_loading_table.xlsm` and use those consistently downstream.

### Handling top-ups, technical replicates, and multiple FASTQ inputs

The `FASTQ` column supports comma-separated entries. Each entry may be:

1. A directory containing `_R1_` and `_R2_` FASTQ files, or
2. An explicit FASTQ file path.

For a sublibrary with multiple sequencing runs (top-ups or technical replicates), list all corresponding directories or FASTQ paths in the same row, separated by commas with no spaces.

Example metadata format:

| sublibrary_ID | FASTQ | kit | chemistry |
|:----------|:----------|:----------|:----------|
| sublibrary_ID1 | /absolute_path/seq_submission_code1/replicate1,/absolute_path/seq_submission_code1/replicate2 | WT | v3 |

Other metadata may be included, but the following columns are required: `sublibrary_ID`, `FASTQ`, `kit`, and `chemistry`. 

The module automatically:

- Collects and sorts matching `_R1_` and `_R2_` FASTQ files for each sublibrary
- Validates that R1 and R2 file counts are equal
- Writes per-sublibrary FASTQ list files (`fq1_list.txt`, `fq2_list.txt`) and a submission manifest under `results/<analysis_folder>/01_logs/<sublibrary_ID>/`
- Records sublibrary order in `results/<analysis_folder>/sublib_list.txt` for the combine step

There is no need to manually merge FASTQs before alignment—format the metadata correctly and the pipeline handles file discovery and submission.

### Projects with more than 16 sublibraries (Mega kit / large cohorts)

Parse Biosciences workflows often require aligning sublibraries individually and then combining results. This module is designed for that pattern:

- Step 1 submits one alignment job per metadata row, so cohorts with more than 16 sublibraries are supported.
- Step 2 combines outputs listed in `sublib_list.txt` and adds the `--parfile` flag to increase the sublibrary limit above 16.

### Rerunning the combine step after removing sublibraries

If you need to exclude one or more sublibraries from the combined output:

1. Ensure the unwanted sublibrary alignments are removed or ignored.
2. Edit `results/<analysis_folder>/sublib_list.txt` so it contains only the `sublibrary_ID` names to include, in the desired order.
3. Re-run combine only:

```
bash run-splitpipe-combine.sh
```

Or submit on LSF:

```
bsub < lsf-script-combine.txt
```

## Run module on HPC

This module runs **outside the container** on St. Jude HPC. It uses the `ParseBiosciences/1.6.0` environment module for `split-pipe`.

### Submit the full module on LSF (align + combine)

From an interactive compute node, submit the lightweight launcher job that reads metadata and submits per-sublibrary `split-pipe` jobs, then combine with LSF dependencies:

```
bsub < lsf-script.txt
```

### Submit combine only on LSF

When alignments are already complete and you only need to combine sublibraries:

```
bsub < lsf-script-combine.txt
```

The launcher jobs request minimal resources because they only parse inputs and submit child jobs. Each per-sublibrary alignment job uses `parseq_alignment_threads` and `parseq_alignment_mem_per_core_gb` from `project_parameters.Config.yaml` (default: 8 cores and 48 GB total). The combine job requests 6 cores and up to 36 GB memory.

### Run steps manually on an interactive session

To run Step 1 from an interactive node:

```
bash 01-splitpipe-alignment.sh
```

After all alignment jobs finish, run combine only:

```
bash run-splitpipe-combine.sh
```

Or run both steps through the module wrapper:

```
bash run-parseq-alignment.sh
```

## Folder content

This folder contains scripts to align Parse Biosciences single-cell RNA-seq data with `split-pipe` for one or many sublibraries across a project, then combine sublibrary outputs into a single dataset for downstream Snap-Parse modules.

Each sublibrary alignment uses:

- `--mode all` for per-sublibrary processing from FASTQ inputs
- `--nthreads` from `parseq_alignment_threads` in `project_parameters.Config.yaml`
- `--kit` and `--chemistry` values from the metadata file
- `--genome_dir` from `project_parameters.Config.yaml`
- `--samp_sltab` from the configured sample loading table

For more information, see the [Parse Biosciences split-pipe documentation](https://support.parsebiosciences.com/).

## Folder structure

The structure of this folder is as follows:

```
├── 01-splitpipe-alignment.sh
├── 02-splitpipe-combine.sh
├── lsf-script.txt
├── lsf-script-combine.txt
├── README.md
├── results
|   └── <analysis_folder>
|       ├── 01_logs
|       |   ├── <sublibrary_ID>
|       |   |   ├── fq1_list.txt
|       |   |   ├── fq2_list.txt
|       |   |   ├── submission_manifest.txt
|       |   |   ├── splitpipe.<jobid>.out
|       |   |   └── splitpipe.<jobid>.err
|       |   ├── alignment_dependencies.txt
|       |   ├── alignment_job_ids.txt
|       |   └── combined
|       |       ├── parse_combine.<jobid>.out
|       |       └── parse_combine.<jobid>.err
|       ├── 02_split_pipe
|       |   └── <sublibrary_ID>
|       ├── 03_combined
|       └── sublib_list.txt
├── run-parseq-alignment.sh
└── run-splitpipe-combine.sh
```

## Authors

Antonia Chroni, PhD ([@AntoniaChroni](https://github.com/AntoniaChroni)) and Sharon Freshour, PhD ([@sharonfreshour](https://github.com/sharonfreshour))
