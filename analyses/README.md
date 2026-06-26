# Using Analysis Modules in single-cell RNA-seq data from PARSE BIOSCIENCES sequencing technology (ScRNASeqPARSE) Workflow

This repository contains a collection of analysis modules designed to process and analyze single-cell RNA-seq data from PARSE BIOSCIENCES sequencing technology. 

Each module is self-contained and can be executed independently or as part of a larger analysis pipeline. Below is a summary of each analysis module, including whether they are required or optional. Furthermore, the analysis modules should be run in the following recommended order:

1. `fastqc-analysis` module (description="Pipeline for FastQC quality control tool for high throughput sequence data analysis.", required=True).
2. `parseq-alignment` module (description="Pipeline for running and combining Parse Biosciences split-pipe alignment for multiple sublibraries.", required=True). 


## Contact

Contributions, issues, and feature requests are welcome! Please feel free to check [issues](https://github.com/stjude-dnb-binfcore/sc-snap-parse/issues).

---

*These tools and pipelines have been developed by the Bioinformatics core team at the [St. Jude Children's Research Hospital](https://www.stjude.org/). These are open access materials distributed under the terms of the [BSD 2-Clause License](https://opensource.org/license/bsd-2-clause), which permits unrestricted use, distribution, and reproduction in any medium, provided the original author and source are credited.*
