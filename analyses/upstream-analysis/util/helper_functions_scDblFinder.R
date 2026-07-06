###############################################################################################################
#' Helper function: extract scDblFinder per-cell metadata
#' @param sce
#' @param sample_name
#' @param method_suffix
#' 
#'
#' @return
#' @export
#'
#' @examples
#' 
extract_scDblFinder_results <- function(sce, sample_name, method_suffix) {
  
  # Extract colData from the SingleCellExperiment object
  results <- as.data.frame(SingleCellExperiment::colData(sce))
  
  # Add cell barcode from row names
  results$cell <- rownames(results)
  
  # Add sample name explicitly, in case sample column is absent or inconsistent
  results$sample_name <- sample_name
  
  # Keep only relevant columns
  results <- results[, c("cell", "sample_name", "scDblFinder.class", "scDblFinder.score")]
  
  # Rename scDblFinder columns according to method
  colnames(results) <- c("cell", "sample_name", paste0("scDblFinder.class.", method_suffix), paste0("scDblFinder.score.", method_suffix))
  
  return(results)
}
###############################################################################################################


###############################################################################################################
#' Helper function: summarize sample-level doublet calls
#' @param sce
#' @param sample_name
#' @param method_name
#' 
#'
#' @return
#' @export
#'
#' @examples
#' 
summarize_doublets <- function(sce, sample_name, method_name) {
  
  # Count singlets and doublets
  tab <- table(SingleCellExperiment::colData(sce)$scDblFinder.class)
  
  singlet_n <- ifelse("singlet" %in% names(tab), as.integer(tab[["singlet"]]), 0L)
  doublet_n <- ifelse("doublet" %in% names(tab), as.integer(tab[["doublet"]]), 0L)
  
  total_n <- singlet_n + doublet_n
  doublets_pct <- ifelse(total_n > 0, round((doublet_n / total_n) * 100, 2), NA_real_)
  metrics <- data.frame(sample_name = sample_name, method = method_name, singlet = singlet_n, doublet = doublet_n, doublets_pct_library = doublets_pct, stringsAsFactors = FALSE)
  
  return(metrics)
}
###############################################################################################################


###############################################################################################################
#' Helper function: plot_scDblFinder_results
#' @param sce
#' @param method_label
#' 
#'
#' @return
#' @export
#'
#' @examples
#' 
plot_scDblFinder_results <- function(sce, method_label) {
  fname_png <- paste0(scDblFinder_plots_dir, "/", current_sample, "_", method_label, "_Doublets_prediction.png")
  print(fname_png)
  
  gridExtra::grid.arrange(plot1 <- plotUMAP(sce, colour_by = "scDblFinder.score", point_size = 0.1) + ggtitle(paste0("Doublet score")),
                          plot2 <- plotUMAP(sce, colour_by = "scDblFinder.class", point_size = 0.1) + ggtitle(paste0("Doublet class")),
                          ncol = 2, nrow = 1, top = paste0(current_sample, " - ", method_label, "_Doublets_prediction"), padding = unit(1.5, "line"))
  
  g <- gridExtra::arrangeGrob(plot1, plot2, ncol = 2, nrow = 1,
                              #top = paste0(current_sample, " - ", method_label, "_Doublets_prediction"),
                              padding = unit(1.5, "line")) #generates g
  ggsave(filename = fname_png, plot = g, width = 10, height = 4, device = "png")
}
###############################################################################################################


###############################################################################################################
#' Helper function: summarize consensus from all methods
#' @param df
#' @param sample_name
#' @param consensus_col
#' @param method_name

#' 
#'
#' @return
#' @export
#'
#' @examples
#' 
summarize_consensus <- function(df, sample_name, consensus_col, method_name) {

  sample_df <- df %>%
    dplyr::filter(sample_name == !!sample_name)

  doublet_n <- sum(sample_df[[consensus_col]], na.rm = TRUE)
  total_n <- nrow(sample_df)
  singlet_n <- total_n - doublet_n

  data.frame(
    sample_name = sample_name,
    method = method_name,
    singlet = singlet_n,
    doublet = doublet_n,
    doublets_pct_library = round(doublet_n / total_n * 100, 2),
    stringsAsFactors = FALSE
  )
}
###############################################################################################################
