# ============================================================================ #
# 25_compare_actual_imputed_NTM.R
# Purpose:  Diagnostics for the NTM imputation of 23_compute_NTM_ave.R: a scatter
#           plot of actual versus imputed AVE with a fitted line, and Excel tables
#           of the observations that could or could not be imputed.
# Reads:    interim/NTM_ave_imputed.RData        (object NTM_ave_imputed, written by 23)
# Writes:   outputs/diagnostics/actual_vs_imputed_AVE.pdf
#           outputs/diagnostics/NTM_AVE_diagnostics.xlsx
# Depends:  dplyr, openxlsx (loaded by 00_load_packages.R); base graphics
# Notes:    Not sourced by main.R. Run it manually after 23_compute_NTM_ave.R has
#           written interim/NTM_ave_imputed.RData (which needs the two large raw
#           files): from code/processing, source("R/00_load_packages.R") and then
#           source("R/25_compare_actual_imputed_NTM.R"); set
#           options(bsat.data_dir = ...) first if the data live elsewhere. The
#           outputs/diagnostics folder is created if needed.
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files (written by 23_compute_NTM_ave.R)
input_path_imputed_NTM  <- file.path(base_dir, "interim", "NTM_ave_imputed.RData")

# Output files
output_dir_diagnostics  <- file.path(base_dir, "outputs", "diagnostics")
output_path_comparison  <- file.path(output_dir_diagnostics, "actual_vs_imputed_AVE.pdf")
output_path_diagnostics <- file.path(output_dir_diagnostics, "NTM_AVE_diagnostics.xlsx")

dir.create(output_dir_diagnostics, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------- #
# Load and prepare data
# ---------------------------------------------------------------------------- #

# Load the imputed NTM data
load(input_path_imputed_NTM)

# Summary of imputed AVE
summary(NTM_ave_imputed$ave_hat)

# Keep valid records: non-missing and non-negative
NTM_ave_comparison <- NTM_ave_imputed %>%
  filter(ave >= 0 & !is.na(ave) & !is.na(ave_hat))

# ---------------------------------------------------------------------------- #
# Scatter plot: Actual vs imputed AVE
# ---------------------------------------------------------------------------- #

# Fit linear model
fit <- lm(ave_hat ~ ave, data = NTM_ave_comparison)
slope <- coef(fit)[2]  # Slope of fitted line
n_obs <- nrow(NTM_ave_comparison)  # Number of observations

# Save scatter plot to PDF
pdf(output_path_comparison, width = 8, height = 6)
plot(NTM_ave_comparison$ave, NTM_ave_comparison$ave_hat,
     xlab = "Actual AVE", 
     ylab = "imputed AVE", 
     main = "Actual vs imputed AVE")
abline(fit, col = "red")
text(
  x = 200, 
  y = 100, 
  labels = paste0("Slope: ", round(slope, 2), "\nN: ", n_obs),
  pos = 1, 
  cex = 0.8, 
  col = "blue"
)
dev.off()

# ---------------------------------------------------------------------------- #
# Diagnostics: Performance of imputation
# ---------------------------------------------------------------------------- #

# NTMs with missing imputed AVE (i.e. ave_hat not available)
ntm_missing_imputed <- NTM_ave_imputed %>% 
  filter(is.na(ave_hat))

# NTMs with missing actual AVE (i.e. ave not available)
ntm_missing_actual <- NTM_ave_imputed %>% 
  filter(is.na(ave))

# NTMs with missing actual AVE but a positive imputed AVE
ntm_imputed_success <- NTM_ave_imputed %>% 
  filter(is.na(ave) & !is.na(ave_hat) & ave_hat > 0)

# NTMs with missing actual AVE and failed imputation (missing or negative ave_hat)
ntm_imputed_fail <- NTM_ave_imputed %>% 
  filter(is.na(ave) & (is.na(ave_hat) | ave_hat < 0))

# ---------------------------------------------------------------------------- #
# Create metadata sheet describing each diagnostics dataset
# ---------------------------------------------------------------------------- #

metadata <- data.frame(
  name = c(
    "ntm_missing_imputed",
    "ntm_missing_actual",
    "ntm_imputed_success",
    "ntm_imputed_fail"
  ),
  description = c(
    "Observations where AVE could not be imputed (ave_hat is NA)",
    "Observations with missing actual AVE (ave is NA)",
    "Observations with missing actual AVE but a valid (positive) imputed AVE",
    "Observations with missing actual AVE and no valid imputation (NA or negative ave_hat)"
  )
)

# ---------------------------------------------------------------------------- #
# Export all diagnostics datasets and metadata to one Excel file
# ---------------------------------------------------------------------------- #

write.xlsx(
  list(
    metadata = metadata,
    ntm_missing_imputed  = ntm_missing_imputed,
    ntm_missing_actual   = ntm_missing_actual,
    ntm_imputed_success  = ntm_imputed_success,
    ntm_imputed_fail     = ntm_imputed_fail
  ),
  file = output_path_diagnostics
)


