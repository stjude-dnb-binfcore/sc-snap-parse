#################################################################################
# This will run all scripts in the module
#################################################################################
# Load the Package with a Specific Library Path
#.libPaths("/home/user/R/x86_64-pc-linux-gnu-library/4.4")
#################################################################################
# Load library
suppressPackageStartupMessages({
  library(yaml)})

#################################################################################
# load config file
configFile <- paste0("../../project_parameters.Config.yaml")
if (!file.exists(configFile)){
  cat("\n Error: configuration file not found:", configFile)
  stop("Exit...")}

# read `yaml` file defining the `params` of the project and strategy analysis
yaml <- read_yaml(configFile)

#################################################################################
# Set up directories and paths to root_dir and analysis_dir
root_dir <- yaml$root_dir
analysis_dir <- file.path(root_dir, "analyses", "upstream-analysis") 
parse_data_dir <- yaml$data_dir
analysis_folder <- yaml$analysis_folder
data_dir <- file.path(parse_data_dir, glue::glue("{analysis_folder}"), "03_combined")

# File path to plots directory
plots_dir <- file.path(analysis_dir, "plots") 
if (!dir.exists(plots_dir)) {
  dir.create(plots_dir)
}

# Create module_results_dir
module_results_dir <- file.path(analysis_dir, paste0("results"))
if (!dir.exists(module_results_dir)) {
  dir.create(module_results_dir)
}

SoupX_dir <- file.path(analysis_dir, "plots", "01_SoupX") 
scDblFinder_dir <- file.path(analysis_dir, "plots", "03_scDblFinder") 
Filter_object_dir <- file.path(analysis_dir, "plots", "04_Filter_object") 
Final_summary_report_dir <- file.path(analysis_dir, "plots", "05_Final_summary_report")

################################################################################################################
# Run Rmd scripts to process data per method
################################################################################################################
future_globals_value <- as.numeric(yaml$future_globals_value_upstream) * 1024^3
################################################################################################################
# (1) Estimating and filtering out ambient mRNA (`empty droplets`)
rmarkdown::render('01_run_SoupX.Rmd', 
                   clean = FALSE,
                   output_dir = file.path(SoupX_dir),
                   output_file = paste('Report-', 'SoupX', '-', Sys.Date(), sep = ''),
                   output_format = 'all',
                   params = list(
                    soup_fraction_value_default = yaml$soup_fraction_value_default,
                    root_dir = yaml$root_dir,
                    metadata_dir = yaml$metadata_dir,
                    metadata_file = yaml$metadata_file,
                    PROJECT_NAME = yaml$PROJECT_NAME,
                    PI_NAME = yaml$PI_NAME,
                    TASK_ID = yaml$TASK_ID,
                    PROJECT_LEAD_NAME = yaml$PROJECT_LEAD_NAME,
                    DEPARTMENT = yaml$DEPARTMENT,
                    LEAD_ANALYSTS = yaml$LEAD_ANALYSTS,
                    GROUP_LEAD = yaml$GROUP_LEAD,
                    CONTACT_EMAIL = yaml$CONTACT_EMAIL,
                    PIPELINE = yaml$PIPELINE, 
                    START_DATE = yaml$START_DATE,
                    COMPLETION_DATE = yaml$COMPLETION_DATE))

