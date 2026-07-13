# --------------------------------------------------------------------------------------------
# This has been updated to read and process ParseBio
# --------------------------------------------------------------------------------------------
# Mitochondrial Gene Detection Across Genome Formats
#
# The original 'calculate_mito_pct' helper function from the scooter package
# (source: https://github.com/igordot/scooter/blob/master/R/import.R)
# only detects mitochondrial genes in single-genome settings and assumes
# standard gene symbols such as:
#   • Human: MT-CO1, MT-ND1
#   • Mouse: mt-Nd1, mt-Co1
#
# However, our pipeline supports multiple genome configurations, including:
#   • Human (GRCh38, hg19)
#   • Mouse (GRCm39, mm10, mm9)
#   • Dual genomes (e.g., GRCh38 + mm10), which can contain *both* MT- and mt- prefixes
#   • Custom references with additional prefixes (e.g., GRCm39-mt-Nd5, Prefix-mt-Co2)
#
# To ensure full compatibility across all supported genome reference formats,
# we introduce an updated function, `calculate_mito_pct_updated()`, which:
#   1. Uses a generalized mitochondrial gene pattern that matches:
#         - Human-style:   MT-*
#         - Mouse-style:   mt-*
#         - Prefixed:      <anything>-mt-*
#   2. Correctly identifies mitochondrial features in single or dual genomes.
#   3. Computes percent mtDNA reads per cell and stores the result in metadata.
#
# This update ensures that mitochondrial QC metrics are calculated reliably
# regardless of annotation source, species, genome build, or custom reference structure.
# Maintainer:    Antonia Chroni (DNB Bioinformatics, St. Jude Children's Research Hospital)
# Last updated:  2026-06-16
# --------------------------------------------------------------------------------------------


###############################################################################################
#' Create a new Seurat object from a matrix.
#'
#' @param counts_matrix A matrix of raw counts.
#' @param assay Seurat assay to add the data to.
#' @param min_cells Include genes/features detected in at least this many cells.
#' @param min_genes Include cells where at least this many genes/features are detected.
#' @param log_file Filename for the logfile.
#' @param project Project name for Seurat object.
#'
#' @return Seurat object.
#'
#' @import dplyr readr tibble
#' @importFrom glue glue
#' @importFrom Matrix rowSums
#' @importFrom Seurat CreateSeuratObject AddMetaData
#' @export
create_seurat_obj <- function(counts_matrix, assay = "RNA",
                              min_cells = 1, min_genes = 1,
                              log_file = NULL, project = "proj", cell_metadata_info) {

  # check that the size of the input matrix is reasonable
  if (ncol(counts_matrix) < 10) {
    stop(glue::glue("matrix contains too few cells: {ncol(counts_matrix)}"))
  }

  # remove genes with very few counts
  counts_matrix <- counts_matrix[Matrix::rowSums(counts_matrix) > 0, ]

  message_str <- glue::glue("\n\n ========== create seurat object ========== \n\n
                     input cells: {ncol(counts_matrix)}
                     input genes: {nrow(counts_matrix)}")
  write_message(message_str, log_file)

  # Create seurat object
  s_obj <- CreateSeuratObject(
    counts = counts_matrix,
    meta.data = cell_metadata_info,
    project = "proj",
    assay = assay,
    names.field = 1,
    names.delim = ":",
    min.cells = min_cells,
    min.features = min_genes
  )

  # Calculate mito pct
  if (assay == "RNA") {
    s_obj <- calculate_mito_pct_updated(s_obj)
  }

  return(s_obj)
}
###############################################################################################

###############################################################################################
#' Calculate mitochondrial percentage from Seurat object.
#'
#' @param seurat_obj A Seurat object.
#' @param genome_name Genome name.
#'
#' @return Seurat object.
#'
#' @importFrom Matrix colSums
#' @importFrom Seurat AddMetaData
#' @export
calculate_mito_pct_updated <- function(seurat_obj) {
  # nGene and nUMI are automatically calculated for every object by Seurat
  # calculate the percentage of mitochondrial genes here and store it in percent.mito using the AddMetaData
  s_obj <- seurat_obj

  # get all mitochondrial genes (may fail depending on species or annotation)
  if (genome_name == "GRCh38" | genome_name == "hg19" | genome_name == "GRCm39" | genome_name == "mm10" | genome_name == "mm9"){
    mt_genes <- grep("^MT-", rownames(s_obj@assays$RNA@counts),
    ignore.case = TRUE, value = TRUE)
    } else if (genome_name == "DualGRCh38" | genome_name == "Dualhg19" | genome_name == "DualGRCm39" | genome_name == "Dualmm10" | genome_name == "Dualmm9"){
       mt_genes <- grep("(^mt-[A-Za-z0-9]+$)|(-mt-[A-Za-z0-9]+$)|(^MT-[A-Za-z0-9]+$)|(-MT-[A-Za-z0-9]+$)",
                        rownames(s_obj[["RNA"]]@counts),
                        ignore.case = FALSE,
                        value = TRUE)
       
    }
  
  # calculate the percent mitochondrial reads
  percent_mt <- Matrix::colSums(s_obj@assays$RNA@counts[mt_genes, ]) / Matrix::colSums(s_obj@assays$RNA@counts)
  percent_mt <- round(percent_mt * 100, digits = 3)

  # add columns to object@meta.data, and is a great place to stash QC stats
  s_obj <- AddMetaData(s_obj, metadata = percent_mt, col.name = "pct_mito")

  return(s_obj)
}
###############################################################################################

###############################################################################################
#' Add assay to Seurat object.
#'
#' @param seurat_obj Seurat object.
#' @param assay Seurat assay to add the matrix to.
#' @param counts_matrix Raw counts matrix.
#' @param log_file Filename for the log file.
#'
#' @return Seurat object of cells found in both the existing object and new data.
#'
#' @importFrom Seurat CreateAssayObject
#' @importFrom methods is
#' @export
add_seurat_assay <- function(seurat_obj, assay, counts_matrix, log_file = NULL) {
  if (!is(seurat_obj, "Seurat")) {
    stop(glue::glue("{seurat_obj} is not a Seurat object. Cannot add Assay"))
  }

  if (assay %in% names(seurat_obj)) {
    stop(glue::glue("{assay} already exists in the Seurat object"))
  }

  # use cells that are found in both antibody capture and RNA
  cells_to_use <- intersect(colnames(seurat_obj), colnames(counts_matrix))

  if (length(seurat_obj) != length(cells_to_use)) {
    message_str <- glue::glue("{ncol(seurat_obj) - length(cells_to_use)} cells in seurat object are not in counts matrix")
    write_message(message_str, log_file)
  }

  if (ncol(counts_matrix) != length(cells_to_use)) {
    message_str <- glue::glue("{ncol(seurat_obj) - ncol(counts_matrix)} cells in counts matrix not in scrna matrix")
    write_message(message_str, log_file)
  }

  # subset counts by joint cell barcodes
  counts_matrix <- as.matrix(counts_matrix[, cells_to_use])
  seurat_obj <- subset(seurat_obj, cells = cells_to_use)

  # add assay
  seurat_obj[[assay]] <- CreateAssayObject(counts = counts_matrix)

  return(seurat_obj)
}
###############################################################################################
