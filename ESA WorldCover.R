# 1. LOAD LIBRARIES ------------------------------------------------------------
pacman::p_load(
  rstac,       # For accessing STAC APIs
  sf,
  terra,
  tidyverse,
  tidyterra
)

# 2. PREPARE STUDY AREA FROM TRACKING DATA -------------------------------------
# Read and prepare tracking data
tracking_data <- read_delim("bobcat_coyotes_wa_gps.csv")

# Convert to SF object (WGS84)
animal_sf <- tracking_data %>%
  st_as_sf(
    coords = c("location-long", "location-lat"),
    crs = 4326
  )

# Create study area boundary with 10km buffer
study_area <- animal_sf %>%
  st_union() %>%
  st_convex_hull() %>%    # Create minimum convex polygon
  st_buffer(10000) %>%    # 10km buffer in CRS units
  st_transform(4326)      # Ensure WGS84 for ESA download

# 3. DOWNLOAD ESA WORLDCOVER DATA ----------------------------------------------
# Connect to Microsoft Planetary Computer STAC
stac_api <- stac("https://planetarycomputer.microsoft.com/api/stac/v1")

# Search for ESA WorldCover 2021 data within study area
esa_items <- stac_search(
  q = stac_api,
  collections = "esa-worldcover",
  datetime = "2021-01-01/2021-12-31",  # 2021 version
  bbox = st_bbox(study_area),           # Study area bounding box
  limit = 100
) %>%
  get_request() %>%
  items_sign(sign_planetary_computer())  # Authenticate

# Download all assets
assets_download(
  items = esa_items,
  asset_names = "map",
  output_dir = getwd(),
  overwrite = TRUE
)

# 4. PROCESS ESA DATA ----------------------------------------------------------
# Get all downloaded tiles
esa_tiles <- list.files(
  path = file.path(getwd(), "esa-worldcover/v200/2021/map"),
  pattern = "\\.tif$",
  full.names = TRUE
)

# Merge and crop tiles to study area
land_cover <- esa_tiles %>%
  lapply(rast) %>%
  do.call(mosaic, .) %>%    # Combine all tiles
  crop(vect(study_area)) %>% 
  mask(vect(study_area))

# Convert to factor for plotting
land_cover <- as.factor(land_cover)

# Save the final cropped/mosaicked land cover
writeRaster(
  land_cover,
  "ESA_land_cover_washington.tif",  # Output filename
  overwrite = TRUE,            # Overwrite if exists
  datatype = "INT1U",          # Optimize for categorical data
  gdal = c("COMPRESS=LZW")     # Reduce file size
)

# 5. VISUALIZE RESULTS ---------------------------------------------------------
# Class labels (ESA WorldCover 2021)
class_labels <- c(
  "10" = "Tree cover",
  "20" = "Shrubland",
  "30" = "Grassland",
  "40" = "Cropland",
  "50" = "Built-up",
  "60" = "Bare/sparse vegetation",
  "70" = "Snow and Ice",
  "80" = "Permanent water bodies",
  "90" = "Herbaceous wetland",
  "95" = "Mangroves",
  "100" = "Moss and lichen"
)

# Create plot
ggplot() +
  tidyterra::geom_spatraster(
    data = land_cover,
    maxcell = 1e6
  ) +
  scale_fill_manual(
    values = c(
      "10" = "#006400", "20" = "#FFBB22", "30" = "#FFFF4C",
      "40" = "#F096FF", "50" = "#FA0000", "60" = "#B4B4B4",
      "70" = "#F0F0F0", "80" = "#0064C8", "90" = "#0096A0",
      "95" = "#00CF75", "100" = "#FAE6A0"
    ),
    labels = class_labels,
    na.value = NA
  ) +
  geom_sf(
    data = animal_sf,
    color = "black",
    size = 1,
    alpha = 0.7
  ) +
  labs(
    title = "Animal Tracks Over Land Cover",
    fill = "Land Cover Class"
  ) +
  theme_minimal()
