library(stringr)
library(readr)

# rename_MEGAMATRIX_v2.R
# Fixed version:
# 1. Writes generated mapping to mapping_file_baclife_generated.txt (NOT mapping_file.txt)
# 2. Handles genomes NOT in names_equivalence.txt gracefully (keeps 4-part name)
# 3. mapping_file.txt is preserved — user manages lifestyles there

args = commandArgs(trailingOnly=TRUE)
matrix            <- read_delim(args[1], col_names=TRUE, quote="\"", show_col_types=FALSE)
matrix            <- as.data.frame(matrix)
names_equivalence <- read.table(args[3], header=TRUE)

# Strip _O.fna suffix if present (legacy compatibility)
names_equivalence$Full_name    <- str_remove(names_equivalence$Full_name,    '_O\\.fna$')
names_equivalence$bacLIFE_name <- str_remove(names_equivalence$bacLIFE_name, '_O\\.fna$')

n_samples    <- grep("completeness", colnames(matrix)) - 1
old_colnames <- data.frame(bacLIFE_name = colnames(matrix)[2:n_samples])

# FIX 1: Left join — keep original 4-part name if not in equivalence table
M <- merge(old_colnames, names_equivalence, by='bacLIFE_name', all.x=TRUE)
M <- M[match(old_colnames$bacLIFE_name, M$bacLIFE_name), ]

# Where Full_name is NA (new genomes not yet in equivalence table), keep bacLIFE_name
M$Full_name <- ifelse(is.na(M$Full_name), M$bacLIFE_name, M$Full_name)

# Report any unmapped genomes
unmapped <- M$bacLIFE_name[M$Full_name == M$bacLIFE_name]
if (length(unmapped) > 0) {
  message("NOTE: ", length(unmapped), " genome(s) not in names_equivalence.txt — kept as-is:")
  message(paste(" ", unmapped, collapse="\n"))
  message("Add them to names_equivalence.txt for full renaming.")
}

colnames(matrix)[2:n_samples] <- M$Full_name
write.table(matrix, args[4], row.names=FALSE)

# Rename BiG-SCAPE table
big_scape_matrix  <- read.table(args[2], header=TRUE)
old_bs_colnames   <- data.frame(bacLIFE_name = colnames(big_scape_matrix))
M2 <- merge(old_bs_colnames, names_equivalence, by='bacLIFE_name', all.x=TRUE)
M2 <- M2[match(old_bs_colnames$bacLIFE_name, M2$bacLIFE_name), ]
M2$Full_name <- ifelse(is.na(M2$Full_name), M2$bacLIFE_name, M2$Full_name)
colnames(big_scape_matrix) <- M2$Full_name
write.table(big_scape_matrix, args[5], row.names=TRUE)

# FIX 2: Write generated mapping to mapping_file_baclife_generated.txt ONLY
# DO NOT overwrite mapping_file.txt — user manages lifestyles there
mapping_file <- data.frame(Sample=M$Full_name, Lifestyle='Unknown')
write.table(mapping_file, args[6], row.names=FALSE, quote=TRUE)
message("NOTE: Generated mapping written to ", args[6])
message("      mapping_file.txt was NOT modified — edit it directly to set lifestyles.")
