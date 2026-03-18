library(readr)
library(dplyr)
library(randomForest)

# === extract_TH_LAGs_v5.R ===
# 79-genome dataset with 6-way lifestyle split
# Uses MEGAMATRIX.txt directly (4-part sample names) — no rename step needed
# New lifestyle labels: TH-Anaerobic, TH-Aerobic, MH-Anaerobic, MH-Aerobic,
#                       TP-Anaerobic, TP-Aerobic, Mesophile
# Changes from v4:
#   - Reads MEGAMATRIX.txt instead of MEGAMATRIX_renamed.txt
#   - Joins on 4-part sample IDs matching mapping_file.txt directly
#   - 79 genomes (41 TH, 13 MH, 16 TP, 8 Mesophile + 2 unmapped extras ignored)
#   - MH-Anaerobic / MH-Aerobic split added
#   - Output to ~/Desktop/Halophiles_Baclife_Project/v5/

OUTPUT_DIR <- "~/Desktop/Halophiles_Baclife_Project/v5"
dir.create(OUTPUT_DIR, recursive=TRUE, showWarnings=FALSE)

setwd("~/software/taxonomy_bundle/bacLIFE")

# ── Load data ─────────────────────────────────────────────────────────────────
cat("Loading MEGAMATRIX.txt...\n")
matrix  <- read_delim('MEGAMATRIX.txt', col_names=TRUE, quote='"',
                      show_col_types=FALSE)
mapping <- read.table('mapping_file.txt', header=TRUE, sep="\t")

# Strip quotes from column names if present
colnames(matrix) <- gsub('^"|"$', '', colnames(matrix))

cat("Matrix dimensions:", nrow(matrix), "clusters x", ncol(matrix), "columns\n")
cat("Mapping file entries:", nrow(mapping), "\n\n")

# ── Define lifestyle groups using 4-part sample IDs ──────────────────────────
# Only include samples that exist as columns in the matrix
get_cols <- function(lifestyle_vec) {
  s <- mapping$Sample[mapping$Lifestyle %in% lifestyle_vec]
  s[s %in% colnames(matrix)]
}

th_aero_cols  <- get_cols("TH-Aerobic")
th_anae_cols  <- get_cols("TH-Anaerobic")
th_cols       <- c(th_aero_cols, th_anae_cols)
mh_aero_cols  <- get_cols("MH-Aerobic")
mh_anae_cols  <- get_cols("MH-Anaerobic")
mh_cols       <- c(mh_aero_cols, mh_anae_cols)
tp_aero_cols  <- get_cols("TP-Aerobic")
tp_anae_cols  <- get_cols("TP-Anaerobic")
tp_cols       <- c(tp_aero_cols, tp_anae_cols)
mp_cols       <- get_cols("Mesophile")
all_mapped    <- c(th_cols, mh_cols, tp_cols, mp_cols)

cat("=== DATASET SUMMARY ===\n")
cat("Total gene clusters:", nrow(matrix), "\n")
cat("Group sizes:\n")
cat("  TH-Aerobic:      ", length(th_aero_cols), "\n")
cat("  TH-Anaerobic:    ", length(th_anae_cols), "\n")
cat("  Thermohalophiles:", length(th_cols), "\n")
cat("  MH-Aerobic:      ", length(mh_aero_cols), "\n")
cat("  MH-Anaerobic:    ", length(mh_anae_cols), "\n")
cat("  Meso-halophiles: ", length(mh_cols), "\n")
cat("  TP-Aerobic:      ", length(tp_aero_cols), "\n")
cat("  TP-Anaerobic:    ", length(tp_anae_cols), "\n")
cat("  Thermophiles:    ", length(tp_cols), "\n")
cat("  Mesophiles:      ", length(mp_cols), "\n")
cat("  Total mapped:    ", length(all_mapped), "\n\n")

# ── Filter to complete clusters only ─────────────────────────────────────────
if ("completeness" %in% colnames(matrix)) {
  matrix <- matrix %>% filter(completeness == TRUE)
  cat("After completeness filter:", nrow(matrix), "clusters\n")
}

# ── Helper: presence/absence per group ───────────────────────────────────────
group_freq <- function(mat, cols) {
  if (length(cols) == 0) return(rep(NA, nrow(mat)))
  sub <- mat[, cols, drop=FALSE]
  # Convert to numeric, treat >0 as present
  sub_num <- apply(sub, 2, function(x) as.numeric(x > 0))
  rowMeans(sub_num, na.rm=TRUE)
}

cat("Calculating group frequencies...\n")
matrix$freq_TH      <- group_freq(matrix, th_cols)
matrix$freq_TH_aero <- group_freq(matrix, th_aero_cols)
matrix$freq_TH_anae <- group_freq(matrix, th_anae_cols)
matrix$freq_MH      <- group_freq(matrix, mh_cols)
matrix$freq_MH_aero <- group_freq(matrix, mh_aero_cols)
matrix$freq_MH_anae <- group_freq(matrix, mh_anae_cols)
matrix$freq_TP      <- group_freq(matrix, tp_cols)
matrix$freq_TP_aero <- group_freq(matrix, tp_aero_cols)
matrix$freq_TP_anae <- group_freq(matrix, tp_anae_cols)
matrix$freq_MP      <- group_freq(matrix, mp_cols)

# ── Halophile enrichment score ────────────────────────────────────────────────
# How much more frequent in halophiles (TH+MH) vs non-halophiles (TP+MP)
matrix$freq_halo    <- group_freq(matrix, c(th_cols, mh_cols))
matrix$freq_nonhalo <- group_freq(matrix, c(tp_cols, mp_cols))
matrix$halo_enrichment <- matrix$freq_halo - matrix$freq_nonhalo

# Thermophile enrichment: TH+TP vs MH+MP
matrix$freq_thermo    <- group_freq(matrix, c(th_cols, tp_cols))
matrix$freq_nonthermo <- group_freq(matrix, c(mh_cols, mp_cols))
matrix$thermo_enrichment <- matrix$freq_thermo - matrix$freq_nonthermo

# ── TH-specific LAGs ──────────────────────────────────────────────────────────
# Criteria: freq_TH >= 0.75, enrichment vs all non-TH >= 0.3
non_th_cols <- c(mh_cols, tp_cols, mp_cols)
matrix$freq_nonTH <- group_freq(matrix, non_th_cols)
matrix$TH_enrichment <- matrix$freq_TH - matrix$freq_nonTH

cat("Filtering TH LAGs (freq_TH >= 0.75, enrichment >= 0.3)...\n")
TH_LAGs <- matrix %>%
  filter(freq_TH >= 0.75, TH_enrichment >= 0.3) %>%
  arrange(desc(TH_enrichment), desc(freq_TH))

cat("TH LAGs found:", nrow(TH_LAGs), "\n")

# ── TH-Anaerobic specific LAGs ────────────────────────────────────────────────
non_th_anae_cols <- c(th_aero_cols, mh_cols, tp_cols, mp_cols)
matrix$freq_nonTH_anae <- group_freq(matrix, non_th_anae_cols)
matrix$TH_anae_enrichment <- matrix$freq_TH_anae - matrix$freq_nonTH_anae

TH_anae_LAGs <- matrix %>%
  filter(freq_TH_anae >= 0.75, TH_anae_enrichment >= 0.3) %>%
  arrange(desc(TH_anae_enrichment), desc(freq_TH_anae))

cat("TH-Anaerobic specific LAGs:", nrow(TH_anae_LAGs), "\n")

# ── TH-Aerobic specific LAGs ─────────────────────────────────────────────────
non_th_aero_cols <- c(th_anae_cols, mh_cols, tp_cols, mp_cols)
matrix$freq_nonTH_aero <- group_freq(matrix, non_th_aero_cols)
matrix$TH_aero_enrichment <- matrix$freq_TH_aero - matrix$freq_nonTH_aero

TH_aero_LAGs <- matrix %>%
  filter(freq_TH_aero >= 0.75, TH_aero_enrichment >= 0.3) %>%
  arrange(desc(TH_aero_enrichment), desc(freq_TH_aero))

cat("TH-Aerobic specific LAGs:", nrow(TH_aero_LAGs), "\n")

# ── Halophile LAGs (TH + MH, not in TP or MP) ────────────────────────────────
Halo_LAGs <- matrix %>%
  filter(freq_halo >= 0.75, halo_enrichment >= 0.3) %>%
  arrange(desc(halo_enrichment), desc(freq_halo))

cat("Halophile LAGs (TH+MH enriched):", nrow(Halo_LAGs), "\n")

# ── Flag transposases ─────────────────────────────────────────────────────────
flag_transposase <- function(df) {
  df %>% mutate(
    is_transposase = grepl("transpos|IS[0-9]|insertion seq",
                           prokkadescription, ignore.case=TRUE)
  )
}

TH_LAGs      <- flag_transposase(TH_LAGs)
TH_anae_LAGs <- flag_transposase(TH_anae_LAGs)
TH_aero_LAGs <- flag_transposase(TH_aero_LAGs)
Halo_LAGs    <- flag_transposase(Halo_LAGs)

# ── Select output columns ─────────────────────────────────────────────────────
out_cols <- c("clusters", "freq_TH", "freq_TH_aero", "freq_TH_anae",
              "freq_MH", "freq_MH_aero", "freq_MH_anae",
              "freq_TP", "freq_TP_aero", "freq_TP_anae", "freq_MP",
              "TH_enrichment", "halo_enrichment", "thermo_enrichment",
              "is_transposase", "completeness",
              "gene", "keggid", "kegg_description",
              "cogid", "cog_description",
              "pfamid", "pfam_description",
              "dbcanid", "dbcan_description",
              "prokkadescription", "descriptions")

write_out <- function(df, fname) {
  df_out <- df %>% select(any_of(out_cols))
  write.csv(df_out, file.path(OUTPUT_DIR, fname), row.names=FALSE)
  cat("  Written:", fname, "(", nrow(df_out), "rows )\n")
}

cat("\n=== WRITING OUTPUTS ===\n")
write_out(TH_LAGs,       "TH_LAGs_v5.csv")
write_out(TH_anae_LAGs,  "TH_Anaerobic_LAGs_v5.csv")
write_out(TH_aero_LAGs,  "TH_Aerobic_LAGs_v5.csv")
write_out(Halo_LAGs,     "Halophile_LAGs_v5.csv")

# Full enriched matrix
write_out(matrix %>% select(any_of(out_cols)) %>%
            arrange(desc(TH_enrichment)),
          "MEGAMATRIX_enriched_v5.csv")

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
cat("\nTop 10 TH LAGs:\n")
print(TH_LAGs %>%
        filter(!is_transposase) %>%
        select(clusters, freq_TH, TH_enrichment, cogid, cog_description,
               prokkadescription) %>%
        head(10))
