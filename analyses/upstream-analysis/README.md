# Pipeline for estimating QC metrics for sc-/sn-RNA-Seq Analysis in PARSE BIOSCIENCES sequencing technology data

## Usage

`run-upstream-analysis.sh` is designed to be run as if it was called from this module directory even when called from outside of this directory.

Parameters according to the project and analysis strategy will need to be specified in the following scripts:
- `project_parameters.Config.yaml` located at the `root_dir`.


### Sample metadata requirements

Sample identifiers must be consistent across modules:

- The `ID` column in `sample_metadata.tsv` **must match** the sample IDs defined in the Parse Biosciences sample loading table (`.xlsm`).
- `split-pipe` uses the sample loading table to assign sample-level output directories; mismatches can cause incorrect labeling or downstream failures even when alignment completes successfully.
- The `sublibrary_ID` column in `sublibrary_metadata.tsv` is independent and does not need to match the sample loading table.



### Run module on an interactive session on HPC within the container

To run all of the Rscripts in this module sequentially on an interactive session on HPC, please run the following command from an interactive compute node (while within the container):

```
bash run-upstream-analysis.sh
```

### Run module by using lsf on HPC with the container

There is also the option to run a lsf job on the HPC cluster by using the following command on an HPC node:

```
bsub < lsf-script.txt
```


## Folder content

This folder contains scripts tasked to:

(1) Infer QC metrics and associated plots to visually explore the quality of each library of the project.
(2) Evaluate QC metrics and set filters to remove low quality cells in Parse Biosciences single-cell- and single-nuclei-RNA-sequencing libraries (without cell hashing experiment).
(3) Estimate and filter doublets using a Parse-adapted multi-method scDblFinder strategy.
(4) Merge filtered data and generate a final QC summary report across upstream modules.

## QC Steps and methods

The pipeline offers flexibility for users to include or exclude methods and adjust the workflow during QC based on factors such as sequence type, expected cell number, experiment type, and genome reference.

By default, the pipeline runs all methods from steps (1-5). Step (2) is mandatory for basic QC filtering, while integration of steps (1) and/or (3) is optional. This can be configured in the `project_parameters.Config.yaml` file. However, we recommend reviewing all results, as this can provide valuable insights into the overall quality of each library.


### (1) Estimating and filtering out ambient mRNA (empty droplets) — optional

[SoupX](https://cran.r-project.org/web/packages/SoupX/vignettes/pbmcTutorial.html) profiles “the soup”, i.e., collection of cell-free mRNAs floating in the input solution. The soup looks different for each input solution and strongly resembles the expression pattern obtained by summing all the individual cells.

SoupX calculates `Cell-specific contamination fraction` (estimate or manually set the contamination fraction, the fraction of UMIs originating from the background, in each cell) and infers a `corrected expression matrix` (correct the expression of each cell using the ambient mRNA expression profile and estimated contamination).

The combined per-sample `split-pipe` outputs from the `parseq-alignment` module are used for this step.
 - Contamination summary table and cell-specific contamination fraction plot are generated.

Please note that if there is no cluster variability in the library, SoupX algorithm will fail when running `autoEstCont` by default:

```
sc <- autoEstCont(sc_raw, forceAccept = TRUE)
```

This means that the algorithm was not able to identify genes that are very specific to one cluster of cells. The determination of how specific is “very specific” is based on the gene’s `tf-idf` value for the cluster it is specific to. See the quickMarkers help or [this](https://constantamateur.github.io/2020-04-10-scDE/) for an explanation of what this means. The default of `tfidfMin=1` demands that genes be reasonably specific, so if the user is getting a low number of genes for estimation they can consider decreasing this value. This list is further reduced by keeping only genes that are “highly expressed” in the soup (as these give more accurate estimates of rho), where highly expressed is controlled by `soupQuantile`. The default value sounds strict, but in practice many genes with tf-idf over 1 tend to pass it.

If this is the case, the user will need to adjust as following in the `01_run_SoupX.Rmd` script:

```
sc <- autoEstCont(sc_raw, forceAccept = TRUE, tfidfMin = 0.1, soupQuantile = 0.9)
```


### (2) Seurat QC metrics

[Seurat](https://satijalab.org/seurat/articles/pbmc3k_tutorial.html) and [scooter](https://github.com/igordot/scooter) workflows are implemented to pre-process, filter and plot the RNA-sequencing data. The combined per-sample `split-pipe` outputs from the `parseq-alignment` module or the corrected per-sample matrices from step (1) SoupX will be used for this step. The user will have to define `params` as needed for their experiment.

Parse-specific data import is handled by `ReadParseBio()` in `util/import_updated_parse.R`, which reads filtered DGE matrices and cell metadata from `split-pipe` sample output directories. Cell barcodes are prefixed with the sample `ID`, and `sublibrary_ID` is mapped from `sublib_list.txt` in the combined output folder.

  - Before and after filter: plot distribution of the number of genes, UMI, and percent mitochondrial reads per cell.
  - Summary of cell statistics: percent of reads in cells, median UMI count per cell, median genes detected per cell, median percent reads mitochondrial.
  - Data are normalized by using the global-scaling normalization method “LogNormalize” that normalizes the feature expression measurements for each cell by the total expression, multiplies this by a scale factor (10,000 by default), and log-transforms the result. Then, highly variable genes (HVGs) are selected to subset features that indicate high cell-to-cell variation in the dataset (i.e., they are highly expressed in some cells, and lowly expressed in others). Then, these HVGs are used as input to principal component analysis, and the top 30 principal components are selected. A combination of 30 dimensions and 30 neighbors are used along with the principal components to calculate the UMAP (Uniform Manifold Approximation and Projection) embeddings.
  - Per-sample and per-sublibrary QC plots are generated via `generate_QC_Plots_sublibrary_ID.R`.

Here, the user can select to implement the following strategies to remove low quality cells:
- `step A` [miQC](https://bioconductor.org/packages/devel/bioc/vignettes/miQC/inst/doc/miQC.html) R package. The miQC model is based on the assumption that there are a non-trivial number of compromised cells in the dataset, which is not true in all datasets. If it is already known that the dataset is high-quality with a trivial number of compromised cells, we recommend that the user skip this step. If miQC does not identify any low quality cells, then `step B` will automatically be used as the filtering strategy.
- `step B` `run_QC_default` function. This is split in two filtering steps.
   - `step 1`: filter cells with low content of genes expressed and remove mtDNA from each library (as defined in the `params`).
   - `step 2`: `Find_Outlier_Thershold` function. This is an optional step (as defined in the `params`).

Moreover, only libraries with more than 500 cells will be kept for merging and integration purposes. This value is a commonly used threshold for many single-cell RNA-seq studies as a minimum for obtaining reliable and meaningful analysis.
- Statistical power: at least 500 cells are typically needed to ensure the analysis has enough statistical power to detect meaningful biological signals.
- Cell diversity: with fewer cells, you may not capture sufficient cellular diversity, leading to incomplete or biased results.
- Clustering: some clustering algorithms in single-cell RNA-seq require a minimum number of cells to create robust, meaningful clusters.


#### Post alignment/cell quality filtering parameters

We recommend that the user use the following parameters for initial QC, and then adjust accordingly if necessary:

- `scRNA`: min_genes = 300 (nFeature_RNA, genes detected)
           min_count = 500 (nCount_RNA, UMIs detected)
           mtDNA_pct_default = 15 (ideally 10; percent mitochondrial)
- `snRNA`: min_genes = 300 (nFeature_RNA, genes detected)
           min_count = 500 (nCount_RNA, UMIs detected)
           mtDNA_pct_default = 5 (ideally 1; percent mitochondrial)

#### Parse-specific QC defaults

Parse datasets typically exhibit lower mitochondrial expression compared to droplet-based methods (e.g., 10x), and applying MAD-based mitochondrial thresholds can be overly stringent (e.g., forcing mito% cutoff near zero). Therefore, mitochondrial MAD filtering is **disabled by default** in the `yaml` for Parse projects:

```yaml
use_QC_default_no_mito_MAD_upstream: "YES"  # default for Parse
use_QC_default_upstream: "NO"
```

These settings can be adjusted in the `yaml` to apply MAD-based fitlering thresholds for mitochondrial expression, if needed.

### (3) Estimating and filtering out doublets

Popular approaches of scRNAseq use oil droplets or wells to isolate single cells along with barcoded beads. Depending on the cell density loaded, a proportion of reaction volumes (i.e. droplets or wells) will capture more than one cell, forming ‘doublets’ (or ‘multiplets’), i.e. two or more cells captured by a single reaction volume and thus sequenced as a single-cell artifact.

The proportion of doublets is proportional to the number of cells captured. It is common in single-cell experiments to have 10-20% doublets in droplet-based platforms, making accurate doublet detection critical. For Parse Biosciences libraries, the expected doublet rate may vary by sample type, loading strategy, tissue characteristics, and project-specific behavior.

Doublets are prevalent in single-cell sequencing data and can lead to artifactual findings. We use a computational approach to calculate and remove doublets from the library. Here, we use the [scDblFinder](https://bioconductor.org/packages/devel/bioc/vignettes/scDblFinder/inst/doc/scDblFinder.html) method for identifying doublets/multiplets in single-cell data.

The `seurat_obj_raw.rds` object from step (2) is used for this step.
 - Summary table with doublet metrics and doublet prediction plots are generated per sample and per method.
 - Per-cell doublet calls from all methods are saved to `doublet_results_all_methods_per_cell.tsv`.
 - A merged Seurat object with all doublet metadata columns is saved as `merged_seurat_obj_with_doublets.rds`.

#### Parse-adapted scDblFinder strategy

Because platform-specific expected doublet rates for Parse Biosciences data can be uncertain, this pipeline evaluates **three scDblFinder parameterizations per sample** and derives **three scDblFinder_prior_sensitivity strategies** for downstream filtering.

All methods use `clusters = FALSE` (random approach), as benchmarking reports similar performance regardless of cluster structure ([Germain et al., 2021](https://f1000research.com/articles/10-979)).

| Method | YAML / metadata column | scDblFinder parameters | Description |
|--------|------------------------|------------------------|-------------|
| `no_dbr_dbr.sd_1` | `scDblFinder.class.no_dbr` | `dbr.sd = 1` | No fixed expected doublet rate; threshold relies on score distribution / misclassification error. Recommended when platform-specific rates are uncertain. |
| `low_dbr_0.0003` | `scDblFinder.class.low_dbr` | `dbr = 0.0003` (0.03%) | Very conservative fixed prior; usually flags very few cells as doublets. |
| `expected_dbr_` | `scDblFinder.class.expected_dbr` | `dbr = 0.035` (3.5%) | Higher fixed prior; the user can specify the value to use here, e.g. based on the anticipated proportion of doublets in the dataset. The default value provided in the `yaml` is 0.035. |
| `scDblFinder_prior_sensitivity_any` | `scDblFinder.class.scDblFinder_prior_sensitivity_any` | derived | Cell is a doublet if **at least one** of the three methods calls it a doublet (most permissive). |
| `scDblFinder_prior_sensitivity_majority` | `scDblFinder.class.scDblFinder_prior_sensitivity_majority` | derived | Cell is a doublet if **at least two** of the three methods call it a doublet. |
| `scDblFinder_prior_sensitivity_all` | `scDblFinder.class.scDblFinder_prior_sensitivity_all` | derived | Cell is a doublet only if **all three** methods call it a doublet (most stringent). |

The final filtering step (4) uses one of these columns, selected via `doublet_method_filter_object_module` in `project_parameters.Config.yaml`. The default is `scDblFinder.class.low_dbr`, which applies the conservative 0.03% expected doublet rate.

Helper functions in `util/helper_functions_scDblFinder.R` support per-cell extraction, sample-level summarization, scDblFinder_prior_sensitivity calculation, and UMAP-based doublet prediction plots.


### (4) Merging filtered data

Next, we merge count matrices from steps (1-3) after filtering out low quality cells, ambient RNA (optional as defined in the `params`), and doublets (optional as defined in the `params`). Seurat object and metadata for the library along with UMAP embeddings are saved to be used for downstream analyses.


### (5) Final QC summary report

Lastly, we provide a final QC summary report containing graphs and summary tables across each QC step.


## Folder structure

The structure of this folder is as follows:

```
├── 01_run_SoupX.Rmd
├── 02A_run_seurat_qc.Rmd
├── 02B_run_seurat_qc_multiple_samples.R
├── 03_run_scDblFinder.Rmd
├── 04_run_filter_object.Rmd
├── 05_run_summary_report.Rmd
├── plots
├── lsf-script.txt
├── README.md
├── results
├── run-upstream-analysis.R
├── run-upstream-analysis.sh
└── util
    ├── function-calculate-qc-metrics.R
    ├── function-create-UMAP.R
    ├── function-process-Seurat.R
    ├── function-run-QC.R
    ├── generate_QC_Plots_sublibrary_ID.R
    ├── helper_functions_scDblFinder.R
    └── import_updated_parse.R
```
