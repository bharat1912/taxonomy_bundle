# ============================================================
# extract_osmolyte_LAGs_v1.R
# Osmolyte strategy LAG analysis for thermohalophile dataset
#
# Groups genomes by osmolyte strategy (Salt-in vs Salt-out vs Hybrid)
# rather than by lifestyle, cutting across phylogeny and temperature
# to isolate genes specifically associated with osmotic adaptation mechanism.
#
# Dataset: 79 bacterial genomes
#   Salt-in:   6 genomes (Haloanaerobiales + Salinibacter ruber)
#   Salt-out: 68 genomes (Thermotogales, Aquificae, Proteobacteria etc.)
#   Hybrid:    2 genomes (Natranaerobius spp.)
#   Unknown:   3 genomes (excluded from main analysis)
#
# Usage:
#   cd ~/software/taxonomy_bundle/bacLIFE
#   pixi run -e env-baclife Rscript extract_osmolyte_LAGs_v1.R
# ============================================================

library(readr)
library(dplyr)
library(vegan)

OUTPUT_DIR <- "~/Desktop/Halophiles_Baclife_Project/v5/osmolyte_analysis"
dir.create(OUTPUT_DIR, recursive=TRUE, showWarnings=FALSE)

setwd("~/software/taxonomy_bundle/bacLIFE")

cat("=== Osmolyte Strategy LAG Analysis v1 ===\n\n")

# ── Load MEGAMATRIX and metadata ──────────────────────────────────────────────
cat("Loading MEGAMATRIX.txt...\n")
matrix <- read_delim('MEGAMATRIX.txt', col_names=TRUE, quote='"',
                     show_col_types=FALSE)
colnames(matrix) <- gsub('^"|"$', '', colnames(matrix))

# Load metadata with osmolyte strategy
meta_file <- "~/Desktop/Halophiles_Baclife_Project/v5/metadata_traits_v2.txt"
metadata  <- read.table(meta_file, header=TRUE, sep="\t", quote='"')
cat("Metadata loaded:", nrow(metadata), "genomes\n")

# ── Extract osmolyte strategy from metadata ───────────────────────────────────
# Simplify to Salt-in / Salt-out / Hybrid
metadata$osmolyte_simple <- case_when(
  grepl("^Salt-in",  metadata$Osmolyte_strategy) ~ "Salt-in",
  grepl("^Salt-out", metadata$Osmolyte_strategy) ~ "Salt-out",
  grepl("^Hybrid",   metadata$Osmolyte_strategy) ~ "Salt-in",  # Hybrid -> Salt-in (primary strategy)
  TRUE ~ "Unknown"
)

# Sample IDs in metadata use 4-part names (_O suffix)
# MEGAMATRIX uses 3-part names — strip _O suffix for matching
metadata$Sample_3part <- sub("_O$", "", metadata$Sample)

cat("\nOsmolyte strategy counts:\n")
print(table(metadata$osmolyte_simple))

# ── Match metadata to MEGAMATRIX columns ─────────────────────────────────────
meta_cols <- c("clusters","completeness","descriptions","gene",
               "keggid","kegg_description","cogid","cog_description",
               "pfamid","pfam_description","dbcanid","dbcan_description",
               "prokkadescription")
genome_cols <- colnames(matrix)[!colnames(matrix) %in% meta_cols]

# Match MEGAMATRIX column names to metadata Sample_3part
get_cols <- function(strategy) {
  samples <- metadata$Sample_3part[metadata$osmolyte_simple == strategy]
  cols <- samples[samples %in% genome_cols]
  cat(sprintf("  %s: %d/%d genomes matched in MEGAMATRIX\n",
              strategy, length(cols), length(samples)))
  cols
}

cat("\nMatching genomes to MEGAMATRIX columns:\n")
salt_in_cols  <- get_cols("Salt-in")
salt_out_cols <- get_cols("Salt-out")
hybrid_cols   <- get_cols("Hybrid")
all_cols      <- c(salt_in_cols, salt_out_cols, hybrid_cols)

cat(sprintf("\nTotal genomes in analysis: %d\n", length(all_cols)))
cat(sprintf("  Salt-in:  %d\n", length(salt_in_cols)))
cat(sprintf("  Salt-out: %d\n", length(salt_out_cols)))
cat(sprintf("  Hybrid:   %d\n", length(hybrid_cols)))

# ── Completeness filter ───────────────────────────────────────────────────────
if ("completeness" %in% colnames(matrix)) {
  matrix <- matrix %>% filter(completeness == TRUE)
  cat(sprintf("\nAfter completeness filter: %d clusters\n", nrow(matrix)))
}

# ── Helper: frequency per group ───────────────────────────────────────────────
group_freq <- function(mat, cols) {
  if (length(cols) == 0) return(rep(NA_real_, nrow(mat)))
  sub <- mat[, cols, drop=FALSE]
  sub_num <- apply(sub, 2, function(x) as.numeric(x > 0))
  rowMeans(sub_num, na.rm=TRUE)
}

cat("\nCalculating group frequencies...\n")
matrix$freq_salt_in   <- group_freq(matrix, salt_in_cols)
matrix$freq_salt_out  <- group_freq(matrix, salt_out_cols)
matrix$freq_hybrid    <- group_freq(matrix, hybrid_cols)

# Enrichment: salt-in vs salt-out (the key comparison)
matrix$salt_in_enrichment  <- matrix$freq_salt_in  - matrix$freq_salt_out
matrix$salt_out_enrichment <- matrix$freq_salt_out - matrix$freq_salt_in

# ── Flag transposases ─────────────────────────────────────────────────────────
matrix <- matrix %>% mutate(
  is_transposase = grepl("transpos|IS[0-9]|insertion seq",
                         prokkadescription, ignore.case=TRUE)
)

# ── Salt-in LAGs ──────────────────────────────────────────────────────────────
# Genes enriched in salt-in organisms vs salt-out
# Lower threshold due to small salt-in group (n=6)
cat("\n=== Salt-in LAGs (freq_salt_in >= 0.67, enrichment >= 0.30) ===\n")
salt_in_LAGs <- matrix %>%
  filter(freq_salt_in >= 0.67,        # >=4/6 genomes
         salt_in_enrichment >= 0.30,
         !is_transposase) %>%
  arrange(desc(salt_in_enrichment), desc(freq_salt_in))
cat(sprintf("Salt-in LAGs found: %d\n", nrow(salt_in_LAGs)))

# ── Salt-out LAGs ─────────────────────────────────────────────────────────────
cat("\n=== Salt-out LAGs (freq_salt_out >= 0.75, enrichment >= 0.30) ===\n")
salt_out_LAGs <- matrix %>%
  filter(freq_salt_out >= 0.75,
         salt_out_enrichment >= 0.30,
         !is_transposase) %>%
  arrange(desc(salt_out_enrichment), desc(freq_salt_out))
cat(sprintf("Salt-out LAGs found: %d\n", nrow(salt_out_LAGs)))

# ── Universal halophile genes (present in both salt-in AND salt-out) ──────────
cat("\n=== Universal halophile genes (freq_salt_in >= 0.67 AND freq_salt_out >= 0.75) ===\n")
universal_halo <- matrix %>%
  filter(freq_salt_in  >= 0.67,
         freq_salt_out >= 0.75,
         !is_transposase) %>%
  arrange(desc(freq_salt_in + freq_salt_out))
cat(sprintf("Universal halophile genes: %d\n", nrow(universal_halo)))

# ── PERMANOVA: salt-in vs salt-out ───────────────────────────────────────────
cat("\n=== PERMANOVA: Salt-in vs Salt-out ===\n")
pa_cols     <- c(salt_in_cols, salt_out_cols)
pa_matrix   <- t(as.matrix(matrix[, pa_cols]))
pa_matrix[pa_matrix > 0] <- 1
pa_matrix   <- apply(pa_matrix, 2, as.numeric)
strategy_vec <- c(rep("Salt-in", length(salt_in_cols)),
                  rep("Salt-out", length(salt_out_cols)))

dice_dist <- vegdist(pa_matrix, method="jaccard", binary=TRUE)
set.seed(42)
perm <- adonis2(dice_dist ~ strategy_vec, permutations=999)
print(perm)
cat(sprintf("\nR2=%.4f, F=%.2f, p=%.4f %s\n",
    perm$R2[1], perm$F[1], perm$`Pr(>F)`[1],
    ifelse(perm$`Pr(>F)`[1]<0.001,"***",
    ifelse(perm$`Pr(>F)`[1]<0.01,"**",
    ifelse(perm$`Pr(>F)`[1]<0.05,"*","ns")))))

# ── Output columns ────────────────────────────────────────────────────────────
out_cols <- c("clusters","freq_salt_in","freq_salt_out","freq_hybrid",
              "salt_in_enrichment","salt_out_enrichment",
              "is_transposase","completeness",
              "gene","keggid","kegg_description",
              "cogid","cog_description",
              "pfamid","pfam_description",
              "prokkadescription","descriptions")

write_out <- function(df, fname) {
  df_out <- df %>% select(any_of(out_cols))
  write.csv(df_out, file.path(OUTPUT_DIR, fname), row.names=FALSE)
  cat(sprintf("  Written: %s (%d rows)\n", fname, nrow(df_out)))
}

cat("\n=== WRITING OUTPUTS ===\n")
write_out(salt_in_LAGs,    "Salt_in_LAGs_v1.csv")
write_out(salt_out_LAGs,   "Salt_out_LAGs_v1.csv")
write_out(universal_halo,  "Universal_halophile_genes_v1.csv")

# Also write full enriched matrix
matrix %>%
  select(any_of(out_cols)) %>%
  arrange(desc(salt_in_enrichment)) %>%
  write.csv(file.path(OUTPUT_DIR, "MEGAMATRIX_osmolyte_enriched_v1.csv"),
            row.names=FALSE)
cat("  Written: MEGAMATRIX_osmolyte_enriched_v1.csv (47744 rows)\n")

# ── Top results summary ───────────────────────────────────────────────────────
cat("\n=== Top 10 Salt-in LAGs ===\n")
print(salt_in_LAGs %>%
  select(clusters, freq_salt_in, freq_salt_out, salt_in_enrichment,
         cogid, cog_description, prokkadescription) %>%
  head(10), width=120)

cat("\n=== Top 10 Salt-out LAGs ===\n")
print(salt_out_LAGs %>%
  select(clusters, freq_salt_out, freq_salt_in, salt_out_enrichment,
         cogid, cog_description, prokkadescription) %>%
  head(10), width=120)

cat("\n=== Universal halophile genes (top 10) ===\n")
print(universal_halo %>%
  select(clusters, freq_salt_in, freq_salt_out,
         cogid, cog_description, prokkadescription) %>%
  head(10), width=120)

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
