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

# ── PERMANOVA: Lifestyle effect on gene content ───────────────────────────────
library(vegan)

cat("\n=== PERMANOVA: Lifestyle effect on gene content ===\n")

setwd("~/software/taxonomy_bundle/bacLIFE")

# Load MEGAMATRIX and mapping
matrix_raw <- read_delim('MEGAMATRIX.txt', col_names=TRUE, quote='"', show_col_types=FALSE)
mapping    <- read.table('mapping_file.txt', header=TRUE, sep="\t")
colnames(matrix_raw) <- gsub('^"|"$', '', colnames(matrix_raw))

# Get mapped genome columns only
meta_cols <- c("clusters","completeness","descriptions","gene",
               "keggid","kegg_description","cogid","cog_description",
               "pfamid","pfam_description","dbcanid","dbcan_description",
               "prokkadescription")
genome_cols  <- colnames(matrix_raw)[!colnames(matrix_raw) %in% meta_cols]
mapped_cols  <- genome_cols[genome_cols %in% mapping$Sample]
cat("Genomes included in PERMANOVA:", length(mapped_cols), "\n")

# Build binary presence/absence matrix (genomes as rows)
pa_matrix <- t(as.matrix(matrix_raw[, mapped_cols]))
pa_matrix[pa_matrix > 0] <- 1
pa_matrix <- apply(pa_matrix, 2, as.numeric)

# Match lifestyle labels
lifestyle_vec <- mapping$Lifestyle[match(mapped_cols, mapping$Sample)]
cat("Lifestyle breakdown:\n")
print(table(lifestyle_vec))

# Dice dissimilarity
cat("\nCalculating Dice dissimilarity matrix...\n")
dice_dist <- vegdist(pa_matrix, method="jaccard", binary=TRUE)

# Global PERMANOVA
cat("\nRunning global PERMANOVA (999 permutations)...\n")
set.seed(42)
perm_result <- adonis2(dice_dist ~ lifestyle_vec, permutations=999)
print(perm_result)

r2   <- perm_result$R2[1]
pval <- perm_result$`Pr(>F)`[1]
fstat <- perm_result$F[1]
cat(sprintf("\nSummary: R2=%.4f (%.1f%% variance), F=%.2f, p=%.4f %s\n",
    r2, r2*100, fstat, pval,
    ifelse(pval<0.001,"***",ifelse(pval<0.01,"**",ifelse(pval<0.05,"*","ns")))))

# Pairwise PERMANOVA
cat("\n=== Pairwise PERMANOVA: TH-Anaerobic vs other groups ===\n")
comparisons <- list(
  "TH-Anaerobic vs Mesophile"    = c("TH-Anaerobic","Mesophile"),
  "TH-Anaerobic vs TP-Anaerobic" = c("TH-Anaerobic","TP-Anaerobic"),
  "TH-Anaerobic vs MH-Aerobic"   = c("TH-Anaerobic","MH-Aerobic"),
  "TH-Anaerobic vs MH-Anaerobic" = c("TH-Anaerobic","MH-Anaerobic"),
  "TH-Anaerobic vs TH-Aerobic"   = c("TH-Anaerobic","TH-Aerobic"),
  "TH-Anaerobic vs TP-Aerobic"   = c("TH-Anaerobic","TP-Aerobic")
)

pw <- data.frame()
for (nm in names(comparisons)) {
  grps <- comparisons[[nm]]
  idx  <- lifestyle_vec %in% grps
  sub_dist <- as.dist(as.matrix(dice_dist)[idx, idx])
  sub_life <- lifestyle_vec[idx]
  set.seed(42)
  res <- adonis2(sub_dist ~ sub_life, permutations=999)
  pw <- rbind(pw, data.frame(
    Comparison = nm,
    n1 = sum(sub_life==grps[1]),
    n2 = sum(sub_life==grps[2]),
    R2 = round(res$R2[1],4),
    F  = round(res$F[1],2),
    p  = round(res$`Pr(>F)`[1],4),
    sig = ifelse(res$`Pr(>F)`[1]<0.001,"***",
          ifelse(res$`Pr(>F)`[1]<0.01,"**",
          ifelse(res$`Pr(>F)`[1]<0.05,"*","ns")))
  ))
}
print(pw)

# Betadisper — homogeneity of dispersions
cat("\n=== Betadisper: within-group dispersion ===\n")
bd <- betadisper(dice_dist, lifestyle_vec)
cat("Mean distance to centroid per group:\n")
print(round(bd$group.distances, 3))
print(permutest(bd, permutations=999))

# Save
write.csv(pw, file.path(OUTPUT_DIR, "PERMANOVA_pairwise_v5.csv"), row.names=FALSE)
cat("\nWritten: PERMANOVA_pairwise_v5.csv\n")
