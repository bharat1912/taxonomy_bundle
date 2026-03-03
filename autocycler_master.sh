#!/bin/bash

# ==============================================================================
# Autocycler Master Pipeline Script (Combined)
# Downloads, subsamples, assembles, compresses, clusters, and resolves.
#
# This script integrates all four components provided, adding stage-based checks
# to ensure it can resume from a previous failure point or skip completed steps.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- CONFIGURATION (Single Source of Truth) ---

# !!! REQUIRED USER INPUT !!!
# 1. NCBI/ENA SRA Accession (e.g., SRR35175383)
#SRA_ACCESSION="SRR32486273" # <-- CHANGE THIS
SRA_ACCESSION="SRR5413256" # <-- CHANGE THIS

# 2. Genus Name (e.g., Gardnerella)
#GENUS_NAME="Listeria" # <-- CHANGE THIS
GENUS_NAME="Helicobacter" # <-- CHANGE THIS

# 3. Sequencing Technology Tag (e.g., ONT)
#TECH_TAG="ONT" # <-- CHANGE THIS
TECH_TAG="PacBio" # <-- CHANGE THIS

# 4. Estimated Genome Size (Used for subsampling and assembly - e.g., 3.1m, 1.5m)
#GENOME_SIZE="3.1m" # <-- CHANGE THIS
GENOME_SIZE="1.8m" # <-- CHANGE THIS

# --- CRITICAL: Set Plassembler DB Path using the user's custom location ---
export PLASSEMBLER_DB="./db/plassembler_db"

# --- DIRECTORY AND FILE DEFINITIONS ---
APP_ID="project_${SRA_ACCESSION}"
INPUT_READS_DIR="./input_reads"
SRA_STAGING_DIR=".temp_sra"
SUBSAMPLED_READ_DIR="./subsampled_reads"
ASSEMBLY_INPUT_DIR="./autocycler_input_assemblies"
AUTOCYCLER_DIR="./autocycler_output_graph"

# Legacy prefix check (Prevents cross-contamination from old runs)
LEGACY_PREFIX="my_unknown_genome_project"

# Final FASTQ file name created by Stage 0 (and used as input for Stage 1)
FINAL_READ_FILE="$INPUT_READS_DIR/${SRA_ACCESSION}_${GENUS_NAME}_${TECH_TAG}.fastq.gz"
ORIGINAL_READ_FILE="$FINAL_READ_FILE"

# Assembly & Processing Parameters
SUBSAMPLE_COUNT=4
ASSEMBLERS="flye canu metamdbg miniasm necat nextdenovo raven redbean plassembler"
THREADS=8
KMER_SIZE=51
CLUSTER_CUTOFF=0.2

# Derived Paths (used for resume checks)
INPUT_GFA="$AUTOCYCLER_DIR/input_assemblies.gfa"
FINAL_GFA="$AUTOCYCLER_DIR/combined.gfa"
CLUSTER_PARENT_DIR="$AUTOCYCLER_DIR/clustering/qc_pass"
CLUSTER_TOP_DIR="$AUTOCYCLER_DIR/clustering"


# Ensure all necessary directories exist
mkdir -p "$INPUT_READS_DIR"
mkdir -p "$SRA_STAGING_DIR"
mkdir -p "$SUBSAMPLED_READ_DIR"
mkdir -p "$ASSEMBLY_INPUT_DIR"
mkdir -p "$AUTOCYCLER_DIR"

echo "--- STARTING AUTOCYCLER MASTER PIPELINE ---"
echo "SRA Accession: $SRA_ACCESSION"
echo "Project ID: $APP_ID"
#echo "Plasmid DB Path: $PLASMID_DB_PATH"
echo "Plassembler DB Path: $PLASSEMBLER_DB"

# ----------------------------------------------------------------------
# --- PREREQUISITE CHECK: LEGACY FILE POLLUTION (STOPS if detected) ---
# ----------------------------------------------------------------------
echo ""
echo "#########################################################"
echo "--- PREREQUISITE CHECK: LEGACY FILE POLLUTION ---"
echo "#########################################################"

if find "$ASSEMBLY_INPUT_DIR" -maxdepth 1 -type f \
    \( -name "${LEGACY_PREFIX}*.fasta" -o -name "${LEGACY_PREFIX}*.gfa" -o -name "${LEGACY_PREFIX}*.log" \) | grep -q .; then
    echo "!!! STOPPING: LEGACY ASSEMBLY FILES DETECTED !!!"
    echo "ACTION REQUIRED: Please run: rm -rf $ASSEMBLY_INPUT_DIR $AUTOCYCLER_DIR"
    exit 1
fi
echo "Prerequisite check passed."

# ----------------------------------------------------------------------
# --- FINAL PIPELINE COMPLETION CHECK (If final output exists, exit pipeline) ---
# ----------------------------------------------------------------------
if [ -f "$FINAL_GFA" ]; then
    echo "========================================================="
    echo "!!! PIPELINE COMPLETE: Final GFA ($FINAL_GFA) already exists. !!!"
    echo "========================================================="
    exit 0
fi

# ======================================================================
# --- STAGE 0: SRA DOWNLOAD AND SETUP ---
# ======================================================================
echo ""
echo "#########################################################"
echo "--- STAGE 0/4: SRA DOWNLOAD AND SETUP ---"
echo "#########################################################"

if [ -f "$FINAL_READ_FILE" ]; then
    echo "Skipping SRA download: Final read file ($FINAL_READ_FILE) already exists."
else
    # Define temporary file paths (as in the original Part 1 logic)
    TEMP_PREFIX="$SRA_STAGING_DIR/$SRA_ACCESSION"
    FILE_NO_SUFFIX="${TEMP_PREFIX}.fastq.gz"
    TEMP_FASTQ_FILE="${TEMP_PREFIX}_1.fastq.gz"
    RAW_SRA_FILE="${TEMP_PREFIX}.sra"
    
    echo "Attempting to download and extract reads for $SRA_ACCESSION using kingfisher..."

    # Kingfisher download attempt
    kingfisher get -r "$SRA_ACCESSION" -m ena-ascp aws-http prefetch -f fastq.gz \
      --output-directory "$SRA_STAGING_DIR" --download-threads "$THREADS" --extraction-threads "$THREADS" --force

    # Handle Kingfisher's naming oddities
    if [ -f "$FILE_NO_SUFFIX" ]; then
      mv "$FILE_NO_SUFFIX" "$TEMP_FASTQ_FILE"
    fi

    # CRITICAL FALLBACK: Handle failed extraction (left behind a .sra file)
    if [ -f "$TEMP_FASTQ_FILE" ]; then
      echo "Successfully found FASTQ file: $TEMP_FASTQ_FILE."
    elif [ -f "$RAW_SRA_FILE" ]; then
      echo "Error: FASTQ missing, but raw SRA file found. Manually extracting using fastq-dump..."
      fastq-dump --gzip --skip-technical --split-files --outdir "$SRA_STAGING_DIR" "$RAW_SRA_FILE"
      if [ -f "$FILE_NO_SUFFIX" ]; then
        mv "$FILE_NO_SUFFIX" "$TEMP_FASTQ_FILE"
      fi
      rm "$RAW_SRA_FILE"
    else
      echo "FATAL ERROR: Could not find FASTQ or SRA file after download attempt."
      exit 1
    fi

    # Final move and cleanup
    echo "Moving $TEMP_FASTQ_FILE to final destination: $FINAL_READ_FILE"
    mv "$TEMP_FASTQ_FILE" "$FINAL_READ_FILE"
    rm -rf "$SRA_STAGING_DIR"
fi
echo "STAGE 0: SRA download and cleanup complete."

# ----------------------------------------------------------------------
# --- STAGE 1 & 2: ASSEMBLY AND COMPRESSION CHECK ---
# ----------------------------------------------------------------------
if [ -f "$INPUT_GFA" ]; then
    echo "Skipping Stage 1 (Assembly) and Stage 2 (Compression): Compressed GFA ($INPUT_GFA) already exists."
    SKIP_STAGE_1_2=true
else
    SKIP_STAGE_1_2=false
fi

if [ "$SKIP_STAGE_1_2" = false ]; then
    # ======================================================================
    # --- STAGE 1: SUBSAMPLING & ASSEMBLY ---
    # ======================================================================
    echo ""
    echo "#########################################################"
    echo "--- STAGE 1/4: SUBSAMPLING AND RUNNING ASSEMBLERS ---"
    echo "#########################################################"

    # 1. Subsampling
    echo "Running Subsampling using input file: $ORIGINAL_READ_FILE..."
    rm -f "$SUBSAMPLED_READ_DIR"/sample_*.fastq

    autocycler subsample \
      --reads "$ORIGINAL_READ_FILE" \
      --out_dir "$SUBSAMPLED_READ_DIR" \
      --genome_size "$GENOME_SIZE" \
      --count "$SUBSAMPLE_COUNT"

    echo "Subsampling complete. Starting assembly..."

    # 2. Assembly Loop
    for ASSEMBLER in $ASSEMBLERS; do
      echo "Starting iterative assembly with $ASSEMBLER..."
      for READ_FILE in "$SUBSAMPLED_READ_DIR"/sample_*.fastq; do
        [ -f "$READ_FILE" ] || continue
        SAMPLE_NAME=$(basename "$READ_FILE" .fastq)
        ASSEMBLY_PREFIX="$ASSEMBLY_INPUT_DIR/${APP_ID}_${ASSEMBLER}_${SAMPLE_NAME}"

    # Granular Resume Check: Check if the final expected output file already exists.
    # We check for both .fasta and .gfa as different assemblers produce different primary outputs.
    EXPECTED_OUTPUT_FASTA="${ASSEMBLY_PREFIX}.fasta"
    EXPECTED_OUTPUT_GFA="${ASSEMBLY_PREFIX}.gfa"

    # Skip this assembly if a final FASTA or GFA output file is found
    if [ -f "$EXPECTED_OUTPUT_FASTA" ] || [ -f "$EXPECTED_OUTPUT_GFA" ]; then
      echo "  -> Skipping $ASSEMBLER on $SAMPLE_NAME: Assembly output already exists."
      continue
    fi

        echo "  -> Running $ASSEMBLER on $SAMPLE_NAME, prefix set to $ASSEMBLY_PREFIX"

        autocycler helper \
          --reads "$READ_FILE" \
          --out_prefix "$ASSEMBLY_PREFIX" \
          --genome_size "$GENOME_SIZE" \
          "$ASSEMBLER"
      done
    done
    echo "STAGE 1: Assembly of all subsamples complete."

    # ======================================================================
    # --- STAGE 2: CLEANUP & COMPRESSION --- (Integration of Part 1 & 2)
    # ======================================================================
    echo ""
    echo "#########################################################"
    echo "--- STAGE 2/4: CLEANUP AND COMPRESSION ---"
    echo "#########################################################"

    # 1. Cleanup: Remove failed assemblies, zero-byte files, and non-project logs
    echo "Cleaning up assembly directory $ASSEMBLY_INPUT_DIR..."
    find "$ASSEMBLY_INPUT_DIR" -name "*miniasm*" -type f -delete
    find "$ASSEMBLY_INPUT_DIR" -type f -size 0 -delete
    find "$ASSEMBLY_INPUT_DIR" -maxdepth 1 -type f -name "*.log" ! -name "${APP_ID}*" -delete
    find "$ASSEMBLY_INPUT_DIR" -maxdepth 1 -type f -name "*.fasta" ! -name "${APP_ID}*" -delete
    find "$ASSEMBLY_INPUT_DIR" -maxdepth 1 -type f -name "*.gfa" ! -name "${APP_ID}*" -delete
    find "$ASSEMBLY_INPUT_DIR" -maxdepth 1 -type f -name "*.fastq" ! -name "${APP_ID}*" -delete
    echo "Cleanup complete."

    # 2. Compression
    echo "--- Running autocycler compress ---"
    autocycler compress \
      --assemblies_dir "$ASSEMBLY_INPUT_DIR" \
      --autocycler_dir "$AUTOCYCLER_DIR" \
      --kmer "$KMER_SIZE" \
      --threads "$THREADS"

    echo "STAGE 2: Compression finished. Unitig graph ready at $INPUT_GFA."
fi

# ======================================================================
# --- STAGE 3: CLUSTERING --- (Integration of Part 3)
# ======================================================================
echo ""
echo "#########################################################"
echo "--- STAGE 3/4: CLUSTERING ---"
echo "#########################################################"

if [ -d "$CLUSTER_TOP_DIR" ]; then
    echo "Skipping Stage 3 (Clustering): Cluster output directory ($CLUSTER_TOP_DIR) already exists."
else
    if [ ! -f "$INPUT_GFA" ]; then
        echo "FATAL ERROR: Required compressed GFA file not found at $INPUT_GFA. Cannot run clustering."
        exit 1
    fi
    echo "Input GFA found. Proceeding to clustering."
    autocycler cluster \
        --autocycler_dir "$AUTOCYCLER_DIR" \
        --cutoff "$CLUSTER_CUTOFF"
    echo "STAGE 3: Clustering finished."
fi

# ======================================================================
# --- STAGE 4: TRIM, RESOLVE, AND COMBINE --- (Integration of Part 4)
# ======================================================================
echo ""
echo "#####################################################"
echo "--- STAGE 4/4: TRIM, RESOLVE, AND COMBINE ---"
echo "#####################################################"

# Find all successful cluster directories (check is needed before proceed)
CLUSTER_DIRS=$(find "$CLUSTER_PARENT_DIR" -maxdepth 1 -type d -name "cluster_*" | sort)

if [ -z "$CLUSTER_DIRS" ]; then
    echo "ERROR: Could not find any 'cluster_*' directories in $CLUSTER_PARENT_DIR. Cannot proceed with trim/resolve/combine."
    exit 1
fi

# 1. Intermediate File Renaming Fix
echo "--- Applying Renaming Fix for 'trim' input ---"
find "$CLUSTER_PARENT_DIR" -type f -name "[0-9]*.gfa" ! -name "*untrimmed.gfa" | while read GFA_FILE; do
  if [[ "$(basename "$GFA_FILE")" =~ ^[0-9]{3}\.gfa$ ]]; then
    GFA_DIR=$(dirname "$GFA_FILE")
    CLUSTER_ID=$(basename "$GFA_FILE" .gfa)
    NEW_NAME="${GFA_DIR}/${CLUSTER_ID}_untrimmed.gfa"
    if [ ! -f "$NEW_NAME" ]; then
      mv "$GFA_FILE" "$NEW_NAME"
    fi
  fi
done
echo "Renaming fix complete."

# 2. Run TRIM and RESOLVE per cluster
echo "--- Running autocycler trim and resolve per cluster ---"
for CLUSTER_DIR in $CLUSTER_DIRS; do
    CLUSTER_NAME=$(basename "$CLUSTER_DIR")
    # Resume Check: Skip if the final output for this cluster already exists
    if find "$CLUSTER_DIR" -maxdepth 1 -type f -name "*_final.gfa" | grep -q .; then
        echo "  -> Skipping TRIM/RESOLVE for $CLUSTER_NAME: *_final.gfa already exists."
        continue
    fi
    
    echo "Processing cluster: $CLUSTER_NAME"

    # Run TRIM
    echo "  -> Running TRIM on $CLUSTER_NAME..."
    autocycler trim \
        --cluster_dir "$CLUSTER_DIR" \
        --threads "$THREADS"

    # Run RESOLVE
    echo "  -> Running RESOLVE on $CLUSTER_NAME..."
    autocycler resolve \
        --cluster_dir "$CLUSTER_DIR"
done
echo "Trim and Resolve steps complete for all successful clusters."


# 3. FINAL COMBINE
echo "--- FINAL COMBINE ---"
# Check if the final combined file already exists (redundant, but safe)
if [ -f "$FINAL_GFA" ]; then
    echo "Skipping final combine: Final GFA ($FINAL_GFA) already exists."
else
    RESOLVED_GFAS=$(find "$AUTOCYCLER_DIR" -type f -name "*_final.gfa" | tr '\n' ' ')

    if [ -z "$RESOLVED_GFAS" ]; then
        echo "ERROR: Could not find any *_final.gfa files in $AUTOCYCLER_DIR. Cannot run combine."
        exit 1
    fi

    echo "Found files for combination: $RESOLVED_GFAS"

    autocycler combine \
        --autocycler_dir "$AUTOCYCLER_DIR" \
        --in_gfas $RESOLVED_GFAS
fi

echo "#####################################################"
echo "--- MASTER PIPELINE COMPLETE SUCCESSFULLY ---"
echo "Final consensus graph available at: $FINAL_GFA"
echo "#####################################################"

