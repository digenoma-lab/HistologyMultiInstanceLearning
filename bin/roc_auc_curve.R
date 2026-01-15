#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ggplot2)
  library(readr)
})

compute_roc <- function(y_true, y_score, n_thresholds = 100L) {
  # thresholds from 0 to 1
  ts <- seq(0, 1, length.out = n_thresholds)

  tpr <- numeric(length(ts))
  fpr <- numeric(length(ts))

  for (i in seq_along(ts)) {
    thr <- ts[i]
    y_pred <- ifelse(y_score >= thr, 1L, 0L)

    tp <- sum(y_true == 1L & y_pred == 1L)
    fp <- sum(y_true == 0L & y_pred == 1L)
    fn <- sum(y_true == 1L & y_pred == 0L)
    tn <- sum(y_true == 0L & y_pred == 0L)

    tpr[i] <- if ((tp + fn) > 0) tp / (tp + fn) else 0
    fpr[i] <- if ((fp + tn) > 0) fp / (fp + tn) else 0
  }

  data.frame(fpr = fpr, tpr = tpr)
}

compute_auc <- function(roc_df) {
  # trapezoidal rule, sort by fpr
  roc_df <- roc_df[order(roc_df$fpr), ]
  x <- roc_df$fpr
  y <- roc_df$tpr
  sum((x[-1] - x[-length(x)]) * (y[-1] + y[-length(y)]) / 2)
}

compute_roc_and_auc <- function(df) {
  if (!all(c("y_true", "y_pred") %in% colnames(df))) {
    stop("Expected columns y_true and y_pred in input CSV.", call. = FALSE)
  }

  y_true <- as.integer(df$y_true)
  y_score <- as.numeric(df$y_pred)

  roc_df <- compute_roc(y_true, y_score)
  auc <- compute_auc(roc_df)

  list(roc_df = roc_df, auc = auc)
}

roc_plot_combined <- function(roc_data_list, output_path = "roc_curve.png", title = "ROC Curves") {
  # Combine all ROC data with labels
  all_roc_data <- data.frame()
  
  for (i in seq_along(roc_data_list)) {
    roc_df <- roc_data_list[[i]]$roc_df
    auc <- roc_data_list[[i]]$auc
    label <- roc_data_list[[i]]$label
    
    roc_df$fold <- sprintf("%s (AUC = %.3f)", label, auc)
    all_roc_data <- rbind(all_roc_data, roc_df)
  }

  # Generate color palette
  n_folds <- length(roc_data_list)
  colors <- rainbow(n_folds)
  
  p <- ggplot(all_roc_data, aes(x = fpr, y = tpr, color = fold)) +
    geom_line(size = 1) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
    coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
    scale_color_manual(values = colors, name = "Fold") +
    labs(
      x = "False Positive Rate",
      y = "True Positive Rate",
      title = title
    ) +
    theme_minimal() +
    theme(
      legend.position = "right",
      legend.title = element_text(size = 10),
      legend.text = element_text(size = 9)
    )

  ggsave(output_path, plot = p, width = 8, height = 6, dpi = 300)
  message(sprintf("Generated combined ROC curve: %s", output_path))
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript roc_auc_curve.R <test_predictions1.csv> [test_predictions2.csv ...] [output_path]", call. = FALSE)
  }

  # Check if last argument is output path (not ending with .csv)
  output_path <- NULL
  csv_files <- args
  
  # If last argument doesn't end with .csv, treat it as output path
  if (length(args) > 1 && !grepl("\\.csv$", args[length(args)], ignore.case = TRUE)) {
    output_path <- args[length(args)]
    csv_files <- args[-length(args)]
  }

  # If no output path specified, use default
  if (is.null(output_path)) {
    output_path <- "roc_auc.png"
  }

  # Process all CSV files and collect ROC data
  roc_data_list <- list()
  
  for (csv_file in csv_files) {
    if (!file.exists(csv_file)) {
      warning(sprintf("File not found: %s, skipping...", csv_file))
      next
    }

    # Read and process
    df <- read_csv(csv_file, show_col_types = FALSE)
    base_name <- tools::file_path_sans_ext(basename(csv_file))
    
    # Extract fold number if present in filename (e.g., predictions_0.csv -> Fold 0)
    fold_match <- regmatches(base_name, regexpr("_\\d+$", base_name))
    if (length(fold_match) > 0) {
      fold_num <- gsub("_", "", fold_match)
      label <- paste0("Fold ", fold_num)
    } else {
      label <- base_name
    }
    
    roc_data <- compute_roc_and_auc(df)
    roc_data$label <- label
    roc_data_list[[length(roc_data_list) + 1]] <- roc_data
    
    message(sprintf("Processed %s: AUC = %.3f", csv_file, roc_data$auc))
  }

  if (length(roc_data_list) == 0) {
    stop("No valid CSV files found to process.", call. = FALSE)
  }

  # Generate combined plot
  roc_plot_combined(roc_data_list, output_path)
}

if (identical(environment(), globalenv())) {
  main()
}


