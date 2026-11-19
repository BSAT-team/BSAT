# ============================================================================ #
# test_50_harmonize_targets.R
# Purpose:  Check that 50_harmonize_targets.R applies exactly the three target
#           adjustments of the BSAT model core (v2.27), in the model's order, on
#           a small synthetic targets table.
# Run:      <micromamba> run -p <bsat env> Rscript code/processing/tests/test_50_harmonize_targets.R
#           (from any folder; needs dplyr, tidyr, readr, tibble)
# Notes:    The script under test reads and writes <data root>/processed/data_targets.csv
#           and <data root>/interim/harmonization_log.csv, with the data root taken
#           from getOption("bsat.data_dir"). The test points that option at a
#           temporary folder, sources the script in a private environment, and
#           checks the files it wrote.
# ============================================================================ #

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(readr); library(tibble) })

this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
if (length(this_file) != 1) stop("run this file with Rscript")
script <- normalizePath(file.path(dirname(this_file), "..", "R", "50_harmonize_targets.R"), mustWork = TRUE)

root <- tempfile("bsat_test13_")
dir.create(file.path(root, "processed"), recursive = TRUE)
dir.create(file.path(root, "interim"),   recursive = TRUE)

row <- function(region, commodity, attribute, value, input = NA_character_, year = 2025L) {
  tibble(region = region, year = year, nest = NA_character_, commodity = commodity, input = input,
         attribute = attribute, value = value, unit = NA_character_, attribute_type = NA_character_,
         attribute_description = attribute, region_name = NA_character_, nest_name = NA_character_,
         commodity_name = NA_character_)
}

targets <- bind_rows(
  # Corn (AAA): consumption residual +1; feed to livestock (70) is the largest component:
  # left to the model, rows untouched. Sorghum (AAA): residual +1, other feed largest: same.
  row("AAA", "Corn", "Total Consumption", 100),
  row("AAA", "Corn", "Food Consumption",   20),
  row("AAA", "Beef", "Total_feed_use_input_to_commodity", 50, input = "Corn"),
  row("AAA", "Pork", "Total_feed_use_input_to_commodity", 20, input = "Corn"),
  row("AAA", "Corn", "Feed Consumption",   79),
  row("AAA", "Sorghum", "Total Consumption", 21),
  row("AAA", "Sorghum", "Food Consumption",   5),
  row("AAA", "Sorghum", "Feed Consumption",  15),
  # Soybean (AAA): consumption residual +1, crushing largest; market residual -10, outside the window.
  row("AAA", "Soybean", "Total Consumption", 60),
  row("AAA", "Soybean", "Food Consumption",   0),
  row("AAA", "Soybean", "Feed Consumption",  10),
  row("AAA", "Soybean", "Crushing",          49),
  row("AAA", "Soybean", "Area",              10),
  row("AAA", "Soybean", "Production",        50),
  row("AAA", "Soybean", "Beginning Stocks",   5),
  row("AAA", "Soybean", "Imports",           10),
  row("AAA", "Soybean", "Exports",            3),
  row("AAA", "Soybean", "Ending Stocks",     12),
  # Wheat (AAA): market residual +14, outside the window. Wheat (BBB): residual +2, tie Q = M, Q wins.
  row("AAA", "Wheat", "Total Consumption", 30), row("AAA", "Wheat", "Food Consumption", 30),
  row("AAA", "Wheat", "Beginning Stocks",   4), row("AAA", "Wheat", "Production",      40),
  row("AAA", "Wheat", "Imports",           40), row("AAA", "Wheat", "Exports",         20),
  row("AAA", "Wheat", "Ending Stocks",     20),
  row("BBB", "Wheat", "Total Consumption", 30), row("BBB", "Wheat", "Food Consumption", 30),
  row("BBB", "Wheat", "Beginning Stocks",   4), row("BBB", "Wheat", "Production",      40),
  row("BBB", "Wheat", "Imports",           40), row("BBB", "Wheat", "Exports",         20),
  row("BBB", "Wheat", "Ending Stocks",     32),
  row("BBB", "Wheat", "Area",              10), row("BBB", "Wheat", "Yields",         999),   # derived after the repair
  # Oats (AAA): consumption residual +2 with a tie food = crushing (30 = 30): food wins (first in order).
  row("AAA", "Oats", "Total Consumption", 62), row("AAA", "Oats", "Food Consumption", 30),
  row("AAA", "Oats", "Crushing",          30),
  # Rice (AAA): zero residual, food row missing stays missing. Barley (AAA): residual +2 goes to a
  # food row that is present with a missing value (the model reads it as 0 and keeps the key).
  row("AAA", "Rice",   "Total Consumption", 10), row("AAA", "Rice",   "Food Consumption", NA_real_),
  row("AAA", "Rice",   "Feed Consumption",  10),
  row("AAA", "Barley", "Total Consumption",  2), row("AAA", "Barley", "Food Consumption", NA_real_),
  # Derived series: cotton yield in kg per hectare; soybean meal extraction rate from the adjusted
  # crush (50 after the consumption repair); beef yield without area is missing.
  row("AAA", "Cotton",  "Production", 100), row("AAA", "Cotton",  "Area", 50), row("AAA", "Cotton", "Yields", 999),
  row("AAA", "SoyMeal", "Production",  40), row("AAA", "SoyMeal", "Extraction Rate", 999),
  row("AAA", "Beef",    "Production",  10), row("AAA", "Beef",    "Yields", 999)
)
write_csv(targets, file.path(root, "processed", "data_targets.csv"), na = "")

options(bsat.data_dir = root, readr.show_col_types = FALSE)
warnings_seen <- character()
withCallingHandlers(
  source(script, local = new.env()),
  warning = function(w) { warnings_seen <<- c(warnings_seen, conditionMessage(w)); invokeRestart("muffleWarning") })

out <- read_csv(file.path(root, "processed", "data_targets.csv"),
                col_types = cols(.default = col_character(), value = col_double(), year = col_integer()))
log <- read_csv(file.path(root, "interim", "harmonization_log.csv"), col_types = cols(.default = col_character()))

val <- function(region, commodity, attribute, input = NA_character_) {
  r <- out %>% filter(.data$region == .env$region, .data$commodity == .env$commodity,
                      .data$attribute == .env$attribute,
                      if (is.na(.env$input)) is.na(.data$input) else .data$input == .env$input)
  if (nrow(r) != 1) stop(sprintf("expected one row for %s %s %s, found %d", region, commodity, attribute, nrow(r)))
  r$value
}
near <- function(a, b) !is.na(a) && !is.na(b) && abs(a - b) < 1e-9

# (a) consumption components: feed cases untouched, food and crushing repaired
stopifnot(near(val("AAA", "Corn", "Feed Consumption"), 79))
stopifnot(near(val("AAA", "Beef", "Total_feed_use_input_to_commodity", input = "Corn"), 50))
stopifnot(near(val("AAA", "Pork", "Total_feed_use_input_to_commodity", input = "Corn"), 20))
stopifnot(near(val("AAA", "Corn", "Food Consumption"), 20))
stopifnot(near(val("AAA", "Sorghum", "Feed Consumption"), 15), near(val("AAA", "Sorghum", "Food Consumption"), 5))
stopifnot(near(val("AAA", "Oats", "Food Consumption"), 32), near(val("AAA", "Oats", "Crushing"), 30))
stopifnot(near(val("AAA", "Soybean", "Crushing"), 50))
stopifnot(near(val("AAA", "Soybean", "Feed Consumption"), 10))
stopifnot(is.na(val("AAA", "Rice", "Food Consumption")))
stopifnot(near(val("AAA", "Barley", "Food Consumption"), 2))

# (b) supply and demand
stopifnot(near(val("AAA", "Soybean", "Beginning Stocks"), 5), near(val("AAA", "Soybean", "Production"), 50),
          near(val("AAA", "Soybean", "Imports"), 10), near(val("AAA", "Soybean", "Ending Stocks"), 12))
stopifnot(near(val("AAA", "Wheat", "Production"), 40), near(val("AAA", "Wheat", "Imports"), 40),
          near(val("AAA", "Wheat", "Ending Stocks"), 20), near(val("AAA", "Wheat", "Beginning Stocks"), 4))
stopifnot(near(val("BBB", "Wheat", "Production"), 38), near(val("BBB", "Wheat", "Imports"), 40),
          near(val("BBB", "Wheat", "Beginning Stocks"), 4))

# (c) derived series from the adjusted table
stopifnot(near(val("AAA", "Cotton", "Yields"), 100 * 217.728111162486 / 50))
stopifnot(near(val("BBB", "Wheat", "Yields"), 38 / 10))   # from the repaired production
stopifnot(near(val("AAA", "SoyMeal", "Extraction Rate"), 80))
stopifnot(is.na(val("AAA", "Beef", "Yields")))
stopifnot(!any(out$attribute == "Yields" & out$commodity == "Soybean"))   # no rows are created

# shape: no rows added or removed, no Slaughter rows
stopifnot(nrow(out) == nrow(targets))
stopifnot(!any(out$attribute == "Slaughter"))

# log
stopifnot(all(c("region", "year", "commodity", "check", "residual", "adjusted", "delta", "status") %in% names(log)))
adjusted <- log %>% filter(status == "adjusted") %>% arrange(check, region, commodity)
stopifnot(nrow(adjusted) == 4)
stopifnot(identical(adjusted$commodity, c("Barley", "Oats", "Soybean", "Wheat")))
stopifnot(identical(adjusted$check,     c("consumption", "consumption", "consumption", "market")))
stopifnot(adjusted$adjusted[adjusted$commodity == "Barley"]  == "Food Consumption")
stopifnot(adjusted$adjusted[adjusted$commodity == "Oats"]    == "Food Consumption")
stopifnot(adjusted$adjusted[adjusted$commodity == "Soybean"] == "Crushing")
stopifnot(adjusted$adjusted[adjusted$commodity == "Wheat"]   == "Production" && adjusted$region[adjusted$commodity == "Wheat"] == "BBB")
to_model <- log %>% filter(grepl("left to the model", status)) %>% arrange(commodity)
stopifnot(identical(to_model$commodity, c("Corn", "Sorghum")), all(to_model$check == "consumption"),
          all(is.na(to_model$adjusted)), all(is.na(to_model$delta)))
outside <- log %>% filter(status != "adjusted", !grepl("left to the model", status))
soy_mkt   <- outside %>% filter(region == "AAA", commodity == "Soybean", check == "market")
wheat_mkt <- outside %>% filter(region == "AAA", commodity == "Wheat",   check == "market")
stopifnot(nrow(soy_mkt) == 1, as.numeric(soy_mkt$residual) == -10, grepl("outside", soy_mkt$status))
stopifnot(nrow(wheat_mkt) == 1, as.numeric(wheat_mkt$residual) == 14, grepl("outside", wheat_mkt$status))
# Barley has a market residual of -2 but no stock, production or import row: within the window,
# no candidate, left alone (as the model does).
barley_mkt <- outside %>% filter(region == "AAA", commodity == "Barley", check == "market")
stopifnot(nrow(barley_mkt) == 1, grepl("no candidate", barley_mkt$status))
stopifnot(all(is.na(outside$delta)))
stopifnot(length(warnings_seen) >= 1)

cat("test_50_harmonize_targets: OK\n")
