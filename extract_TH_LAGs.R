library(readr)
library(dplyr)

# Load data
matrix <- read_delim('MEGAMATRIX_renamed.txt', col_names=T, quote='"')
mapping <- read.table('mapping_file.txt', header=T)

# Define lifestyle groups
thermohalophiles <- mapping$Sample[mapping$Lifestyle == "Thermohalophile"]
others <- mapping$Sample[mapping$Lifestyle != "Thermohalophile"]
thermophiles <- mapping$Sample[mapping$Lifestyle == "Thermophile"]
halophiles <- mapping$Sample[mapping$Lifestyle %in% c("Meso-halophile", "Extreme-Halophile-Bacterial", "Extreme-Halophile-Archaeal")]
mesophiles <- mapping$Sample[mapping$Lifestyle == "Mesophile"]

# Match to matrix columns
th_cols <- thermohalophiles[thermohalophiles %in% colnames(matrix)]
ot_cols <- others[others %in% colnames(matrix)]
tp_cols <- thermophiles[thermophiles %in% colnames(matrix)]
hp_cols <- halophiles[halophiles %in% colnames(matrix)]
mp_cols <- mesophiles[mesophiles %in% colnames(matrix)]

cat("Group sizes:\n")
cat("  Thermohalophiles:", length(th_cols), "\n")
cat("  Thermophiles:", length(tp_cols), "\n")
cat("  Halophiles:", length(hp_cols), "\n")
cat("  Mesophiles:", length(mp_cols), "\n\n")

# Calculate presence frequencies per group for each gene cluster
results <- matrix %>%
  rowwise() %>%
  mutate(
    TH_freq   = mean(c_across(all_of(th_cols)), na.rm=T),
    TP_freq   = mean(c_across(all_of(tp_cols)), na.rm=T),
    HP_freq   = mean(c_across(all_of(hp_cols)), na.rm=T),
    MP_freq   = mean(c_across(all_of(mp_cols)), na.rm=T),
    Other_freq = mean(c_across(all_of(ot_cols)), na.rm=T),
    TH_enrichment = TH_freq - Other_freq,
    # Shared with thermophiles but not halophiles = temperature signal
    TH_TP_shared = TH_freq >= 0.67 & TP_freq >= 0.5 & HP_freq < 0.3,
    # Shared with halophiles but not thermophiles = salt signal  
    TH_HP_shared = TH_freq >= 0.67 & HP_freq >= 0.5 & TP_freq < 0.3,
    # Unique to thermohalophiles = dual stress signal
    TH_unique = TH_freq >= 0.67 & TP_freq < 0.3 & HP_freq < 0.3 & MP_freq < 0.3
  ) %>%
  ungroup() %>%
  select(clusters, descriptions, gene, keggid, kegg_description,
         cogid, cog_description, pfamid, pfam_description,
         TH_freq, TP_freq, HP_freq, MP_freq, Other_freq, 
         TH_enrichment, TH_TP_shared, TH_HP_shared, TH_unique,
         completeness) %>%
  arrange(desc(TH_enrichment))

# Filter sets
TH_enriched <- results %>% filter(TH_freq >= 0.67, TH_enrichment >= 0.3)
TH_unique   <- results %>% filter(TH_unique == TRUE)
TH_TP       <- results %>% filter(TH_TP_shared == TRUE)
TH_HP       <- results %>% filter(TH_HP_shared == TRUE)

cat("=== SUMMARY ===\n")
cat("Total gene clusters:", nrow(matrix), "\n")
cat("TH-enriched (>=4/6 TH, enrichment>=0.3):", nrow(TH_enriched), "\n")
cat("TH-unique (not in TP/HP/MP):", nrow(TH_unique), "\n")
cat("TH+TP shared (temperature signal):", nrow(TH_TP), "\n")
cat("TH+HP shared (salt signal):", nrow(TH_HP), "\n\n")

cat("=== TOP 20 TH-ENRICHED LAGs ===\n")
print(TH_enriched %>% 
  select(clusters, gene, kegg_description, cog_description, 
         TH_freq, TP_freq, HP_freq, MP_freq, TH_enrichment) %>% 
  head(20), n=20, width=120)

cat("\n=== TH-UNIQUE LAGs (dual stress candidates) ===\n")
print(TH_unique %>%
  select(clusters, gene, kegg_description, cog_description,
         TH_freq, TP_freq, HP_freq, MP_freq) %>%
  head(20), n=20, width=120)

cat("\n=== TH+TP SHARED (temperature adaptation) ===\n")
print(TH_TP %>%
  select(clusters, gene, kegg_description, cog_description,
         TH_freq, TP_freq, HP_freq) %>%
  head(20), n=20, width=120)

cat("\n=== TH+HP SHARED (salt adaptation) ===\n")
print(TH_HP %>%
  select(clusters, gene, kegg_description, cog_description,
         TH_freq, HP_freq, TP_freq) %>%
  head(20), n=20, width=120)

# Save all output files
write.csv(TH_enriched, 'TH_LAGs_enriched.csv', row.names=F)
write.csv(TH_unique,   'TH_LAGs_unique.csv', row.names=F)
write.csv(TH_TP,       'TH_LAGs_temperature_signal.csv', row.names=F)
write.csv(TH_HP,       'TH_LAGs_salt_signal.csv', row.names=F)
write.csv(results,     'all_clusters_ranked.csv', row.names=F)

cat("\nSaved:\n")
cat("  TH_LAGs_enriched.csv\n")
cat("  TH_LAGs_unique.csv\n")
cat("  TH_LAGs_temperature_signal.csv\n")
cat("  TH_LAGs_salt_signal.csv\n")
cat("  all_clusters_ranked.csv\n")
