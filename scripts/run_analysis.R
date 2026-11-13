# Executes an analysis plan (02_plan.json, schemas/plan.schema.json) and writes
# 03_results.json (schemas/results.schema.json) + audit.jsonl.
# STUB: each tool below must be connected to the real Samen Analyseren (Tier 1)
# or openair (Tier 2) function. Until then a tool records "not implemented".
#
# Usage: Rscript scripts/run_analysis.R plan.json out

suppressMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
plan <- fromJSON(args[1], simplifyVector = FALSE)
out  <- args[2]
dir.create(out, showWarnings = FALSE, recursive = TRUE)

audit <- character()
log_step <- function(step, tool, tier, software, detail) {
  audit <<- c(audit, toJSON(list(run_id = plan$plan_id,
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    step = step, tool = tool, tier = tier, software = software, detail = detail),
    auto_unbox = TRUE, null = "null"))
}

# Allowed tools: name -> function(params, state).
# Each must return one results step: list(step, tool, tier, software, status,
# inputs_used, values = list(list(id, label, value, unit, period)), warnings, files).
# Fill these in with real Samen Analyseren / openair calls.
not_impl <- function(step) function(p, s) list(step = step, status = "not_available",
  inputs_used = if (is.null(p)) setNames(list(), character()) else p,
  values = list(), warnings = list("not implemented yet"), files = list())
tools <- list(
  check_data_coverage     = not_impl("data_check"),
  get_sensor_data         = not_impl("data_check"),
  detect_faulty_sensors   = not_impl("sensor_check"),
  flag_high_humidity      = not_impl("sensor_check"),
  compare_with_neighbours = not_impl("sensor_check"),
  filter_outliers         = not_impl("sensor_check"),
  get_background          = not_impl("background"),
  to_openair_format       = not_impl("analysis"),
  plot_over_time          = not_impl("analysis"),
  average_over_time       = not_impl("analysis")
)

results <- list(run_id = plan$plan_id,
  data_source = list(name = "Hollandse Luchten sensor data", file = "data_sensors.parquet", time_zone = "UTC"),
  steps = list())
state <- list()
for (step in plan$steps) {
  tool <- step$tool
  tier <- step$tier
  software <- if (identical(tier, 2L) || identical(tier, 2)) "openair [version]" else "Analyse-Together [commit]"
  if (!tool %in% names(tools)) {
    log_step("rejected", tool, tier, "-", "REJECTED: tool not on the allowed list")
    stop("Tool not allowed: ", tool)
  }
  res <- tools[[tool]](step$params, state)
  res$tool <- tool; res$tier <- tier; res$software <- software
  results$steps[[length(results$steps) + 1]] <- res
  log_step(res$step, tool, tier, software, res$status)
}

write_json(results, file.path(out, "03_results.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
writeLines(audit, file.path(out, "audit.jsonl"))
cat("Done:", length(plan$steps), "steps\n")
