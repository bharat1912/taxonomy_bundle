#!/bin/bash

# --- Color Definitions ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' 

echo -e "${YELLOW}=== Taxonomy Bundle: Database Health Check ===${NC}"
echo -e "Central Path: $PIXI_PROJECT_ROOT/db_link\n"

# --- Improved Robust Check Function ---
check_db_robust() {
    local db_name=$1
    shift # Shift to handle multiple potential anchor files
    local anchors=("$@")

    echo -n "Checking $db_name... "

    local found=false
    for anchor in "${anchors[@]}"; do
        if [[ -f "$anchor" || -d "$anchor" ]]; then
            found=true
            break
        fi
    done

    if [ $found = true ]; then
        echo -e "${GREEN}[OK] Verified (Material Present).${NC}"
    else
        # Show the primary expected anchor in the warning
        echo -e "${YELLOW}[WARNING] Anchor missing (Expected: $(basename "${anchors[0]}"))${NC}"
    fi
}

# --- Execute Checks ---
# We now pass multiple anchors for tools that have version differences.

# GTDB-Tk: Checking for the taxonomy file
check_db_robust "GTDB-Tk" "$GTDBTK_DATA_PATH/taxonomy/gtdb_taxonomy.tsv"

# Bakta: Check for Modern (manifest version)
# We also check both the root and the /db/ subfolder
check_db_robust "Bakta" \
    "$BAKTA_DB/version.json" \
    "$BAKTA_DB/db/version.json"    

check_db_robust "CheckM2"     "$CHECKM2_DB/CheckM2_database/uniref100.KO.1.dmnd"
check_db_robust "TaxonKit"    "$TAXONKIT_DB/names.dmp"

# MyTaxa: Checking for the specific .lib library files in the volume
check_db_robust "MyTaxa" \
    "$MYTAXA_DB/db/geneInfo.lib" \
    "$MYTAXA_DB/db/geneTaxon.lib" \
    "$MYTAXA_DB/AllGenomes.faa.dmnd"

# Krona: Checking for the presence of the taxonomy SQLite or text files
check_db_robust "Krona" \
    "$KRONA_DB/taxonomy.tab" \
    "$KRONA_DB/taxonomy.db"

#check_db_robust "Plassembler" "$PLASSEMBLER_DB/plsdb.fasta"
check_db_robust "Plassembler" \
    "$PLASSEMBLER_DB/plsdb_2023_11_03_v2.msh" \
    "$PLASSEMBLER_DB/plsdb.msh"

# BUSCO lineage check
check_db_robust "BUSCO"       "$BUSCO_LINEAGE_SETS/lineages"

# DFAST_QC: Using the large taxonomy database as the anchor for the 7810 Tower
check_db_robust "DFAST_QC" "db_link/dfast_qc_ref/ete3_taxonomy.db"

# Symclatron: Checking for the HMM profiles or the machine learning models folder
check_db_robust "Symclatron" \
    "$PIXI_PROJECT_ROOT/db_link/symclatron/uni56.hmm" \
    "$PIXI_PROJECT_ROOT/db_link/symclatron/ml_models" \
    "$PIXI_PROJECT_ROOT/db_link/symclatron/symclatron_2384_union_features.hmm"

# GToTree: Checking the internal Pixi 'share' folder for the Bacteria markers
GTT_INTERNAL="db_link/gtotree/Archaea.hmm"
check_db_robust "GToTree HMMs" "$GTT_INTERNAL"

# Prokka: Checking for the pressed HMM and CM indices
check_db_robust "Prokka" \
    "$PROKKA_DB/hmm/HAMAP.hmm.h3m" \
    "$PROKKA_DB/cm/Bacteria.i1m"

# eggNOG-mapper: Checking the main annotation database we just solidified
check_db_robust "eggNOG-mapper" \
    "$PIXI_PROJECT_ROOT/bacLIFE/databases/mapper_data/eggnog.db"

# antiSMASH: Updated anchor for version 8.0 structure
check_db_robust "antiSMASH" \
    "$PIXI_PROJECT_ROOT/db_link/antismash/pfam/35.0/Pfam-A.hmm"

# DRAM2: Core annotation databases
check_db_robust "DRAM2" \
    "$EXTERNAL_VAULT/dram_db/databases/db_descriptions" \
    "$EXTERNAL_VAULT/dram_db/databases/kofam" \
    "$EXTERNAL_VAULT/dram_db/databases/pfam"

# MiGA: Reference databases
check_db_robust "MiGA" \
    "$EXTERNAL_VAULT/miga_db/Phyla_Lite" \
    "$EXTERNAL_VAULT/miga_db/TypeMat_Lite"

# BMTagger: Human read removal
check_db_robust "BMTagger" "$EXTERNAL_VAULT/bmtagger/hg38.fa.gz"

# Kraken2: Taxonomic classification
check_db_robust "Kraken2" \
    "$EXTERNAL_VAULT/kraken2/hash.k2d" \
    "$EXTERNAL_VAULT/kraken2/opts.k2d"

# CompareM2: Genome comparison
check_db_robust "CompareM2-Bakta"    "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/bakta/comparem2_bakta_database_representative.flag"
check_db_robust "CompareM2-CheckM2"  "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/checkm2/comparem2_checkm2_database_representative.flag"
check_db_robust "CompareM2-EggNOG"   "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/eggnog/comparem2_eggnog_database_representative.flag"
check_db_robust "CompareM2-DBCan"    "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/dbcan/comparem2_dbcan_database_representative.flag"
check_db_robust "CompareM2-GTDB"     "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/gtdb/comparem2_gtdb_database_representative.flag"
check_db_robust "CompareM2-AntiSMASH" "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/antismash/comparem2_antismash_database_representative.flag"
check_db_robust "CompareM2-AMRFinder" "$EXTERNAL_VAULT/comparem2_db/cm2_v2.16/amrfinder/comparem2_amrfinder_database_representative.flag"

# GToTree: Phylogenetics HMM sets
check_db_robust "GToTree-HMMs" "$EXTERNAL_VAULT/gtotree/hmm_sets"

echo -e "\n${YELLOW}Health Check Complete.${NC}"
