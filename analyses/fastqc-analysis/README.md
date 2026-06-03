# Pipeline for FastQC quality control tool for high throughput sequence data analysis

## Usage

`run-fastqc-analysis.sh` is designed to be run as if it was called from this module directory even when called from outside of this directory.

Parameters according to the project and analysis strategy will need to be specified in the following scripts:
- `project_parameters.Config.yaml`: define `metadata_dir` and `metadata_file_fastqc_module`. FASTQ paths to the fastqc files with format: `path1/*R1*.fastq.gz` are extracted from the `FASTQ` column from the `metadata_dir`. The `metadata_file_fastqc_module` file can include one or multiple samples, as long as it contains at least the following columns in this exact order: `ID`, `SAMPLE`, and `FASTQ`. 

For example:


| ID | SAMPLE | FASTQ | 
:----------|:----------|:----------|
| seq_submission_code1 | sample001 | /absolute_path/seq_submission_code1 | 
| seq_submission_code2 | sample002 | /absolute_path/seq_submission_code2 | 


FastQC module will automatically identify if there are multiple replicates and assign a `rep` value, analyze them separately and name the output files appropriately as: `_rep${rep}_fastqc.html` and `_rep${rep}_fastqc.zip`. There is no need to manually combine or rename the files—just list them correctly, and the pipeline takes care of the rest.


If the module needs to be run more than one time, user will need to remove the `02-multiqc-reports` folder before rerunning the module or the code will give an error at that step. Files and folder related to the MultiQC step will be generated every time a new run is performed. Folder can be deleted manually or from the node as:

```
rm -r 02-multiqc-reports
```


### Run module on an interactive session on HPC within the container

To run the script on an interactive session on HPC, please run the following command from an interactive compute node (while within the container):

```
bash run-fastqc-analysis.sh
```

### Run module by using lsf on HPC with the container

There is also the option to run a lsf job on the HPC cluster by using the following command on an HPC node:

```
bsub < lsf-script.txt
```


## Folder Content

This folder contains a script to run FastQC for quality control across all sequencing libraries in the project.

Each library directory is expected to contain the following files generated from the sc-parse workflow:

- **I1**: 8 bp sample index (library barcode)
- **R1**: 16 bp cell barcode + 10 bp UMI + read sequence
- **R2**: additional read (typically not used for primary transcript-level QC in this workflow)

### FastQC Scope

For sc-parse data, FastQC is run **on the R1 files**, as these contain the relevant sequence information used in downstream processing.

- **R1 (cell barcode + UMI + read sequence)** → evaluated for sequencing quality, GC content, adapter contamination, and overall read quality
- **I1 (sample index)** → not evaluated, as it is used only for demultiplexing
- **R2** → not evaluated, as it does not contribute primary information for QC in this workflow

Running FastQC on I1 or R2 typically does not provide meaningful metrics for assessing overall library quality.

### Additional Information

- Run `fastqc --help` from the command line for usage details
- See the official documentation:  
  [FastQC documentation](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
  
  
## Folder structure 

The structure of this folder is as follows:

```
├── lsf-script.txt
├── README.md
├── results
|   ├── 01-fastqc-reports
|   ├── 02-multiqc-reports
|   └──multiqc_report.html
└── run-fastqc-analysis.sh
```

