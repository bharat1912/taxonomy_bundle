# ============================================================
# TH_LAG_summary_v5.R
# Generates publication-ready summary tables and figures
# from extract_TH_LAGs_v5.R results
#
# Usage:
#   pixi run -e env-baclife Rscript TH_LAG_summary_v5.R
# ============================================================

library(readr)
library(dplyr)

OUTPUT_DIR <- "~/Desktop/Halophiles_Baclife_Project/v5"
dir.create(OUTPUT_DIR, recursive=TRUE, showWarnings=FALSE)

# ── Load results ──────────────────────────────────────────────────────────────
th     <- read_csv(file.path(OUTPUT_DIR, "TH_LAGs_v5.csv"),          show_col_types=FALSE)
th_an  <- read_csv(file.path(OUTPUT_DIR, "TH_Anaerobic_LAGs_v5.csv"),show_col_types=FALSE)
th_ae  <- read_csv(file.path(OUTPUT_DIR, "TH_Aerobic_LAGs_v5.csv"),  show_col_types=FALSE)
halo   <- read_csv(file.path(OUTPUT_DIR, "Halophile_LAGs_v5.csv"),   show_col_types=FALSE)
matrix <- read_csv(file.path(OUTPUT_DIR, "MEGAMATRIX_enriched_v5.csv"), show_col_types=FALSE)

cat("=== bacLIFE v5 Analysis Summary (79 genomes) ===\n\n")
cat("Dataset:\n")
cat("  TH-Anaerobic: 36 | TH-Aerobic: 5 | Total TH: 41\n")
cat("  MH-Anaerobic:  3 | MH-Aerobic:10 | Total MH: 13\n")
cat("  TP-Anaerobic: 10 | TP-Aerobic: 7 | Total TP: 17\n")
cat("  Mesophile:     8\n")
cat("  Total:        79\n\n")

cat("LAG counts:\n")
cat("  TH LAGs (freq>=0.75, enrich>=0.3):         ", nrow(th),    "\n")
cat("  TH-Anaerobic specific LAGs:                ", nrow(th_an), "\n")
cat("  TH-Aerobic specific LAGs:                  ", nrow(th_ae), "\n")
cat("  Halophile LAGs (TH+MH enriched):           ", nrow(halo),  "\n\n")

# ── Rnf complex summary ───────────────────────────────────────────────────────
rnf_clusters <- matrix %>%
  filter(grepl("ion-translocat|rnf", prokkadescription, ignore.case=TRUE) |
         grepl("COG1860|COG1971|COG2273|COG2878", cogid, ignore.case=TRUE)) %>%
  select(clusters, freq_TH, freq_TH_anae, freq_TH_aero,
         freq_MH, freq_TP, freq_MP,
         TH_enrichment, cogid, prokkadescription) %>%
  arrange(desc(freq_TH_anae))

cat("=== Rnf Complex Clusters ===\n")
print(rnf_clusters %>% select(clusters, freq_TH, freq_TH_anae,
                               freq_MH, freq_TP, TH_enrichment,
                               prokkadescription))

# ── Top TH LAGs table ─────────────────────────────────────────────────────────
cat("\n=== Top TH LAGs (non-transposase) ===\n")
top_th <- th %>%
  filter(!is_transposase) %>%
  arrange(desc(TH_enrichment)) %>%
  select(clusters, freq_TH, freq_TH_anae, freq_TH_aero,
         freq_MH, freq_TP, freq_MP,
         TH_enrichment, cogid, cog_description, prokkadescription) %>%
  head(20)
print(top_th, width=120)

# ── Halophile LAGs table ──────────────────────────────────────────────────────
cat("\n=== Halophile LAGs (TH+MH enriched, not TP/MP) ===\n")
print(halo %>%
  select(clusters, freq_TH, freq_MH, freq_TP, freq_MP,
         halo_enrichment, cogid, cog_description, prokkadescription),
  width=120)

# ── Write clean summary CSV ───────────────────────────────────────────────────
summary_cols <- c("clusters","freq_TH","freq_TH_anae","freq_TH_aero",
                  "freq_MH","freq_TP","freq_MP",
                  "TH_enrichment","halo_enrichment","thermo_enrichment",
                  "is_transposase","cogid","cog_description",
                  "keggid","kegg_description",
                  "pfamid","pfam_description","prokkadescription")

write_csv(th    %>% select(any_of(summary_cols)),
          file.path(OUTPUT_DIR, "TH_LAGs_v5_clean.csv"))
write_csv(th_an %>% select(any_of(summary_cols)),
          file.path(OUTPUT_DIR, "TH_Anaerobic_LAGs_v5_clean.csv"))
write_csv(halo  %>% select(any_of(summary_cols)),
          file.path(OUTPUT_DIR, "Halophile_LAGs_v5_clean.csv"))
write_csv(rnf_clusters,
          file.path(OUTPUT_DIR, "Rnf_clusters_v5.csv"))

cat("\nFiles written to:", OUTPUT_DIR, "\n")
cat("  TH_LAGs_v5_clean.csv\n")
cat("  TH_Anaerobic_LAGs_v5_clean.csv\n")
cat("  Halophile_LAGs_v5_clean.csv\n")
cat("  Rnf_clusters_v5.csv\n")
