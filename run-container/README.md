# Running the Container for single-cell RNA-seq data workflow from PARSE BIOSCIENCES sequencing technology (ScRNASeqPARSE) 

We provide a Docker image that includes all tools, packages, and system dependencies required to run the scRNA-Seq Snap-Parse analysis modules (for more details, see the [devops-containers](https://github.com/stjude-dnb-binfcore/devops-containers/tree/main/analyses/sc-rna-seq/run-container)). The container is built and validated for `RStudio / R v4.4.0` and `Seurat v4.4.0` to ensure reproducibility across environments.


## Table of Contents

1. [Running the Container on HPC](#running-the-container-on-hpc)
   - [1. Start an Interactive Session](#1-start-an-interactive-session)
   - [2. Load the Singularity Module](#2-load-the-singularity-module)
   - [3. Pull the Singularity Container](#3-pull-the-singularity-container)
   - [4. Start the Singularity Container](#4-start-the-singularity-container)
     - [a. Running from the Terminal](#a-running-from-the-terminal)
     - [b. Running from RStudio](#b-running-from-rstudio)
     - [c. Running Analysis Modules via LSF](#c-running-analysis-modules-via-lsf)

2. [Running the Container Outside HPC (Docker)](#running-the-container-outside-hpc-docker)


## Running the Container on HPC

### 1. Start an Interactive Session

Open an interactive node on the HPC and adjust memory/resources as needed:

```
bsub -P hpcf_interactive -J hpcf_interactive -n 2 -q standard -R "rusage[mem=16G]" -Is "bash"
```

### 2. Load the Singularity Module

Please note that a version of Singularity is installed by default on all the cluster nodes at St Jude HPC. Otherwise the user needs to ensure and load Singularity module by running the following on HPC:

```
module load singularity/4.1.1
```

### 3. Pull the Singularity Container

1. Pull the singularity container from the `sc-snap-parse` root_dir

```
singularity pull docker://achronistjude/rstudio_4.4.0_seurat_4.4.0:latest
```


### 4. Start the Singularity Container

#### a. Running from the Terminal

User can run analysis module while on interactive node after executing the container:

```
bash run-terminal.sh
```

Then user may navigate to their module of interest, `./sc-snap-parse/analyses/<module_of_interest>`. For example:

```
cd ./sc-snap-parse/analyses/upstream-analysis
bash run-upstream-analysis.sh
```

#### b. Running from RStudio

User can also run analyses via Rstudio OnDemand after executing the container:

```
bash run-rstudio.sh
```

The `run-rstudio.sh` is running at `IP_ADDR:PORT`. When RStudio launches, please click "Session" -> "Restart R" (at the RStudio web session). Again, the user can navigate to their module of interest and explore/run their analyses.


#### c. Running Analysis Modules via LSF

All analysis modules are designed to be run while executing the container. User only needs to run the lsf script as described in the `README.md` files in each analysis module.



## Running the Container Outside HPC (Docker)

1. Pull the Docker Container from the `sc-snap-parse` root_dir:

```
docker pull docker://achroni/rstudio_4.4.0_seurat_4.4.0:latest
```

2. Start and Run the Docker Container from the terminal:

```
docker run --platform linux/amd64 --name review -d -e PASSWORD=ANYTHING -p 8787:8787 -v $PWD:/home/rstudio/sc-snap-parse docker://achroni/rstudio_4.4.0_seurat_4.4.0:latest
```

Start the container and open a terminal:

```
docker container start review
docker exec -ti review bash
```

Navigate to your module of interest and run the analysis:

```
cd ./sc-snap-parse/analyses/upstream-analysis
bash run-upstream-analysis.sh
```


## Authors

Antonia Chroni, PhD ([@AntoniaChroni](https://github.com/AntoniaChroni)) and 


## Contact

Contributions, issues, and feature requests are welcome! Please feel free to check [issues](https://github.com/stjude-dnb-binfcore/sc-snap-parse/issues).

---

*These tools and pipelines have been developed by the Bioinformatic core team at the [St. Jude Children's Research Hospital](https://www.stjude.org/). These are open access materials distributed under the terms of the [BSD 2-Clause License](https://opensource.org/license/bsd-2-clause), which permits unrestricted use, distribution, and reproduction in any medium, provided the original author and source are credited.*
