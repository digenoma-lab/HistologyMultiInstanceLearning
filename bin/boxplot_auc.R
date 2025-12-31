#!/usr/bin/env Rscript

library(ggplot2)
library(readr)
library(dplyr)
library(stringr)

df <- read.csv("summary.csv")
p <- ggplot(df, aes(x = feature_extractor, y = test_auc, fill = mil)) +
  geom_boxplot() +
  theme_minimal() +
  ylim(0.5, 1) +
  labs(x = "Feature extractor", y = "ROC AUC", title = "Benchmark")

ggsave("boxplot.png", plot = p, width = 15, height = 6, dpi = 300)