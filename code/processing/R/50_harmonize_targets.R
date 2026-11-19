# ============================================================================ #
# 50_harmonize_targets.R
# Purpose:  Apply to data_targets.csv, before the package is built, exactly the
#           three adjustments the BSAT model core (v2.27) makes on its own, in
#           the model's order, so that the model finds zero residuals and the
#           input targets are the targets it uses. No raw data is touched.
# Reads:    processed/data_targets.csv        (written by 12_generate_data_targets.R)
# Writes:   processed/data_targets.csv        (overwritten, harmonized)
#           interim/harmonization_log.csv     (one row per market-year with a nonzero
#                                              residual: region, year, commodity, check,
#                                              residual, adjusted, delta, status)
# Depends:  dplyr, tidyr, readr (loaded by 00_load_packages.R)
# Notes:    COTTON_KG_PER_BALE <- 217.728111162486 is the model's bale-to-kg factor.
#           WINDOW <- 2 is the model's repair window (v2.27; v2.26 used 1).
#           Sourced by main.R after 40, right before 60, so that script 20 computes the
#           expenditure share from the unrepaired quantities of 12, as the model authors do.
#
# The three adjustments, mirrored from model_core.jl, section "3) Decimal adjustments":
#
#   (a) Consumption components. For every region, year and commodity,
#         residual = Total Consumption - (Food Consumption + feed to livestock
#                    + other feed + Crushing),
#       where feed to livestock is the sum of the Total_feed_use_input_to_commodity
#       rows whose input is the commodity, other feed is Feed Consumption minus feed
#       to livestock (defined only where a Feed Consumption row exists), an absent
#       row counts 0 and is not a candidate, and a row present with a missing value
#       counts 0 and is a candidate. A residual within +/- WINDOW is added to the
#       largest candidate, first maximum in the order food, feed to livestock, other
#       feed, crushing. Row effect: food -> Food Consumption; crushing -> Crushing.
#       When the largest candidate is feed to livestock or other feed, the rows are
#       left alone and the residual is left to the model: the model repairs it in its
#       internal feed totals but reports feed consumption from the unrepaired target
#       (model_core.jl, df_DCFEED1), so leaving the row untouched is what reproduces
#       the model's output. Such markets are logged with status "left to the model".
#
#   (b) Supply and demand.
#         residual = (Beginning Stocks + Production + Imports - Loss)
#                    - (Total Consumption + Exports + Ending Stocks).
#       A residual within +/- WINDOW is subtracted from the largest of Beginning
#       Stocks, Production, Imports (first maximum in that order).
#
#   (c) Derived series, from the adjusted table: Yields = Production / Area (cotton in
#       kg per hectare via COTTON_KG_PER_BALE; missing without area) and Extraction
#       Rate of SoyMeal and SoyOil = 100 * Production / Crushing of Soybean in the same
#       region and year (missing without positive crush). Only existing Yields and
#       Extraction Rate rows are replaced. The model reports both series with the same
#       formulas, so the neutral run reproduces them exactly.
#
#   Residuals outside the window are left alone, logged with a status naming the window
#   and reported with a warning: the model refuses such a year ("Baseline Projections
#   Data DO NOT clear in levels"). No Slaughter rows are added (v2.27 dropped slaughter
#   from the model); any present are removed. With these adjustments the model's run on
#   this file gives the same solution as its run on the unharmonized file (checked by
#   code/model/test/runtests.jl), and the neutral run reproduces every target exactly.
# ============================================================================ #

rm(list = ls())
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

path_targets <- file.path(base_dir, "processed", "data_targets.csv")
path_log     <- file.path(base_dir, "interim",   "harmonization_log.csv")

COTTON_KG_PER_BALE <- 217.728111162486   # conversion used by the model (bales to kg)
WINDOW             <- 2                  # the model's repair window (v2.27)
FEED_ROW           <- "Total_feed_use_input_to_commodity"
KEY                <- c("region", "year", "commodity")

data_targets <- read_csv(path_targets, col_types = cols(.default = col_character(), value = col_double(), year = col_integer())) %>%
  filter(attribute != "Slaughter")

# ---------------------------------------------------------------------------- #
# Helpers
# ---------------------------------------------------------------------------- #

# Wide table of the level rows (empty `input`) of the attributes `attrs`, one row per
# market-year holding at least one of them. NA marks an absent row; a row present with
# a missing value is 0 (the model coerces missing to 0.0 and keeps the key).
level_rows <- function(df, attrs) {
  rows <- df %>% filter(is.na(input), attribute %in% attrs) %>% select(all_of(KEY), attribute, value)
  dup <- rows %>% count(region, year, commodity, attribute) %>% filter(n > 1)
  if (nrow(dup) > 0)
    stop("50_harmonize_targets: duplicated target rows, for example ", paste(dup[1, 1:4], collapse = " "))
  wide <- rows %>% mutate(value = coalesce(value, 0)) %>% pivot_wider(names_from = attribute, values_from = value)
  for (a in attrs) if (!a %in% names(wide)) wide[[a]] <- NA_real_
  wide
}

# Name of the first maximum among the columns `cands` of `wide`, in that order (NA columns
# are absent candidates); NA when no candidate is present. Mirrors findmax over the present
# dictionaries in the model.
first_max <- function(wide, cands) {
  m <- as.matrix(wide[, cands, drop = FALSE])
  apply(m, 1, function(v) if (all(is.na(v))) NA_character_ else cands[which.max(v)])
}

# Add `delta` to the rows of `df` matched by `upd` (region, year, commodity, input, attribute,
# delta); a matched row with a missing value starts from 0.
add_to_rows <- function(df, upd) {
  if (nrow(upd) == 0) return(df)
  df %>%
    left_join(upd, by = c(KEY, "input", "attribute")) %>%
    mutate(value = if_else(!is.na(delta), coalesce(value, 0) + delta, value)) %>%
    select(-delta)
}

# ---------------------------------------------------------------------------- #
# (a) Consumption components
# ---------------------------------------------------------------------------- #
feed_to_livestock <- data_targets %>%
  filter(attribute == FEED_ROW) %>%
  group_by(region, year, commodity = input) %>%
  summarise(LIV = sum(coalesce(value, 0)), .groups = "drop")

cons <- level_rows(data_targets, c("Total Consumption", "Food Consumption", "Feed Consumption", "Crushing")) %>%
  full_join(feed_to_livestock, by = KEY) %>%
  mutate(TC   = `Total Consumption`,
         FOOD = `Food Consumption`,
         OTR  = `Feed Consumption` - coalesce(LIV, 0),
         CRSH = Crushing,
         residual = coalesce(TC, 0) - (coalesce(FOOD, 0) + coalesce(LIV, 0) + coalesce(OTR, 0) + coalesce(CRSH, 0)))
cons$target <- first_max(cons, c("FOOD", "LIV", "OTR", "CRSH"))
cons <- cons %>%
  filter(residual != 0) %>%
  mutate(in_window = abs(residual) <= WINDOW & !is.na(target),
         to_model  = in_window & target %in% c("LIV", "OTR"),
         within    = in_window & !to_model,
         adjusted  = case_when(!within          ~ NA_character_,
                               target == "FOOD" ~ "Food Consumption",
                               target == "CRSH" ~ "Crushing"))

cons_upd <- cons %>%
  filter(within) %>%
  transmute(region, year, commodity, input = NA_character_, attribute = adjusted, delta = residual)

data_targets <- add_to_rows(data_targets, cons_upd)

# ---------------------------------------------------------------------------- #
# (b) Supply and demand
# ---------------------------------------------------------------------------- #
mkt <- level_rows(data_targets, c("Beginning Stocks", "Production", "Imports", "Loss",
                                  "Total Consumption", "Exports", "Ending Stocks")) %>%
  mutate(BS = `Beginning Stocks`, Q = Production, M = Imports,
         residual = (coalesce(BS, 0) + coalesce(Q, 0) + coalesce(M, 0) - coalesce(Loss, 0)) -
                    (coalesce(`Total Consumption`, 0) + coalesce(Exports, 0) + coalesce(`Ending Stocks`, 0)))
mkt$target <- first_max(mkt, c("BS", "Q", "M"))
mkt <- mkt %>%
  filter(residual != 0) %>%
  mutate(within = abs(residual) <= WINDOW & !is.na(target),
         to_model = FALSE,
         adjusted = case_when(!within ~ NA_character_,
                              target == "BS" ~ "Beginning Stocks",
                              target == "Q"  ~ "Production",
                              target == "M"  ~ "Imports"))

mkt_upd <- mkt %>%
  filter(within) %>%
  transmute(region, year, commodity, input = NA_character_, attribute = adjusted, delta = -residual)

data_targets <- add_to_rows(data_targets, mkt_upd)

# ---------------------------------------------------------------------------- #
# (c) Derived yields and extraction rates, from the adjusted table
# ---------------------------------------------------------------------------- #
wide <- data_targets %>%
  filter(is.na(input), attribute %in% c("Production", "Area", "Crushing")) %>%
  select(all_of(KEY), attribute, value) %>%
  pivot_wider(names_from = attribute, values_from = value)
for (a in c("Production", "Area", "Crushing")) if (!a %in% names(wide)) wide[[a]] <- NA_real_

derived_yield <- wide %>%
  filter(!is.na(Area), Area > 0, !is.na(Production)) %>%
  transmute(region, year, commodity,
            derived_yield = if_else(commodity == "Cotton",
                                    Production * COTTON_KG_PER_BALE / Area,
                                    Production / Area))

crush_by_region <- wide %>%
  filter(commodity == "Soybean", !is.na(Crushing), Crushing > 0) %>%
  select(region, year, crush_soybean = Crushing)

derived_ext <- wide %>%
  filter(commodity %in% c("SoyMeal", "SoyOil"), !is.na(Production)) %>%
  inner_join(crush_by_region, by = c("region", "year")) %>%
  transmute(region, year, commodity, derived_ext = 100 * Production / crush_soybean)

data_targets <- data_targets %>%
  left_join(derived_yield, by = KEY) %>%
  left_join(derived_ext,   by = KEY) %>%
  mutate(value = case_when(
    attribute == "Yields"          & !is.na(derived_yield) ~ derived_yield,
    attribute == "Yields"          &  is.na(derived_yield) ~ NA_real_,   # no area: nothing to derive from
    attribute == "Extraction Rate" & !is.na(derived_ext)   ~ derived_ext,
    attribute == "Extraction Rate" &  is.na(derived_ext)   ~ NA_real_,
    TRUE ~ value)) %>%
  select(-derived_yield, -derived_ext)

n_yield <- sum(data_targets$attribute == "Yields"          & !is.na(data_targets$value))
n_ext   <- sum(data_targets$attribute == "Extraction Rate" & !is.na(data_targets$value))

# ---------------------------------------------------------------------------- #
# Log, summary and save
# ---------------------------------------------------------------------------- #
status_of <- function(within, to_model, target) case_when(
  within                  ~ "adjusted",
  to_model                ~ "left to the model: feed component",
  is.na(target)           ~ "not adjusted: no candidate row",
  TRUE                    ~ sprintf("not adjusted: outside the model's ±%d window", WINDOW))

harmonization_log <- bind_rows(
  cons %>% transmute(region, year, commodity, check = "consumption", residual, adjusted,
                     delta = if_else(within, residual, NA_real_), status = status_of(within, to_model, target)),
  mkt  %>% transmute(region, year, commodity, check = "market", residual, adjusted,
                     delta = if_else(within, -residual, NA_real_), status = status_of(within, to_model, target))) %>%
  arrange(year, region, commodity, check)

dir.create(dirname(path_log), showWarnings = FALSE, recursive = TRUE)
write_csv(harmonization_log, path_log, na = "")

n_model <- sum(cons$to_model)
n_out   <- sum(harmonization_log$status != "adjusted") - n_model
cat(sprintf("50_harmonize_targets: %d consumption residuals and %d market residuals within ±%d applied as the model would; %d feed residuals left to the model; %d outside the window, not adjusted; %d yields and %d extraction rates derived from the adjusted targets\n",
            sum(cons$within), sum(mkt$within), WINDOW, n_model, n_out, n_yield, n_ext))
if (n_out > 0)
  warning(sprintf("50_harmonize_targets: %d residual(s) not adjusted; the model refuses those years. See %s", n_out, path_log), call. = FALSE)

data_targets <- data_targets %>% arrange(region, year, commodity, attribute)
write_csv(data_targets, path_targets, na = "")
