# Executes an analysis plan (02_plan.json, schemas/plan.schema.json) and writes
# 03_results.json (schemas/results.schema.json) + audit.jsonl.
#
# Tier 1 tools are data handling adapted from Samen Analyseren / Analyse-Together
# (https://github.com/rivm-syso/Analyse-Together, GPL-3); Tier 2 tools wrap
# openair. Every number the AI may quote is written as a "values" entry.
#
# Usage: Rscript scripts/run_analysis.R plan.json out [data_dir]

suppressMessages({
  library(jsonlite)
  library(nanoparquet)
  library(dplyr)
  library(lubridate)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript run_analysis.R plan.json out [data_dir]")
plan     <- fromJSON(args[1], simplifyVector = FALSE)
out      <- args[2]
data_dir <- if (length(args) >= 3) args[3] else "data"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

# ---- shared state across steps -------------------------------------------
st <- new.env(parent = emptyenv())

# ---- small helpers --------------------------------------------------------
NL_BBOX <- list(lat = c(50.6, 53.7), lon = c(3.2, 7.3))

haversine_km <- function(lat1, lon1, lat2, lon2) {
  r <- 6371
  p <- pi / 180
  a <- sin((lat2 - lat1) * p / 2)^2 +
    cos(lat1 * p) * cos(lat2 * p) * sin((lon2 - lon1) * p / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}

period_bounds <- function() {
  lapply(plan$periods, function(p) {
    list(
      label = if (!is.null(p$label)) p$label else paste(p$start, p$end, sep = ".."),
      start = as.POSIXct(paste0(p$start, " 00:00:00"), tz = "UTC"),
      end   = as.POSIXct(paste0(p$end, " 00:00:00"), tz = "UTC") + days(1)
    )
  })
}

period_label_for <- function(dates, periods) {
  lab <- rep(NA_character_, length(dates))
  for (p in periods) lab[dates >= p$start & dates < p$end] <- p$label
  lab
}

round2 <- function(x) if (is.finite(x)) round(x, 2) else NA
# Turn a human period label (e.g. "October 2024") into a value id that matches
# the results schema pattern ^[a-z0-9_]+$.
slug <- function(s) gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(s)))
val <- function(id, label, value, unit, period = NULL) {
  v <- list(id = id, label = label, value = value, unit = unit)
  if (!is.null(period)) v$period <- period
  v
}

# ---- audit ----------------------------------------------------------------
audit <- character()
log_step <- function(step, tool, tier, software, detail) {
  audit <<- c(audit, toJSON(list(
    run_id = plan$plan_id,
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    step = step, tool = tool, tier = tier, software = software, detail = detail),
    auto_unbox = TRUE, null = "null"))
}

# ---- data loading (Tier 1 shared) ----------------------------------------
# Reads data_sensors.parquet once, cleans locations, selects the sensors in the
# requested area, and tags each hourly row with the period it falls in.
pollutant <- plan$pollutant
pollutant_calibrated <- function() {
  for (s in plan$steps) if (identical(s$tool, "get_sensor_data")) {
    if (!is.null(s$params$calibrated)) return(isTRUE(s$params$calibrated))
  }
  TRUE
}

value_column <- function() {
  calibrated <- pollutant_calibrated()
  switch(pollutant,
    pm25 = if (calibrated) "pm25_kal" else "pm25_raw",
    pm10 = "pm10_raw",
    pm1  = NA_character_,
    no2  = NA_character_,
    NA_character_)
}

ensure_loaded <- function() {
  if (!is.null(st$loaded)) return(invisible(TRUE))
  vcol <- value_column()
  if (is.na(vcol)) stop(sprintf("pollutant '%s' is not available in this dataset", pollutant))

  raw <- nanoparquet::read_parquet(file.path(data_dir, "data_sensors.parquet"))
  periods <- period_bounds()
  st$periods <- periods
  wmin <- min(sapply(periods, function(p) as.numeric(p$start)))
  wmax <- max(sapply(periods, function(p) as.numeric(p$end)))

  raw$date <- as.POSIXct(raw$timestamp_from, tz = "UTC")
  raw <- raw[!is.na(raw$date) &
               as.numeric(raw$date) >= wmin &
               as.numeric(raw$date) <  wmax, , drop = FALSE]

  # per-kit modal (median of valid) location
  valid_loc <- raw$latitude  >= NL_BBOX$lat[1] & raw$latitude  <= NL_BBOX$lat[2] &
               raw$longitude >= NL_BBOX$lon[1] & raw$longitude <= NL_BBOX$lon[2]
  loc <- raw[valid_loc, c("kit_id", "latitude", "longitude")] |>
    group_by(kit_id) |>
    summarise(lat = median(latitude), lon = median(longitude), .groups = "drop")

  # select sensors in the area
  area <- plan$area
  if (!is.null(area$sensor_ids) && length(area$sensor_ids) > 0) {
    sel <- loc$kit_id[loc$kit_id %in% unlist(area$sensor_ids)]
  } else if (!is.null(area$lat) && !is.null(area$lon) && !is.null(area$radius_km)) {
    loc$dist <- haversine_km(area$lat, area$lon, loc$lat, loc$lon)
    sel <- loc$kit_id[loc$dist <= area$radius_km]
  } else {
    stop("area needs either sensor_ids, or lat/lon + radius_km (postcode alone is not enough)")
  }

  df <- raw[raw$kit_id %in% sel, , drop = FALSE]
  df$value <- df[[vcol]]
  df$period <- period_label_for(df$date, periods)
  df <- df[!is.na(df$period), c("kit_id", "date", "value", "rh", "temp", "period")]
  df <- left_join(df, loc[, c("kit_id", "lat", "lon")], by = "kit_id")

  meta <- nanoparquet::read_parquet(file.path(data_dir, "metadata_sensors.parquet"))
  df <- left_join(df, meta[, c("kit_id", "pm25_sensor")], by = "kit_id")

  st$meta      <- meta
  st$kits      <- sel
  st$value_col <- vcol
  st$data      <- df
  st$loaded    <- TRUE
  invisible(TRUE)
}

sensor_type <- function(kit) {
  m <- st$meta$pm25_sensor[match(kit, st$meta$kit_id)]
  ifelse(is.na(m), "unknown", m)
}

# ---------------------------------------------------------------------------
# TIER 1 TOOLS
# ---------------------------------------------------------------------------

tool_check_data_coverage <- function(p) {
  ensure_loaded()
  df <- st$data
  kit_type <- sensor_type(st$kits)
  n_sps30  <- sum(grepl("SPS30", kit_type, ignore.case = TRUE))
  n_sds011 <- sum(grepl("SDS011", kit_type, ignore.case = TRUE))

  values <- list(
    val("sensors_found", "Sensors in the area", length(st$kits), "count"),
    val("sensors_sps30", "Sensirion SPS30 sensors", n_sps30, "count"),
    val("sensors_sds011", "Nova SDS011 sensors", n_sds011, "count"))

  warnings <- list()
  below75_total <- 0
  for (per in st$periods) {
    hours <- as.numeric(difftime(per$end, per$start, units = "hours"))
    sub <- df[df$period == per$label & !is.na(df$value), ]
    cov <- sub |>
      group_by(kit_id) |>
      summarise(n = n(), .groups = "drop") |>
      mutate(pct = pmin(100, 100 * n / hours))
    med <- if (nrow(cov)) round2(median(cov$pct)) else 0
    below75 <- sum(cov$pct < 75)
    below75_total <- below75_total + below75
    values[[length(values) + 1]] <- val(
      paste0("coverage_median_", slug(per$label)),
      "Median data coverage", med, "%", per$label)
  }
  values[[length(values) + 1]] <- val(
    "sensors_below_75pct", "Sensors below 75% coverage in a period", below75_total, "count")

  status <- "ok"
  if (length(st$kits) == 0) {
    status <- "failed"
    warnings <- c(warnings, "No sensors found in the requested area")
  } else if (below75_total > 0) {
    status <- "warning"
    warnings <- c(warnings, sprintf(
      "%d sensor(s) have less than 75%% of their hours in a period", below75_total))
  }

  list(step = "data_check", tier = 1L, status = status,
       inputs_used = list(radius_km = plan$area$radius_km,
                          periods = lapply(st$periods, function(p) p$label)),
       values = values, warnings = warnings, files = list())
}

tool_get_sensor_data <- function(p) {
  ensure_loaded()
  df <- st$data
  n_meas <- sum(!is.na(df$value))
  warnings <- list()
  if (identical(pollutant, "pm10"))
    warnings <- c(warnings, "PM10 has no calibrated field; raw values are used")
  list(step = "data_check", tier = 1L, status = if (n_meas > 0) "ok" else "warning",
       inputs_used = list(pollutant = pollutant, calibrated = pollutant_calibrated(),
                          column = st$value_col),
       values = list(
         val("sensors_loaded", "Sensors with data",
             length(unique(df$kit_id[!is.na(df$value)])), "count"),
         val("measurements_loaded", "Hourly values loaded", n_meas, "count")),
       warnings = warnings, files = list())
}

tool_detect_faulty_sensors <- function(p) {
  ensure_loaded()
  df <- st$data
  stuck_hours  <- if (!is.null(p$stuck_hours)) p$stuck_hours else 24
  error_values <- if (!is.null(p$error_values)) unlist(p$error_values) else c(344.54)
  max_value    <- if (!is.null(p$max_value)) p$max_value else 1000

  n_before <- sum(!is.na(df$value))

  # single bad values -> NA
  bad <- !is.na(df$value) & (df$value %in% error_values | df$value > max_value | df$value < 0)
  values_removed <- sum(bad)
  df$value[bad] <- NA

  # stuck sensors: a run of >= stuck_hours identical hourly values
  faulty <- character()
  for (kit in unique(df$kit_id)) {
    idx <- which(df$kit_id == kit)
    v <- df$value[idx][order(df$date[idx])]
    v <- v[!is.na(v)]
    if (length(v) >= stuck_hours) {
      r <- rle(v)
      if (any(r$lengths >= stuck_hours)) faulty <- c(faulty, kit)
    }
  }
  n_faulty <- length(faulty)
  df <- df[!(df$kit_id %in% faulty), ]

  st$data <- df
  st$kits <- setdiff(st$kits, faulty)

  pct <- if (n_before > 0) round2(100 * values_removed / n_before) else 0
  status <- if (n_faulty > 0 || values_removed > 0) "warning" else "ok"
  warnings <- list()
  if (n_faulty > 0) warnings <- c(warnings, sprintf(
    "%d sensor(s) left out: stuck on one value for %d+ hours or on an error code",
    n_faulty, stuck_hours))

  list(step = "sensor_check", tier = 1L, status = status,
       inputs_used = list(stuck_hours = stuck_hours, error_values = as.list(error_values),
                          max_value = max_value),
       values = list(
         val("excluded_broken", "Broken sensors left out", n_faulty, "count"),
         val("sensors_remaining", "Sensors after the check", length(st$kits), "count"),
         val("values_removed", "Single values removed", values_removed, "count"),
         val("values_removed_pct", "Share of values removed", pct, "%")),
       warnings = warnings, files = list())
}

tool_flag_high_humidity <- function(p) {
  ensure_loaded()
  df <- st$data
  threshold <- if (!is.null(p$threshold_rh)) p$threshold_rh else 85
  rh <- df$rh
  rh[!is.na(rh) & (rh == 655.35 | rh > 100 | rh < 0)] <- NA
  usable <- !is.na(df$value) & !is.na(rh)
  humid_pct <- if (any(usable)) round2(100 * sum(rh[usable] > threshold) / sum(usable)) else 0

  warnings <- list()
  status <- "ok"
  if (humid_pct > 20) {
    status <- "warning"
    warnings <- c(warnings, sprintf(
      "%.1f%% of hours very damp (RH above %d%%): sensors may read too high",
      humid_pct, threshold))
  }
  list(step = "sensor_check", tier = 1L, status = status,
       inputs_used = list(threshold_rh = threshold),
       values = list(val("humid_hours_pct",
                         paste0("Hours with humidity above ", threshold, "%"),
                         humid_pct, "%")),
       warnings = warnings, files = list())
}

tool_filter_outliers <- function(p) {
  ensure_loaded()
  df <- st$data
  method <- if (!is.null(p$method)) p$method else "default"
  # default = physical bounds only; real peaks are kept (see sensor-quality.md #7)
  n_before <- sum(!is.na(df$value))
  bad <- !is.na(df$value) & (df$value < 0 | df$value > 1000)
  removed <- sum(bad)
  df$value[bad] <- NA
  st$data <- df
  pct <- if (n_before > 0) round2(100 * removed / n_before) else 0
  warnings <- list()
  if (pct > 5) warnings <- c(warnings, sprintf("%.1f%% of values removed as outliers", pct))
  list(step = "sensor_check", tier = 1L, status = if (removed > 0) "warning" else "ok",
       inputs_used = list(method = method),
       values = list(
         val("outliers_removed", "Outlier values removed", removed, "count"),
         val("outliers_removed_pct", "Share removed as outliers", pct, "%")),
       warnings = warnings, files = list())
}

tool_get_background <- function(p) {
  ensure_loaded()
  comp <- switch(pollutant, pm25 = "PM2.5", pm10 = "PM10", NA_character_)
  meta_csv <- file.path(data_dir, "reference_station_metadata.csv")
  ref_file <- file.path(data_dir, "reference_measurements.parquet")
  if (is.na(comp) || !file.exists(ref_file) || !file.exists(meta_csv)) {
    return(list(step = "background", tier = NULL, status = "not_available",
                inputs_used = list(source = if (!is.null(p$source)) p$source else "station"),
                values = list(),
                warnings = list("No background station available for this pollutant"),
                files = list()))
  }
  stations <- read.csv(meta_csv, stringsAsFactors = FALSE)
  bg <- stations[stations$stationstype == "achtergrond", ]
  area <- plan$area
  center_lat <- if (!is.null(area$lat)) area$lat else median(st$data$lat, na.rm = TRUE)
  center_lon <- if (!is.null(area$lon)) area$lon else median(st$data$lon, na.rm = TRUE)
  bg$dist <- haversine_km(center_lat, center_lon, bg$breedtegraad, bg$lengtegraad)
  bg <- bg[order(bg$dist), ]

  ref <- nanoparquet::read_parquet(ref_file)
  ref <- ref[ref$component == comp, ]
  ref$date <- as.POSIXct(substr(ref$begindatumtijd, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")

  chosen <- NA_character_; chosen_name <- NA_character_
  values <- list(); got <- FALSE
  for (i in seq_len(nrow(bg))) {
    sid <- bg$meetlocatie_id[i]
    sref <- ref[ref$meetlocatie_id == sid & !is.na(ref$waarde), ]
    if (nrow(sref) == 0) next
    per_vals <- list()
    ok <- TRUE
    for (per in st$periods) {
      sub <- sref[sref$date >= per$start & sref$date < per$end, ]
      if (nrow(sub) == 0) { ok <- FALSE; break }
      per_vals[[per$label]] <- round2(mean(sub$waarde, na.rm = TRUE))
    }
    if (!ok) next
    chosen <- sid; chosen_name <- bg$meetlocatie_naam[i]
    for (per in st$periods) {
      values[[length(values) + 1]] <- val(
        paste0("background_", slug(per$label)),
        paste0("Regional background (", chosen_name, ")"),
        per_vals[[per$label]], "\u00b5g/m\u00b3", per$label)
    }
    got <- TRUE
    break
  }

  if (!got) {
    return(list(step = "background", tier = NULL, status = "not_available",
                inputs_used = list(source = "station", component = comp),
                values = list(),
                warnings = list("No background station with data in these periods"),
                files = list()))
  }
  st$background <- values
  list(step = "background", tier = 1L, status = "ok",
       inputs_used = list(source = "station", component = comp,
                          station = chosen, station_name = chosen_name,
                          distance_km = round2(bg$dist[bg$meetlocatie_id == chosen][1])),
       values = values, warnings = list(), files = list())
}

tool_to_openair_format <- function(p) {
  ensure_loaded()
  df <- st$data[!is.na(st$data$value), ]
  oa <- data.frame(date = df$date, site = df$kit_id, stringsAsFactors = FALSE)
  oa[[pollutant]] <- df$value
  st$oa <- oa
  list(step = "analysis", tier = 1L, status = if (nrow(oa) > 0) "ok" else "warning",
       inputs_used = list(pollutant = pollutant),
       values = list(
         val("rows_openair", "Rows for openair", nrow(oa), "count"),
         val("sites_openair", "Sensors for openair", length(unique(oa$site)), "count")),
       warnings = list(), files = list())
}

# ---------------------------------------------------------------------------
# TIER 2 TOOLS (openair)
# ---------------------------------------------------------------------------

# Area daily series: openair::timeAverage per sensor to day, then the area mean.
build_area_daily <- function(min_hours) {
  suppressMessages(library(openair))
  oa <- st$oa
  thr <- max(0, min(100, round(100 * min_hours / 24)))
  sites <- unique(oa$site)
  daily <- lapply(sites, function(s) {
    d <- oa[oa$site == s, c("date", pollutant)]
    da <- suppressWarnings(timeAverage(d, avg.time = "day", data.thresh = thr))
    data.frame(date = da$date, value = da[[pollutant]], site = s, stringsAsFactors = FALSE)
  })
  daily <- bind_rows(daily)
  daily <- daily[!is.na(daily$value), ]
  area <- daily |>
    group_by(date) |>
    summarise(value = mean(value), n = n(), .groups = "drop")
  st$daily <- area
  st$daily_sites <- length(unique(daily$site))
  area
}

tool_average_over_time <- function(p) {
  ensure_loaded()
  if (is.null(st$oa)) tool_to_openair_format(NULL)
  avg_time <- if (!is.null(p$avg_time)) p$avg_time else "day"
  software <- paste("openair", as.character(packageVersion("openair")))

  if (avg_time == "day") {
    min_hours <- if (!is.null(p$min_hours)) p$min_hours else 18
    area <- build_area_daily(min_hours)
    csv <- file.path(out, "daily_area_values.csv")
    write.csv(area[, c("date", "value")], csv, row.names = FALSE)
    return(list(step = "analysis", tier = 2L, software = software, status = "ok",
                inputs_used = list(avg_time = "day", min_hours = min_hours),
                values = list(
                  val("sensors_used", "Sensors with enough daily data", st$daily_sites, "count"),
                  val("days_with_data", "Days with an area value", nrow(area), "count")),
                warnings = list(), files = list("daily_area_values.csv")))
  }

  # monthly (or per-period) summary built from the daily area series
  if (is.null(st$daily)) build_area_daily(18)
  stats <- if (!is.null(p$stats)) unlist(p$stats) else c("mean", "median")
  values <- list(); warnings <- list()
  means <- c()
  for (per in st$periods) {
    sub <- st$daily[st$daily$date >= per$start & st$daily$date < per$end, ]
    lab <- slug(per$label)
    if ("mean" %in% stats) {
      m <- round2(mean(sub$value))
      means[per$label] <- m
      values[[length(values) + 1]] <- val(paste0("mean_", lab),
        "Average of all days", m, "\u00b5g/m\u00b3", per$label)
    }
    if ("median" %in% stats) {
      values[[length(values) + 1]] <- val(paste0("median_", lab),
        "Typical day (median of daily values)", round2(median(sub$value)),
        "\u00b5g/m\u00b3", per$label)
    }
  }
  if ("mean" %in% stats && length(means) == 2) {
    diff <- round2(unname(means[2] - means[1]))
    values[[length(values) + 1]] <- val("mean_difference",
      sprintf("Change in average (%s minus %s)", names(means)[2], names(means)[1]),
      diff, "\u00b5g/m\u00b3")
    if ("median" %in% stats)
      warnings <- c(warnings, "Report both mean and median: peaks can pull the mean")
  }
  list(step = "analysis", tier = 2L, software = software, status = "ok",
       inputs_used = list(avg_time = avg_time, stats = as.list(stats)),
       values = values, warnings = warnings, files = list())
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
# Documented tools that are allowed but not yet implemented. These return a
# clear "not implemented yet" result instead of a hard "Tool not allowed"
# rejection, so a reader can tell "planned but unimplemented" from "forbidden".
not_impl <- function(step) function(p) list(
  step = step, status = "not_available",
  inputs_used = if (is.null(p)) setNames(list(), character()) else p,
  values = list(), warnings = list("not implemented yet"), files = list())

tools <- list(
  check_data_coverage     = tool_check_data_coverage,
  get_sensor_data         = tool_get_sensor_data,
  detect_faulty_sensors   = tool_detect_faulty_sensors,
  flag_high_humidity      = tool_flag_high_humidity,
  compare_with_neighbours = not_impl("sensor_check"),
  filter_outliers         = tool_filter_outliers,
  get_background          = tool_get_background,
  to_openair_format       = tool_to_openair_format,
  plot_over_time          = not_impl("analysis"),
  average_over_time       = tool_average_over_time
)

results <- list(
  run_id = plan$plan_id,
  data_source = list(name = "Hollandse Luchten sensor data",
                     file = "data_sensors.parquet", time_zone = "UTC"),
  steps = list())

for (step in plan$steps) {
  tool <- step$tool
  tier <- step$tier
  if (!tool %in% names(tools)) {
    log_step("rejected", tool, tier, "-", "REJECTED: tool not on the allowed list")
    stop("Tool not allowed: ", tool)
  }
  res <- tools[[tool]](step$params)
  res$tool <- tool
  if (is.null(res$tier)) res$tier <- if (is.null(tier)) NULL else as.integer(tier)
  if (is.null(res$software)) {
    res$software <- if (identical(res$tier, 2L)) "openair" else "Analyse-Together (adapted)"
  }
  results$steps[[length(results$steps) + 1]] <- res
  log_step(res$step, tool, res$tier, res$software, res$status)
}

write_json(results, file.path(out, "03_results.json"),
           auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 6)
writeLines(audit, file.path(out, "audit.jsonl"))
cat("Done:", length(plan$steps), "steps ->", file.path(out, "03_results.json"), "\n")
