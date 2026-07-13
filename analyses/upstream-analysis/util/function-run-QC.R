###########################################################################
#' Function to run miQC
#' @param sce
#'
#' @return
#' @export
#'
#' @examples
run_miQC <- function(sce) {
  if (any(sce$percent.mito == 0)) {
    print("miQC did not work, use two steps filtering as defined by `params` for `min_genes` and `mtDNA_pct_default`, and the `FindOutlierThershold` function!")
    } else {
      print("miQC worked!")
      model <- mixtureModel(sce)
      print(is.nan(model@logLik))    # Apply is.nan function
      parameters(model)
      head(posterior(model))
      print(plotModel(sce, model)) # Plot
      print(plotFiltering(sce, model))
      
      # Convert sce back to seurat object 
      sce <- as.Seurat(filterCells(sce, model), 
                                counts = "counts",
                                data = "logcounts")
  }
  return(sce)
}


###########################################################################
#' Function to run QC with default parameters
#' @param seurat_obj
#'
#' @return
#' @export
#'
#' @examples
run_QC_default <- function(seurat_obj) {
  if (use_only_step1 == "YES") {
    print("Use only step 1 with default parameters for filtering!")
    # Step 1
    cat("Step 1 data filter", sample_name[i], "\n")
    filtered_seurat_obj <- subset(seurat_obj, 
                           subset = nFeature_RNA >= min_genes &
                                    nCount_RNA >= min_count &
                                    percent.mito <= mtDNA_pct_default &
                                    percent.mito <= Find_Outlier_Thershold(seurat_obj$percent.mito)[2])
    } else {        
      print("Use step 1 with default parameters for filtering and then use the `Find_Outlier_Thershold` function!")
      # Step 1
      cat("Step 1 data filter", sample_name[i], "\n")
      filtered_seurat_obj_step1 <- subset(seurat_obj, 
                                          subset = nFeature_RNA >= min_genes &
                                                   nCount_RNA >= min_count &
                                                   percent.mito <= mtDNA_pct_default &
                                                   percent.mito <= Find_Outlier_Thershold(seurat_obj$percent.mito)[2])                                   
      # Step 2
      cat("Step 2 data filter", sample_name[i], "\n")
      nFeature_RNA_rm_outlier <- Find_Outlier_Thershold(filtered_seurat_obj_step1$nFeature_RNA)
      filtered_seurat_obj <- subset(filtered_seurat_obj_step1, 
                                    subset = nFeature_RNA >= Find_Outlier_Thershold(filtered_seurat_obj_step1$nFeature_RNA)[1] &
                                             nFeature_RNA <= Find_Outlier_Thershold(filtered_seurat_obj_step1$nFeature_RNA)[2])

  }
  return(filtered_seurat_obj)
}


###########################################################################
#' Function to run QC with default parameters but exclude MAD filtering for mitochondrial percentage
#' @param seurat_obj
#'
#' @return
#' @export
#'
#' @examples
run_QC_default_no_mito_MAD <- function(seurat_obj) {
  if (use_only_step1 == "YES") {
    print("Use only step 1 with default parameters for filtering!")
    # Step 1
    cat("Step 1 data filter", sample_name[i], "\n")
    filtered_seurat_obj <- subset(seurat_obj, 
                           subset = nFeature_RNA >= min_genes &
                                    nCount_RNA >= min_count &
                                    percent.mito <= mtDNA_pct_default)
    } else {        
      print("Use step 1 with default parameters for filtering and then use the `Find_Outlier_Thershold` function!")
      # Step 1
      cat("Step 1 data filter", sample_name[i], "\n")
      filtered_seurat_obj_step1 <- subset(seurat_obj, 
                                          subset = nFeature_RNA >= min_genes &
                                                   nCount_RNA >= min_count &
                                                   percent.mito <= mtDNA_pct_default)                                   
      # Step 2
      cat("Step 2 data filter", sample_name[i], "\n")
      nFeature_RNA_rm_outlier <- Find_Outlier_Thershold(filtered_seurat_obj_step1$nFeature_RNA)
      filtered_seurat_obj <- subset(filtered_seurat_obj_step1, 
                                    subset = nFeature_RNA >= Find_Outlier_Thershold(filtered_seurat_obj_step1$nFeature_RNA)[1] &
                                             nFeature_RNA <= Find_Outlier_Thershold(filtered_seurat_obj_step1$nFeature_RNA)[2])

  }
  return(filtered_seurat_obj)
}