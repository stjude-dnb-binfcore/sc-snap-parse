# Pipeline for FastQC quality control tool for high throughput sequence data analysis

## Usage

`run-fastqc-analysis.sh` is designed to be run as if it was called from this module directory even when called from outside of this directory.

Parameters according to the project and analysis strategy will need to be specified in the following scripts:
- `project_parameters.Config.yaml`: define `metadata_dir`. FASTQ paths to the fastqc files with format: `path1/*R2*.fastq.gz` are extracted from the `FASTQ` column from the `metadata_dir`. The `project_metadata.tsv` file can include one or multiple samples, as long as it contains at least the following columns in this exact order: `ID`, `SAMPLE`, and `FASTQ`. For samples with multiple technical replicates, list all associated FASTQ file paths in the same row, using commas to separate each path.

If the module needs to be run more than one time, user will need to remove the `02-multiqc-reports` folder before rerunning the module or the code will give an error at that step. Files and folder related to the MultiQC step will be generated every time a new run is performed. Folder can be deleted manually or from the node as:

```
rm -r 02-multiqc-reports
```

### Handling Technical Replicates in FastQC 

If a sample has multiple technical replicates (i.e., multiple sequencing runs of the same library), list all corresponding FASTQ file paths in the same row of the metadata file, separated by commas.

For example:


| ID | SAMPLE | FASTQ | 
:----------|:----------|:----------|
| DYE001 | seq_submission_code1_sample1 | /absolute_path/seq_submission_code1/replicate1,/absolute_path/seq_submission_code1/replicate2 | 


FastQC module will automatically identify if there are multiple replicates and assign a `rep` value, analyze them separately and name the output files appropriately as: `_rep${rep}_fastqc.html` and `_rep${rep}_fastqc.zip`. There is no need to manually combine or rename the files—just list them correctly, and the pipeline takes care of the rest.


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


## Folder content
This folder contains a script tasked to run FastQC quality control tool for all libraries across the project.
Each libary directory contains the following files:
- I1 is the 8 bp sample barcode, 
- R1 is the 16bp feature barcode + 10 bp UMI, and 
- R2 is the reads mapped to the transcriptome.
We only need to run FastQC on the single cell R2 files. Conducting read sequence QC on I1 or R1 wouldn't really tell us much other than do we trust our library indexing and barcode identification.

For more information, please:
- Type from the command line: fastqc --help, or
- See [fastqc](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)

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

