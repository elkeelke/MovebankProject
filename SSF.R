# 0. Setup ----------------------------------------------------------------
# Load libraries
pacman::p_load(
  tidyverse,
  leaflet,
  amt,
  sf,
  geosphere,
  terra,
  MASS,
  glmmTMB,
  emmeans,
  paletteer,
  gratia,
  ggridges,
  performance
)

# Set options
options(scipen = 999) # Turn off scientific notation
options(digits = 15) # Set digits to 15 to ensure GPS coordinates aren't truncated
nt = parallel::detectCores() - 2 # Set number of threads for modelling

# Define common plot theme
theme_publication_dark <- function(base_size = 14, legend_position = "bottom") {
  theme_minimal(base_size = base_size) +
    theme(
      legend.position = legend_position,
      text = element_text(color = "white"),
      axis.text = element_text(color = "white"),
      panel.background = element_rect(fill = "#2D2D2D", color = NA),
      plot.background = element_rect(fill = "#2D2D2D", color = NA),
      panel.grid = element_line(color = "#424242"), 
      legend.background = element_rect(fill = "#2D2D2D", color = NA),
      legend.key = element_rect(fill = "#2D2D2D", color = NA),
      strip.text = element_text(color = "white", size = 10),
      plot.title = element_text(margin = margin(b = 15)),
      axis.title.x = element_text(margin = margin(t = 15)),
      axis.title.y = element_text(margin = margin(r = 15)),
      plot.margin = margin(20, 20, 20, 20, unit = "pt")
    )
}

# Define color palette
landuse_colors <- paletteer_d("nationalparkcolors::Badlands") |> 
  setNames(c("Water", "Cropland", "BuiltUp", "TreeCover", "Open"))

# 1. Data Preparation -----------------------------------------------------
# 1.1 Load, visualize and filter raw tracking data ------------------------
tracking_data <- read_delim("data/bobcat_coyotes_wa_gps.csv") |> 
  dplyr::rename(
    long = `location-long`, 
    lat = `location-lat`,
    id = `individual-local-identifier`,
    timestamp = `timestamp`,
    species = `individual-taxon-canonical-name`) |> 
  dplyr::arrange(id, timestamp) |> 
  dplyr::select(id, species, timestamp, lat, long)

# Create interactive map with random subset of locations and distinct species colors
leaflet() |> 
  addProviderTiles(providers$Esri.NatGeoWorldMap) |> 
  addCircles(data = tracking_data |> 
               mutate(rand = round(runif(n(), 0, 5))) |> 
               filter(rand == 1),
             color = ~ colorFactor(c("#5495CFFF", "#DB4743FF"), domain = species)(species), 
             label = ~ paste(id, timestamp), 
             opacity = 0.7) |> 
  addLegend(position = "topright", 
            colors = c("#5495CFFF", "#DB4743FF"), 
            labels = c("Coyote", "Bobcat"), 
            title = "Species",
            opacity = 1)

# Filter out MVBOB71M after dispersal from home range
tracking_data <- tracking_data |> 
  dplyr::filter(!(id == "MVBOB71M" & timestamp > as.POSIXct("2019-09-24 00:00:00")))

# 1.2 Create amt tracks ---------------------------------------------------
track <- tracking_data |>
  nest(data = c(-id, -species)) |>
  mutate(trk = map(data, ~ make_track(.x, long, lat, timestamp, crs = 4326)))

# Summarize sampling rate
trackSummary <- track |> 
  mutate(sr = lapply(trk, summarize_sampling_rate, time_unit = "hour")) |> 
  dplyr::select(id, sr) |> 
  unnest(cols = sr) |>
  left_join(distinct(dplyr::select(tracking_data, id, species))) |>
  arrange(species, median)

print(trackSummary, n = 70)

# Get the individual sampling rates, for plotting
trackSummarySamples <- track |>
  mutate(sr = lapply(trk, summarize_sampling_rate, time_unit = "hour", summarize = FALSE)) |>
  dplyr::select(id, sr) |>
  unnest(cols = sr) |>
  mutate(species = ifelse(grepl("BOB", id), "Bobcat", "Coyote"))

ggplot(trackSummarySamples,
       aes(x = species, y = sr,
           fill  = species, 
           color = species)) +
  stat_boxplot(geom = "errorbar", width = 0.4, linewidth = 0.7) +
  geom_boxplot(outlier.shape = NA, linewidth = 0.7) +
  scale_fill_manual(values  = c(Bobcat = "#723735")) +
  scale_color_manual(values = c(Bobcat = "#DB4743FF",  Coyote = "#5495CFFF")) +
  labs(title = "GPS sampling interval by species (outliers hidden)",
       x = NULL, y = "Sampling interval in hours") +
  coord_cartesian(ylim = c(0, 15)) +
  theme_publication_dark() +
  theme_publication_dark(legend_position = "none") +
  theme(panel.grid.major.x = element_blank())

ggsave("img/bobcat_coyote_sampling_rates.png", width = 8, height = 5, dpi = 300)

ggplot(trackSummarySamples,
       aes(x = species, y = sr,
           fill  = species,
           color = species)) +
  geom_boxplot(outlier.alpha = 0.5, width = 0.7, linewidth = 0.7) +                   
  scale_color_manual(values = c(Bobcat = "#DB4743FF",  Coyote = "#5495CFFF")) +
  labs(title = "GPS sampling interval by species (outliers shown)",
       x = NULL, y = "Sampling interval in hours") +
  coord_cartesian(ylim = c(0, 1000)) +
  theme_publication_dark(legend_position = "none") +
  theme(panel.grid.major.x = element_blank())

ggsave("img/bobcat_coyote_sampling_rates_outliers.png", width = 8, height = 5, dpi = 300)

# Split into species
coyote <- filter(track, grepl("COY", id))
bobcat <- filter(track, grepl("BOB", id))

# 1.3 Resample tracks and generate steps ----------------------------------
# Omitting coyote in row 8 and 19; too few consecutive data points - causing function to fail
coyote1 <- coyote[-c(8, 19), ] |> 
  mutate(stp = map(trk, function(df)
    df |> 
      track_resample(rate = hours(4), tolerance = minutes(10)) |> 
      steps_by_burst() |> 
      random_steps(n_control = 10) %>% 
      mutate(log_sl_ = log(sl_ + 1), cos_ta_ = cos(ta_)))) |> 
  dplyr::select(-data, -trk) |> 
  unnest(cols = stp) |> 
  mutate(case_binary_ = ifelse(case_ == TRUE, 1, 0))

# Omitting bobcat in row 15 and 18; too few consecutive data points - causing function to fail
bobcat1 <- bobcat[-c(15, 18), ] |> 
  mutate(stp = map(trk, function(df)
    df |> 
      track_resample(rate = hours(8), tolerance = minutes(10)) |> 
      steps_by_burst() |>  
      random_steps(n_control = 10) |> 
      mutate(log_sl_ = log(sl_ + 1), cos_ta_ = cos(ta_)))) |> 
  dplyr::select(-data, -trk) |> 
  unnest(cols = stp) |> 
  mutate(case_binary_ = ifelse(case_ == TRUE, 1, 0))

# Save resampled step data
saveRDS(coyote1, "data/coyote_resampled.rds")
saveRDS(bobcat1,  "data/bobcat_resampled.rds")

# Function to recalculate step lengths (in meters)
recalc_steps <- function(file) {
  readRDS(file) |>
    dplyr::select(-log_sl_, -sl_) |>
    mutate(
      sl_ = distGeo(across(c(x1_, y1_)), across(c(x2_, y2_))),
      log_sl_ = log(sl_)
    )
}

# Apply to saved data
coyote_resampled <- recalc_steps("data/coyote_resampled.rds")
bobcat_resampled <- recalc_steps("data/bobcat_resampled.rds")

# 1.4 Load covariates, extract to steps -----------------------------------
# Load and prepare rasters
hfp <- rast("data/HFP_washington.tif")
NAflag(hfp) <- 64536  # Set no-data value
hfp_capped <- classify(hfp, matrix(c(50000, Inf, 50000), ncol = 3, byrow = TRUE)) # Cap at 50k
hfp_scaled <- hfp_capped/1000 # Scale to 0-50
land_use <- rast("data/ESA_washington.tif")

# Land use class labels (ESA WorldCover 2021)
esa_labels <- c(
  "10" = "Tree cover", "20" = "Shrubland", "30" = "Grassland",
  "40" = "Cropland", "50" = "Built-up", "60" = "Bare or sparse vegetation",
  "70" = "Snow and ice", "80" = "Permanent water bodies",
  "90" = "Herbaceous wetland", "95" = "Mangroves", "100" = "Moss and lichen"
)

# Function to extract covariates
extract_covariates <- function(df) {
  df |>
    mutate(
      human_footprint = terra::extract(hfp_scaled, cbind(x2_, y2_))[, 1],
      land_use_code = terra::extract(land_use, cbind(x2_, y2_))[, 1],
      land_use = factor(land_use_code, levels = names(esa_labels), labels = esa_labels)
    )
}

# Apply extraction to step data
coyote_cov <- extract_covariates(coyote_resampled)
bobcat_cov <- extract_covariates(bobcat_resampled)

# 1.5 Finalize SSF dataset ------------------------------------------------
# Function to format for SSF
prepare_ssf_data <- function(df) {
  df |>
    mutate(
      land_use = as.factor(land_use),
      # Group detailed land use categories into broader, ecologically meaningful classes
      land_use_grouped = fct_collapse(
        land_use, 
        "TreeCover" = "Tree cover",
        "Open"      = c("Grassland", "Bare or sparse vegetation", "Moss and lichen"),
        "Cropland"  = "Cropland",
        "BuiltUp"   = "Built-up",
        "Water"     = c("Permanent water bodies", "Herbaceous wetland")
      ),
      # Create unique stratum ID (animal ID + step ID) for conditional logistic model
      step_id_ = paste(id, step_id_, sep = "_")
    ) |>
    group_by(id) |>
    mutate(n = n() / 11) |> # Calculate number of steps (1 used + 10 available per stratum)
    ungroup()
}

# Applying to data
coyote_final <- prepare_ssf_data(coyote_cov)
bobcat_final <- prepare_ssf_data(bobcat_cov)

# Summary of bobcat SSF data revealed too few relocations in key habitat types
# and inconsistent sampling intervals compared to coyotes.
# Therefore, bobcats are excluded from further SSF modeling.

# Save processed data
saveRDS(coyote_final, "data/coyote_ssf_data.rds")

# 2. Exploratory Data Analysis --------------------------------------------
# Read processed data
coyote_ssf_data <- readRDS("data/coyote_ssf_data.rds")

# Set secondary colors
landuse_colors_sec <- c("TreeCover" = "#4c5133",
                        "Open"      = "#807c70", 
                        "Cropland"  = "#7d6139",
                        "BuiltUp"   = "#723735", 
                        "Water"     = "#3c566e")

# 2.1 Ridgeline plot (HFP across land cover classes) ----------------------
ggplot(coyote_ssf_data,
       aes(x = human_footprint, y = fct_rev(land_use_grouped),
           fill = land_use_grouped, color = land_use_grouped)) +
  geom_density_ridges(scale = 1.2) +
  scale_fill_manual(values = landuse_colors_sec) + 
  scale_color_manual(values = landuse_colors) +
  labs(x = "Human Footprint Index (0–50)", y = "Land Cover Type",
       title = "Human Footprint Distribution by Land Cover Type") +
  theme_publication_dark(legend_position = "none") +
  theme(panel.grid.major.y = element_blank())

ggsave("img/coyote_EDA_ridgeline.png", width = 8, height = 5, dpi = 300)

# 2.2 Boxplot (HFP across land cover classes) -----------------------------
ggplot(coyote_ssf_data,
       aes(x = land_use_grouped, y = human_footprint,
           fill = land_use_grouped, color = land_use_grouped)) +
  stat_boxplot(geom = "errorbar", width = 0.4, linewidth = 0.7) +
  geom_boxplot(outlier.alpha = 0.15, outlier.size = 0.5, 
               width = 0.7, alpha = 1, linewidth = 0.5) +
  scale_fill_manual(values = landuse_colors_sec) + 
  scale_color_manual(values = landuse_colors) +
  labs(x = "Land Cover Type", y = "Human Footprint Index (0–50)",
       title = "Variation in Human Footprint across Land Cover Types") +
  theme_publication_dark(legend_position = "none") +
  theme(panel.grid.major.x = element_blank())

ggsave("img/coyote_EDA_boxplot.png", width = 8, height = 5, dpi = 300)

# 2.3 Bi-variate density plot (HFP vs. log step length) -------------------
dens <- kde2d(coyote_ssf_data$human_footprint, coyote_ssf_data$log_sl_, n = 100)
contour_level <- quantile(dens$z, probs = 0.95)  # Get 95% density threshold

ggplot(coyote_ssf_data, aes(x = human_footprint, y = log_sl_)) +
  geom_bin2d(aes(fill = after_stat(log(density))), bins = 50) +
  scale_fill_viridis_c(option = "D", limits = c(-14.9, -1)) +
  stat_density_2d(colour = "red", breaks = c(0.05), n = 15, size = 1)+
  geom_vline(xintercept = 0, colour = "gray80", linewidth = 0.6) +
  geom_hline(yintercept = 0, colour = "gray80", linewidth = 0.6) +
  labs(x = "Human Footprint Index (0–50)", y = "Log Step Length",
       title = "Relationship between Movement and Human Footprint") +
  theme_publication_dark(legend_position = "right")

ggsave("img/coyote_EDA_hexbin.png", width = 8, height = 5, dpi = 300)

# 3. Coyote SSF Modeling --------------------------------------------------
# Read SSF ready data and filter
coyote_ssf_data <- readRDS("data/coyote_ssf_data.rds") |> 
  filter(n > 100) # Select animals with more than 100 fixes

# Standardize HFP for modeling
coyote_ssf_data$hfp_std <- scale(coyote_ssf_data$human_footprint)[, 1]

# 3.1 Fit the model -------------------------------------------------------
# Fit SSF with glmmTMB following Muff et al (2019)
ssf_coyote <- glmmTMB(
  case_binary_ ~ -1 + 
    land_use_grouped * (hfp_std + I(hfp_std^2)) + 
    log_sl_ + 
    (0 + land_use_grouped + hfp_std + I(hfp_std^2) + log_sl_|| id) +
    (1 | step_id_),
  family = poisson,
  doFit = TRUE,
  data = coyote_ssf_data,
  map = list(theta = factor(c(1:8, NA))),
  start = list(theta = c(rep(0, times = 8),log(1e3))),
  control = glmmTMBControl(parallel = nt)
)

# 3.2 Save fitted model ---------------------------------------------------
saveRDS(ssf_coyote, file = "models/ssf_coyote_model.rds")
ssf_coyote <- readRDS("models/ssf_coyote_model.rds")

# 3.3 Summarize / check model ---------------------------------------------
# Print model summary (fixed effects, random effects, fit statistics)
summary(ssf_coyote)

# Estimate marginal trends (linear + quadratic) of HFP across land use types
emtrends(ssf_coyote, ~ land_use_grouped, var = "hfp_std", max.degree = 2) |>
  summary(infer = c(TRUE, TRUE))

# Test for overdispersion 
check_overdispersion(ssf_coyote)

# Calculate VIFs
check_collinearity(ssf_coyote)

# Plot predicted vs. observed use
coyote_ssf_data$predicted <- predict(ssf_coyote, type = "response")
ggplot(coyote_ssf_data, aes(x = predicted, fill = as.factor(case_binary_))) +
  geom_density(alpha = 0.5) +
  scale_fill_manual(values = c("1" = "#5495CFFF", "0" = "gray80"), name = "Used") +
  theme_publication_dark(legend_position = "right") +
  labs(x = "Predicted Relative Use (exp(η))", y = "Density")

# 4. SSF Results Visualization --------------------------------------------
# 4.1 Predict for average effect plots ------------------------------------
if (file.exists("data/coyote_ssf_pred.rds")) {
  coyote_ssf_pred <- readRDS("data/coyote_ssf_pred.rds")
} else {
  coyote_ssf_pred <- coyote_ssf_data |>
    filter(case_binary_ == 0) |> # remove ID for population-level prediction
    mutate(id = NA)
  
  coy_pred <- predict(ssf_coyote, coyote_ssf_pred, re.form = NA, se.fit = TRUE)
  coyote_ssf_pred$fit <- coy_pred$fit
  coyote_ssf_pred$se <- coy_pred$se
  coyote_ssf_pred <- coyote_ssf_pred |> ungroup()
  
  saveRDS(coyote_ssf_pred, "data/coyote_ssf_pred.rds")
}

# 4.2 Average-effect plot function ----------------------------------------
avg_eff_plot_hfp_landuse <- function(fittedResponse,
                                     nsim = 10, k = 10,
                                     showPeakValue = TRUE,
                                     save_path = NULL,
                                     width = 8, height = 5, dpi = 300) {
  
  set.seed(123)
  
  fit_sample_matrix <- replicate(nsim, {
    rnorm(n = nrow(fittedResponse), mean = fittedResponse$fit, sd = fittedResponse$se)
  })
  
  smooth_list <- purrr::map(1:nsim, function(j) {
    mgcv::bam(
      fit_sample_matrix[, j] ~ s(human_footprint, by = land_use_grouped,
                                 bs = "ts", k = k) + land_use_grouped,
      data    = fittedResponse,
      select  = TRUE, discrete = TRUE,
      nthreads = nt
    ) |>
      gratia::smooth_estimates(overall_uncertainty = TRUE) |>
      gratia::add_confint() |>
      dplyr::rename(hfp = human_footprint)
  })
  
  avg_smooth <- bind_rows(smooth_list) |>
    group_by(.smooth, .by, land_use_grouped, hfp) |>
    summarise(
      est       = mean(.estimate),
      lower_ci  = mean(.lower_ci),
      upper_ci  = mean(.upper_ci),
      .groups   = "drop"
    ) |>
    mutate(land_use_grouped = factor(
      land_use_grouped,
      levels = c("TreeCover", "Open", "Cropland", "BuiltUp", "Water"))
    )
  
  p <- ggplot(avg_smooth,
              aes(x = hfp, y = est, colour = land_use_grouped, fill = land_use_grouped)) +
    geom_hline(yintercept = 0,  linetype = "dashed", colour = "gray50") +
    geom_vline(xintercept = 0, linetype = "dotted", colour = "gray70") +
    geom_ribbon(aes(ymin = lower_ci, ymax = upper_ci), alpha = 0.2, colour = NA) +
    geom_line(linewidth = 1.2) +
    facet_wrap(~land_use_grouped, scales = "fixed", nrow = 2) +
    scale_colour_manual(values = landuse_colors) +
    scale_fill_manual(values   = landuse_colors) +
    labs(
      x = "Human Footprint Index (0–50)",
      y = "Estimated Relative Use (log)",
      title = "Average Marginal Effects across Human Footprint Gradient"
    ) +
    theme_publication_dark(legend_position = "none")
  
  if (showPeakValue) {
    peak_vals <- avg_smooth |>
      group_by(land_use_grouped) |>
      filter(est == max(est)) |>
      slice(rep(1:n(), each = 2)) |>
      mutate(est = ifelse(row_number() %% 2 == 1, est, -Inf))
    
    p <- p + geom_line(
      data = peak_vals,
      aes(x = hfp, y = est, group = land_use_grouped, colour = land_use_grouped),
      linetype = "dashed", linewidth = 0.8, alpha = 0.6)
  }
  
  if (!is.null(save_path))
    ggsave(save_path, p, width = width, height = height, dpi = dpi)
  
  return(p)
}

# 4.3 Relative-selection-strength (RSS) function --------------------------
calc_rss_hfp_landuse <- function(model, data,
                                 land_use_col = "land_use_grouped",
                                 hfp_col      = "hfp_std",
                                 n_points     = 100,
                                 ci_level     = 0.95,
                                 landuse_cols     = landuse_colors,
                                 landuse_cols_sec = landuse_colors,
                                 save_path = NULL,
                                 width = 8, height = 5, dpi = 300) {
  
  rss_df <- purrr::map_dfr(unique(data[[land_use_col]]), function(lc) {
    
    dat_lc  <- dplyr::filter(data, !!rlang::sym(land_use_col) == lc)
    hfp_seq <- seq(min(dat_lc[[hfp_col]], na.rm = TRUE),
                   max(dat_lc[[hfp_col]], na.rm = TRUE),
                   length.out = n_points)
    
    newdata <- expand.grid(hfp_std = hfp_seq, land_use_grouped = lc) |>
      dplyr::mutate(
        `I(hfp_std^2)` = hfp_std^2,
        log_sl_        = mean(data$log_sl_, na.rm = TRUE),
        step_id_ = NA, id = NA, case_binary_ = 1
      )
    
    baseline <- dplyr::filter(newdata, hfp_std == min(hfp_std))
    
    x1_pred <- predict(model, newdata,               re.form = NA)
    x2_pred <- predict(model, baseline[rep(1, nrow(newdata)), ], re.form = NA)
    
    mm_terms <- delete.response(terms(model))
    X1 <- model.matrix(mm_terms, newdata)
    X2 <- model.matrix(mm_terms, baseline[rep(1, nrow(newdata)), ])
    delta_X <- X1 - X2
    
    vc        <- vcov(model)$cond
    keep_cols <- intersect(colnames(delta_X), colnames(vc))
    delta_X   <- delta_X[, keep_cols, drop = FALSE]
    vc        <- vc[keep_cols, keep_cols, drop = FALSE]
    
    se_pred <- sqrt(rowSums((delta_X %*% vc) * delta_X))
    z_val   <- qnorm(1 - (1 - ci_level) / 2)
    
    tibble::tibble(
      land_use_grouped = lc,
      hfp_std          = hfp_seq,
      human_footprint  = hfp_seq * sd(data$human_footprint, na.rm = TRUE) +
        mean(data$human_footprint, na.rm = TRUE),
      logRSS    = x1_pred - x2_pred,
      RSS       = exp(logRSS),
      RSS_lower = exp(logRSS - z_val * se_pred),
      RSS_upper = exp(logRSS + z_val * se_pred)
    )
  })
  
  p <- ggplot(rss_df,
              aes(x = human_footprint, y = RSS,
                  colour = land_use_grouped, fill = land_use_grouped)) +
    geom_hline(yintercept = 1, linetype = "dashed", colour = "grey50") +
    geom_ribbon(aes(ymin = RSS_lower, ymax = RSS_upper),
                alpha = 0.2, colour = NA) +
    geom_line(linewidth = 1.1) +
    scale_colour_manual(values = landuse_cols) +
    scale_fill_manual(values  = landuse_cols_sec) +
    labs(
      x = "Human Footprint Index (0–50)",
      y = "Relative Selection Strength (RSS)",
      title = "Coyote Habitat Selection across the Human Footprint Gradient",
      colour = "Land-cover", fill = "Land-cover"
    ) +
    theme_publication_dark(legend_position = "bottom")
  
  if (!is.null(save_path))
    ggsave(save_path, p, width = width, height = height, dpi = dpi)
  
  return(p)
}

# 4.4 Generate and plot average effect ------------------------------------
p_avg_effect <- avg_eff_plot_hfp_landuse(coyote_ssf_pred, nsim = 1000, save_path = "img/avg_effect.png")
print(p_avg_effect)

# Report peaks
p_avg_effect$plot_env$peak_vals

# 4.5 Generate and plot RSS -----------------------------------------------
p_rss <- calc_rss_hfp_landuse(ssf_coyote, coyote_ssf_data, save_path = "img/rss.png")
print(p_rss)
