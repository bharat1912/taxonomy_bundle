# Snakefile_autocycler_master_Jan11.smk
# ============================================================
# AUTOCYCLER MASTER PIPELINE (Snakemake Version)
# Author: Bharat K.C. Patel
# ============================================================
# -*- coding: utf-8 -*-
import warnings
warnings.filterwarnings("ignore", category=SyntaxWarning)
import os, glob, re, yaml
from pathlib import Path

#ruleorder: run_busco_consensus > run_busco

# ----------------------------
# LOAD CONFIGURATION FOR AUTOCYCLER
# ----------------------------
configfile: "config/config_auto.yaml"
configfile: "config/config_busco.yaml"

###############################################################################
# LAB SAMPLES AND SRA INITIALIZATION
###############################################################################

# ----------------------------
# LAB SAMPLES
# ----------------------------
local_reads_cfg = config.get("local_reads", {})  # safely return {} if missing
if local_reads_cfg.get("enabled", False):
    LAB_SAMPLES = []
    for sid, meta in local_reads_cfg.get("samples", {}).items():
        LAB_SAMPLES.append({
            "sample_id": sid,
            "fastq": meta["reads"][0],
            "tech": meta["tech_tag"],
            "genus": meta["genus_name"],
            "genome_size": meta["genome_size"]
        })
else:
    LAB_SAMPLES = []


# ----------------------------
# SRA Sample (optional)
# ----------------------------
sra_config = config.get("sra", {})  # empty dict if section missing
SRA_ACCESSION = sra_config.get("accession", None)
GENUS_NAME = sra_config.get("genus_name", "")
TECH_TAG = sra_config.get("tech_tag", "")
GENOME_SIZE = sra_config.get("genome_size", "")

# ----------------------------
# Debug print (optional, useful for learning)
# ----------------------------
print("==============================================")
print(f"Detected LAB samples: {[s['sample_id'] for s in LAB_SAMPLES]}")
print(f"SRA accession: {SRA_ACCESSION}")
print("==============================================")


###############################################################################
# BUSCO Lineage Helper Function (GitHub Portable)
#
# Maps genus → GTDB Hierarchy → Local BUSCO Lineage Folder. 
# Falls back to bacteria_odb12 if no match or missing lineage folder.
# Place this BEFORE Snakefile dynamic config loading.
# ##############################################################################
def detect_best_busco_lineage_from_gtdb(genus_file, gtdb_tsv, busco_lineage_dir):
    """
    Resolves the Taxonomic Conflict by bridging DFAST genus output with
    the GTDB hierarchy to select the most specific local BUSCO dataset.
    """
    # 1. Load the Genus Noun
    try:
        target_genus = Path(genus_file).read_text().strip().lower()
        if target_genus == "unknown": return "bacteria_odb12"
    except Exception:
        return "bacteria_odb12"

    # 2. Resolve Path & Search GTDB
    gtdb_path = Path(gtdb_tsv).resolve()
    full_tax_string = ""
    
    if gtdb_path.exists():
        search_term = f"g__{target_genus}"
        with open(gtdb_path, 'r') as f:
            for line in f:
                if search_term in line.lower():
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        full_tax_string = parts[1].strip()
                        break
    
    if not full_tax_string:
        return "bacteria_odb12"

    # 3. Hierarchical Match (Specific -> Broad)
    available = os.listdir(busco_lineage_dir) if os.path.exists(busco_lineage_dir) else []
    levels = [l.split('__')[-1].lower() for l in full_tax_string.split(';')]
    levels.reverse() 

    for lvl in levels:
        if not lvl or len(lvl) < 3: continue
        for db in available:
            # Strict word matching to avoid 'eukaryota' hijacks
            if db.lower().startswith(lvl + '_'):
                return db
    
    return "bacteria_odb12"


###################################################################
# DYNAMIC CONFIG LOADING (BUSCO + BAKTA)
##################################################################
import configparser

# ----------------------------
# Load BUSCO YAML (Using the already loaded Snakemake config)
# ----------------------------
# Instead of manual 'with open', use the Snakemake 'config' object
BUSCO_CFG = config.get("busco", {}) 

if not BUSCO_CFG:
    # This fallback prevents the KeyError if the file wasn't loaded
    print("[WARNING] BUSCO configuration not found in config object!")

# Defaults from YAML
BUSCO_INPUT_SRC = BUSCO_CFG.get("input_source", "genome")
BUSCO_THREADS   = BUSCO_CFG.get("threads", 16)
BUSCO_LINEAGE   = BUSCO_CFG.get("lineage_dataset", "bacteria_odb12")
BUSCO_STRATEGY  = BUSCO_CFG.get("lineage_strategy", "auto")
BUSCO_AUTO_SCOPE = BUSCO_CFG.get("auto_scope", "prok")
GTDB_TAX_PATH   = BUSCO_CFG.get("gtdb_taxonomy_path", "db_link/gtdb/gtdb_taxonomy.tsv")

# ----------------------------
# Optional INI override
# ----------------------------
busco_ini_file = BUSCO_CFG.get("config_ini", "config/config_busco.ini")
if os.path.exists(busco_ini_file):
    parser = configparser.ConfigParser()
    parser.read(busco_ini_file)
    ini_section = parser["busco_run"]

    # Override YAML settings if provided in INI
    BUSCO_STRATEGY = ini_section.get("lineage_strategy", BUSCO_STRATEGY)
    BUSCO_DOWNLOADS = ini_section.get("download_path", "./db_link/busco")
    BUSCO_DATASET_VERSION = ini_section.get("datasets_version", "odb12")
else:
    BUSCO_DOWNLOADS = "./db_link/busco"
    BUSCO_DATASET_VERSION = "odb12"

# ----------------------------
# Final debug info
# ----------------------------
print(f"[INFO] BUSCO input source: {BUSCO_INPUT_SRC}")
print(f"[INFO] BUSCO threads: {BUSCO_THREADS}")
print(f"[INFO] BUSCO lineage strategy: {BUSCO_STRATEGY}")
print(f"[INFO] BUSCO auto_scope: {BUSCO_AUTO_SCOPE}")
print(f"[INFO] BUSCO download path: {BUSCO_DOWNLOADS}")
print(f"[INFO] BUSCO dataset version: {BUSCO_DATASET_VERSION}")
print(f"[INFO] BUSCO default/fallback lineage: {BUSCO_LINEAGE}")

# ----------------------------
# Load Bakta YAML (unchanged)
# ----------------------------
bakta_cfg_file = config.get("bakta_cfg", "config/config_bakta.yaml")
with open(bakta_cfg_file) as f:
    BAKTA_CFG = yaml.safe_load(f)["bakta"]

BAKTA_DB_DIR      = BAKTA_CFG["db"]
BAKTA_INPUT_FASTA = BAKTA_CFG["input_fasta"]
BAKTA_OUTDIR      = BAKTA_CFG["output_dir"]

# Ensure log directories exist
os.makedirs("logs/dfast", exist_ok=True)
os.makedirs("logs/busco", exist_ok=True)


# ============================================================
# ASSEMBLER SELECTION HELPER (permissive / semi-permissive)
# ============================================================
def filter_assemblers_for_sample(read_type):
    mode = config["mode"]["assembler_selection"]
    assemblers = config["assemblers"]
    compat = config["assembler_compatibility"]

    if mode == "permissive":
        return assemblers  # run everything

    elif mode == "semi-permissive":
        filtered = [a for a in assemblers if read_type in compat.get(a, [])]
        if not filtered:
            raise ValueError(
                f"No compatible assemblers found for read_type '{read_type}' "
                f"in semi-permissive mode."
            )
        return filtered

    else:
        raise ValueError("Unknown assembler selection mode in config_auto.yaml")

# ----------------------------
# 1. UNIFIED SAMPLE RESOLUTION 
# ----------------------------
if local_reads_cfg.get("enabled", False) and LAB_SAMPLES:
    ACTIVE_ID    = LAB_SAMPLES[0]["sample_id"]
    GENUS_NAME   = LAB_SAMPLES[0]["genus"]
    TECH_TAG     = LAB_SAMPLES[0]["tech"]
    GENOME_SIZE  = LAB_SAMPLES[0]["genome_size"]
elif SRA_ACCESSION:
    ACTIVE_ID    = SRA_ACCESSION
    # EXPLICITLY assign these from the sra_config defined at top of Snakefile
    GENUS_NAME   = sra_config.get("genus_name", "Unknown")
    TECH_TAG     = sra_config.get("tech_tag", "pacbio_clr")
    GENOME_SIZE  = sra_config.get("genome_size", "3.0m")
else:
    raise ValueError("Conflict: No active sample found in config.")

# ----------------------------
# 2. RESTORE THE MISSING PATHS & PARAMETERS
# ----------------------------
# 1. Base Directories from config
BASE_INPUT_DIR   = config["directories"]["input_reads_dir"]
BASE_RESULT_DIR  = "results_autocycle"

# 2. Extract Processing Parameters (With Safe Fallbacks)
SUBSAMPLE_COUNT = config.get("parameters", {}).get("subsample_count", 4)
THREADS         = config.get("parameters", {}).get("threads", 8)
ASSEMBLERS_LIST = config.get("assemblers", ["flye"])
ASSEMBLERS      = " ".join(ASSEMBLERS_LIST)

# 3. Database Paths (Specifically fixed to avoid the Line 1089 TypeError)
DB_CFG              = config.get("database_paths", {})
PLASSEMBLER_DB_PATH = DB_CFG.get("plassembler_db", "db_link/plassembler")
BAKTA_DB_DIR        = DB_CFG.get("bakta_db", "db_link/bakta")
DFAST_REF_DIR       = DB_CFG.get("dfast_ref", "db_link/dfast_qc_ref")

# 4. System Options (Agnostic to nesting)
READ_TYPE     = config.get("read_type", "pacbio_clr")
SKIP_EXISTING = config.get("skip_existing", True)
SKIP_SRA      = config.get("skip_sra_download", True)

# 5. Derived Sample Paths (Unified & Sample-Aware)
# ============================================================
# RESULTS_ROOT is the single folder for everything.
# By nesting by ACTIVE_ID, LAB and SRA samples never clash.
# ============================================================
RESULTS_ROOT        = "results_autocycle"
SAMPLE_DIR          = os.path.join(RESULTS_ROOT, ACTIVE_ID)
INPUT_READS_DIR     = config["directories"].get("input_reads_dir", "input_reads")

# Tool-specific subdirectories inside the Sample folder
SUBSAMPLED_READ_DIR = os.path.join(SAMPLE_DIR, "01_subsampled")
ASSEMBLY_INPUT_DIR  = os.path.join(SAMPLE_DIR, "02_assemblies")
AUTOCYCLER_DIR      = os.path.join(SAMPLE_DIR, "03_autocycler")
BAKTA_OUTDIR        = os.path.join(SAMPLE_DIR, "bakta")
DFAST_QC_DIR        = os.path.join(SAMPLE_DIR, "dfast_qc")

# 6. BUSCO Hierarchy (Nesting consensus and plots together)
BUSCO_BASE_DIR      = os.path.join(SAMPLE_DIR, "busco")
BUSCO_CONS_DIR      = os.path.join(BUSCO_BASE_DIR, "consensus")
BUSCO_PLOT_DIR      = os.path.join(BUSCO_CONS_DIR, "plots")
BUSCO_AUDIT_DIR     = os.path.join(BUSCO_BASE_DIR, "audit")

# Database downloads (Kept inside results to keep project root clean)
BUSCO_DB_DIR        = os.path.join(RESULTS_ROOT, "busco_downloads")

# Global Logs
LOG_BASE            = os.path.join(SAMPLE_DIR, "logs")

# 7. Environment Readiness [cite: 2025-12-29]
os.makedirs(os.path.join(LOG_BASE, "dfast"), exist_ok=True)
os.makedirs(BUSCO_PLOT_DIR, exist_ok=True)

# ------------------------------------------------------------
# RULE ORDER: The Master Target (Synchronized for BUSCO 6.0)
# ------------------------------------------------------------
rule all:
    input:
        # 1. The Assembly
        os.path.join(AUTOCYCLER_DIR, "consensus_assembly.fasta"),

        # 2. Annotation
        os.path.join(BAKTA_OUTDIR, "consensus_annot.gbk"),

        # 3. Taxonomy Audit + High-Speed Annotations
        os.path.join(DFAST_QC_DIR, "consensus", "genus.txt"), # dfast taxonomy
#        os.path.join(DFAST_QC_DIR, "annotation", "genome.gff"), # dfast annotation

        # 4. Quality Audit
        os.path.join(BUSCO_AUDIT_DIR, "short_summary.txt"),

        # 5. Visualization (CHANGED to match Rule 4.4 output)
        os.path.join(BUSCO_PLOT_DIR, "busco_figure.png"),

        # 6. Lifecycle Flag
        "post_assembly_qc_done.flag"


# ============================================================
# AUTOCYCLER PIPELINE READ FLOW (BEGINNER-FRIENDLY)
# ============================================================
# 
# SRA accession FASTQ (.fastq.gz)
#  │
#  ├─> download_sra -------------------┐
#  │                                   │
#  │                                   │
#  │                               dedup_reads
#  │                                   │
#  │                                   │
#  └─> raw reads (.fastq.gz) ---------> filtlong filter
#                                          │
#                                          │                                          
#                                    subsample_reads
#                                          │
#                                          │
#                         ┌────────────────┴───────────────┐
#                         │                                │
#                  subsampled_reads                renamed_reads (unique IDs)
#             (all assemblers except Flye)            (used for Flye)
#                         │                                │
#                         └─────────┬──────────────────────┘
#                                   │
#                                   ▼
#                              run_assemblers
#        ┌───────────────┬─────────────┬───────────────┐
#        │               │             │               │
#      Raven           Myloasm      Miniasm          Flye
#        │               │             │               │
#  MetaMDBG, NECAT, NextDenovo, Plassembler, Canu, LJA
#        │
#        ▼
#  Apply Plassembler circular contig weights
#  Apply Flye / Canu consensus weights
#        │
#        ▼
#  compress_assemblies
#        │
#        ▼
#  cluster_graph
#        │
#        ▼
#  trim_resolve (QC pass trimming and resolution)
#        │
#        ▼
#  final_combine → final assembly (GFA + FASTA)
#        │
#        ▼   
#    BUSCO quality check
# (Completeness / contamination)
#
#
# ============================================================
# Notes:
# 1. Flye requires renamed reads to ensure unique read IDs.
# 2. Plassembler requires a reference DB and receives extra circular contig weighting.
# 3. Read type is auto-detected from the downloaded SRA or taken from YAML config.
# 4. Assemblers are skipped if output already exists (prevents redundant runs).
# 5. This pipeline currently supports long-read data only (ONT/PacBio).
# 6. Busco is run separately after the pipeline has completed it's run
# ============================================================


# ----------------------------
# Determine sample source and genome metadata
# ----------------------------
if LAB_SAMPLES:
    # Use first LAB sample (or loop over all later)
    sample_meta = LAB_SAMPLES[0]
    GENOME_SIZE = sample_meta.get("genome_size")
    GENUS_NAME = sample_meta.get("genus")
    TECH_TAG = sample_meta.get("tech")
    SAMPLE_ID = sample_meta.get("sample_id")

    if not GENOME_SIZE:
        raise ValueError(f"Genome size missing for LAB sample {SAMPLE_ID}")

elif config.get("sra", {}).get("accession"):
    GENOME_SIZE = config["sra"].get("genome_size")
    GENUS_NAME = config["sra"].get("genus_name")
    TECH_TAG = config["sra"].get("tech_tag")
    SAMPLE_ID = config["sra"].get("accession")

    if not GENOME_SIZE:
        raise ValueError(f"Genome size missing for SRA accession {SAMPLE_ID}")

else:
    raise ValueError(
        "No genome defined: provide either a LAB sample or SRA accession in config/config_auto.yaml"
    )

# ----------------------------
# Convert GENOME_SIZE to numeric bases
# Supports suffixes: k (thousand), m (million), g (billion)
# ----------------------------
import re

def parse_genome_size(size_str):
    size_str = str(size_str).strip().lower()
    match = re.match(r"(\d*\.?\d+)([kmg]?)", size_str)
    if not match:
        raise ValueError(f"Cannot parse genome size: {size_str}")
    number, suffix = match.groups()
    number = float(number)
    multiplier = {"":1, "k":1_000, "m":1_000_000, "g":1_000_000_000}
    return int(number * multiplier[suffix])

GENOME_SIZE_BASES = parse_genome_size(GENOME_SIZE)
print(f"[INFO] SAMPLE: {SAMPLE_ID}")
print(f"[INFO] GENOME_SIZE: {GENOME_SIZE} -> {GENOME_SIZE_BASES} bases")
print(f"[INFO] GENUS_NAME: {GENUS_NAME}")
print(f"[INFO] TECH_TAG: {TECH_TAG}")


# ------------------------------------------------------------
# Rule: download_sra_or_local
# Handles both local lab FASTQ and SRA download
# ============================================================
# Steps:
# 1. Automatically detects all local lab reads
# 2. Skips SRA download entirely when skip_sra_download=True
# 3. Provides beginner-friendly user summary
# 4. Keeps commented learning sections
# 5. Handles keyboard interrupt safely
# ------------------------------------------------------------
rule download_sra_or_local:
    output:
        # Change {SRA_ACCESSION} to {ACTIVE_ID} to remove the 'None'
        fastq = os.path.join(INPUT_READS_DIR, f"{ACTIVE_ID}_{GENUS_NAME}_{TECH_TAG}.fastq.gz"),
        type  = os.path.join(INPUT_READS_DIR, f"{ACTIVE_ID}_{GENUS_NAME}_{TECH_TAG}_readtype.txt")
    threads: THREADS
    run:
        import os
        import shutil
        import gzip
        import signal
        import sys
        from pathlib import Path

        # =============================================================
        # Ensure input directory exists
        # =============================================================
        os.makedirs(INPUT_READS_DIR, exist_ok=True)

        # =============================================================
        # STEP 1: Check for lab sample in YAML
        # =============================================================
        lab_sample = None
        for s in LAB_SAMPLES:
            if s.get("sample_id") == ACTIVE_ID:
                lab_sample = s
                break

        if lab_sample:
            # Emphasize ACTIVE_ID for the log [cite: 2025-06-27]
            print(f"[INFO] LAB sample detected: {ACTIVE_ID}. Using local FASTQ...")
            
            # Use the new named output 'fastq'
            shutil.copy(lab_sample["fastq"], output.fastq) 
            
            # Use the new named output 'type'
            with open(output.type, "w") as f:
                f.write(lab_sample["tech"].lower())

            # Update the summary section [cite: 2025-12-29]
            with gzip.open(output.fastq, "rt") as f:
                num_lines = sum(1 for _ in f)
            num_reads = num_lines // 4
            file_size = os.path.getsize(output.fastq)
            
            print(f"=============================================================")
            print(f"[SUMMARY] Local LAB sample copy complete")
            print(f"SAMPLE ID      : {ACTIVE_ID}") # Corrected from SRA_ACCESSION
            print(f"READ COUNT     : {num_reads:,}")
            print(f"FILE SIZE      : {file_size / (1024*1024):.2f} MB")
            print(f"=============================================================")

            # ADD THIS LINE HERE:
            return  # This stops the rule so it doesn't try to download "None"

        # =============================================================
        # Temporary download directory
        # =============================================================
        tmp_dir = Path(".temp_sra")
        tmp_dir.mkdir(exist_ok=True)

        # =============================================================
        # Retry mechanism with subprocess for safe Ctrl+C
        # =============================================================
        import subprocess

        MAX_RETRIES = 3
        SUCCESS = False
        for attempt in range(1, MAX_RETRIES + 1):
            print(f"=== Download attempt {attempt} for {SRA_ACCESSION} ===")
            try:
                cmd = [
                    "kingfisher", "get",
                    "-r", SRA_ACCESSION,
                    "-m", "ena-ascp", "aws-http", "prefetch",
                    "-f", "fastq.gz",
                    "--output-directory", str(tmp_dir),
                    "--download-threads", str(threads),
                    "--extraction-threads", str(threads),
                    "--force"
                ]
                subprocess.run(cmd, check=True)
            except subprocess.CalledProcessError:
                print(f"[WARNING] Download attempt {attempt} failed.")
                continue
            except KeyboardInterrupt:
                print("[INFO] Ctrl+C detected during SRA download. Cleaning up and exiting.")
                shutil.rmtree(tmp_dir)
                sys.exit(1)

            # ---------------------------------------------------------
            # Detect downloaded FASTQ
            # ---------------------------------------------------------
            found_file = None
            for pattern in [f"{SRA_ACCESSION}_subreads.fastq.gz", f"{SRA_ACCESSION}_pass.fastq.gz"]:
                candidate = tmp_dir / pattern
                if candidate.exists() and candidate.stat().st_size > 0:
                    found_file = candidate
                    break
            if not found_file:
                files = list(tmp_dir.glob(f"{SRA_ACCESSION}*.fastq.gz"))
                if files:
                    found_file = files[0]

            if found_file and found_file.stat().st_size > 0:
                SUCCESS = True
                break

        if not SUCCESS:
            raise RuntimeError(f"[ERROR] Failed to download valid FASTQ for {SRA_ACCESSION} after {MAX_RETRIES} attempts.")

        # ---------------------------------------------------------
        # Detect read type automatically
        # ---------------------------------------------------------
        READ_TYPE_DETECTED = "ont_r10"
        if found_file.name.endswith(".subreads.fastq.gz"):
            READ_TYPE_DETECTED = "pacbio_clr"
            print("[INFO] Detected PacBio subreads.")
        elif found_file.name.endswith("_pass.fastq.gz"):
            READ_TYPE_DETECTED = "ont_r10"
            print("[INFO] Detected ONT pass reads.")

        # ---------------------------------------------------------
        # Move FASTQ and Generate Stats
        # ---------------------------------------------------------
        shutil.move(str(found_file), output.fastq)
        
        with open(output.type, "w") as f:
            f.write(READ_TYPE_DETECTED)

        # FIXING THE GHOSTS:
        with gzip.open(output.fastq, "rt") as f: # Changed from output.reads
            num_lines = sum(1 for _ in f)
        
        num_reads = num_lines // 4
        file_size = os.path.getsize(output.fastq) # Changed from output.reads

        print(f"==============================================")
        print(f"FASTQ path    : {output.fastq}") # Changed from output.reads
        print(f"File size     : {file_size / 1024**2:.2f} MB")
        print(f"Approx. reads : {num_reads}")
        print(f"==============================================")

        # ---------------------------------------------------------
        # Cleanup temporary directory
        # ---------------------------------------------------------
        shutil.rmtree(tmp_dir)
        print("[INFO] Temporary download directory removed.")


# ===========================================================
# Rule Deduplication with clumpify
# ... (Rule body remains unchanged) ...
# ===========================================================
rule dedup_reads:
    input: raw=f"{INPUT_READS_DIR}/{ACTIVE_ID}_{GENUS_NAME}_{TECH_TAG}.fastq.gz"
    output: touch(f"{INPUT_READS_DIR}/dedup_done.flag")
    threads: THREADS
    shell:
        r"""
        TMP={input.raw%.gz}_dedup.fastq.gz
        clumpify.sh in={input.raw} out=$TMP dedupe=t
        mv -f $TMP {input.raw}
        touch {output}

        # ----------------------------------------------------------
        # KEEP THIS USER-FRIENDLY SUMMARY INSIDE THE r""" """ quotes
        # -----------------------------------------------------------
        FILE_SIZE=$(du -h {input.raw} | cut -f1)
        NUM_READS=$(zcat {input.raw} | echo $((`wc -l`/4)))
        echo "-------------------------------------------------------------"
        echo "[SUMMARY] Deduplicated reads (Clumpify)"
        echo "FASTQ path    : {input.raw}"
        echo "File size     : $FILE_SIZE"
        echo "Approx. reads : $NUM_READS"
        echo "-------------------------------------------------------------"
        """

# ----------------------------
# Compute target bases for Filtlong (60× coverage)
# ----------------------------
TARGET_BASES = GENOME_SIZE_BASES * 60
print(f"[INFO] Using TARGET_BASES={TARGET_BASES} for Filtlong (~60× coverage)")


# ===========================================================
# Rule Filtlong (optional; keep filtered file separate)
# ... (Rule body remains unchanged) ...
# ===========================================================
rule filtlong_filter:
    input:
        raw=f"{INPUT_READS_DIR}/{SRA_ACCESSION}_{GENUS_NAME}_{TECH_TAG}.fastq.gz"
    output:
        filtered=f"03_filtlong/{SRA_ACCESSION}_filtered.fastq.gz"
    threads: THREADS
    shell: """
        set -euo pipefail
        mkdir -p 03_filtlong

        # ==============================
        # Beginner-friendly summary
        # ==============================
        echo "============================================================="
        echo "[INFO] Starting Filtlong filtering stage"
        echo "[INFO] Input FASTQ : {input.raw}"
        echo "[INFO] Output FASTQ: {output.filtered}"
        echo "[INFO] Target coverage: 60× (approx.)"
        echo "============================================================="

        # ============================================================
        # Filtlong: good defaults for noisy CLR / ONT reads
        # ------------------------------------------------------------
        # --min_length    1000        # or 2000 for very noisy reads
        # --target_bases  GENOME_SIZE * desired_coverage (e.g. 60×)
        # --keep_percent  80–95       # keep-best percentage (higher = stricter)
        # ============================================================

        # Quote the input and output to handle spaces in Genus Name
        filtlong \
            --min_length 1000 \
            --keep_percent 90 \
            --target_bases {TARGET_BASES} \
            "{input.raw}" | gzip > "{output.filtered}"

        # =========================
        # USER-FRIENDLY SUMMARY
        # =========================
        # We wrap output.filtered in double quotes to handle spaces
        FILE_SIZE=$(du -h {output.filtered} | cut -f1)

        # We use a reliable pipe to count lines and divide by 4
        NUM_READS=$(zcat {output.filtered} | echo $((`wc -l`/4)))

        echo "-------------------------------------------------------------"
        echo "[SUMMARY] Filtlong Filtered Reads"
        echo "FASTQ path    : {output.filtered}"
        echo "File size     : $FILE_SIZE"
        echo "Approx. reads : $NUM_READS"
        echo "-------------------------------------------------------------"
        """

# ============================================================
# RULE 1: SUBSAMPLE READS (The Conflict Resolver)
# ============================================================
rule subsample_reads: 
    input:          
        # We name this 'reads_file' to avoid shadowing the 'input' function
        reads_file = LAB_SAMPLES[0]["fastq"] if local_reads_cfg.get("enabled", False) else f"{INPUT_READS_DIR}/{ACTIVE_ID}_{GENUS_NAME}_{TECH_TAG}.fastq.gz"
    output:
        flag = touch(os.path.join(SUBSAMPLED_READ_DIR, "subsample_done.flag"))
    threads: THREADS
    shell:
        r"""        
        autocycler subsample \
            --reads "{input.reads_file}" \
            --out_dir "{SUBSAMPLED_READ_DIR}" \
            --genome_size {GENOME_SIZE} \
            --count {SUBSAMPLE_COUNT}
        """

# ============================================================
# RULE 2A: RUN ASSEMBLERS (USER-FRIENDLY, YAML-CONFIGURED)
# ============================================================
rule run_assemblers:
    """
    Runs all selected assemblers on subsampled reads.
    - Flye uses renamed reads (unique IDs).
    - Plassembler uses subsampled reads directly.
    - Other assemblers use the generic autocycler helper.
    """
    input:
        subsample_flag=f"{SUBSAMPLED_READ_DIR}/subsample_done.flag"
    output:
        assembly_flag=f"{ASSEMBLY_INPUT_DIR}/assembly_done.flag"
    threads: THREADS
    run:
        import os, glob, subprocess, time, datetime

        # -----------------------------
        # Ensure directories exist
        # -----------------------------
        os.makedirs(ASSEMBLY_INPUT_DIR, exist_ok=True)
        os.makedirs("renamed_reads", exist_ok=True)

        # -----------------------------
        # Determine read type
        # -----------------------------
        # Use the global variable defined in Block #4
        # instead of reaching back into the deleted config['options']
        ACTIVE_READ_TYPE = READ_TYPE 

        # Optional: We still check for the file just to warn you if there's a conflict
        readtype_file = f"{INPUT_READS_DIR}/{SRA_ACCESSION}_{GENUS_NAME}_{TECH_TAG}_readtype.txt"
        if os.path.exists(readtype_file):
            recorded_type = open(readtype_file).read().strip()
            if recorded_type != READ_TYPE:
                print(f"[WARNING] Config says {READ_TYPE}, but metadata file says {recorded_type}.")
                print(f"[INFO] Proceeding with YAML preference: {READ_TYPE}")

        print(f"[INFO] Active Read Model: {ACTIVE_READ_TYPE}") 

        # -----------------------------
        # Discover available reads
        # -----------------------------
        full_read = f"{INPUT_READS_DIR}/{SRA_ACCESSION}_{GENUS_NAME}_{TECH_TAG}.fastq.gz"
        subsampled_reads = sorted(
            glob.glob(os.path.join(SUBSAMPLED_READ_DIR, "sample_*.fastq"))
        )

        # Build renamed set for Flye and others
        renamed_reads = []
        for f in subsampled_reads:
            base = os.path.basename(f).replace(".fastq", "").replace(".gz", "")
            out = f"renamed_reads/{base}_uniq.fastq"
            if not os.path.exists(out):
                print(f"[INFO] Renaming reads: {f} → {out}")
                subprocess.run(f"seqkit rename {f} -o {out}", shell=True, check=True)
            renamed_reads.append(out)

        # -----------------------------
        # Plassembler read selection
        # -----------------------------
        pl_mode = config.get("plassembler_input", "subsampled")
        pl_n = int(config.get("plassembler_subsample_count", SUBSAMPLE_COUNT))
        print(f"[INFO] Plassembler input mode: {pl_mode} (subsample_count={pl_n})")

        # -----------------------------
        # Load weights
        # -----------------------------
        plassembler_weight = config["weights"].get("plassembler_cluster_weight", 3)
        canu_weight = config["weights"].get("canu_consensus_weight", 2)
        flye_weight = config["weights"].get("flye_consensus_weight", 2)

        # ============================================================
        # Run selected assemblers (via autocycler helper)
        # ============================================================
        ASSEMBLERS_TO_RUN = filter_assemblers_for_sample(READ_TYPE)

        # Optional depth filters from config
        min_abs = config.get("min_depth_abs", None)
        min_rel = config.get("min_depth_rel", None)

        for assembler in ASSEMBLERS_TO_RUN:
            assembler_lower = assembler.lower()
            assembler_upper = assembler.upper()

            print("\n" + "=" * 86)
            print(f"{'':20}{'='*10} {assembler_upper.center(25)} {'='*10}")
            print("=" * 86)
            start_batch = time.time()
            print(f"[START] {assembler} batch at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

            # -----------------------------
            # Choose read list per assembler
            # -----------------------------
            if assembler_lower == "flye":
                # Flye prefers unique IDs → use renamed_reads
                read_list = renamed_reads

            elif assembler_lower == "plassembler":
                # Allow plassembler to use either full or subsampled reads
                if pl_mode == "full":
                    if not os.path.exists(full_read):
                        raise FileNotFoundError(f"[ERROR] Full read file not found: {full_read}")
                    read_list = [full_read]
                else:
                    if len(subsampled_reads) == 0:
                        raise FileNotFoundError("[ERROR] No subsampled reads found!")
                    read_list = subsampled_reads[:pl_n]

            else:
                # All other assemblers use subsampled reads
                read_list = subsampled_reads

            # -----------------------------
            # Process each subsample
            # -----------------------------
            for read_file in read_list:
                sample_name = (
                    os.path.basename(read_file)
                    .replace(".fastq", "")
                    .replace("_uniq", "")
                    .replace(".gz", "")
                )

                prefix = os.path.join(
                    ASSEMBLY_INPUT_DIR,
                    f"{ACTIVE_ID}_{assembler_lower}_{sample_name}"
                )

                # Base autocycler helper command
                cmd_parts = [
                    "autocycler", "helper", assembler_lower,
                    "--reads", read_file,
                    "--out_prefix", prefix,
                    "--genome_size", str(GENOME_SIZE),
                    "--threads", str(threads),
                    "--read_type", READ_TYPE,
                ]

                # Optional depth filters
                if min_abs is not None:
                    cmd_parts.extend(["--min_depth_abs", str(min_abs)])
                if min_rel is not None:
                    cmd_parts.extend(["--min_depth_rel", str(min_rel)])

                # Optional plassembler extra args from config
                if assembler_lower == "plassembler":
                    extra = config["parameters"].get("plassembler_args", "").strip()
                    if extra:
                        cmd_parts.extend(["--args", extra])

                cmd = " ".join(cmd_parts)

                # ---------------------------------------------------------
                # SPECIAL CASE: LJA must run inside env-lja
                # ---------------------------------------------------------
                if assembler_lower == "lja":
                    # env-lja must contain lja + autocycler + dependencies
                    cmd = f"pixi run -e env-lja {cmd}"
                else:
                    # All other assemblers (flye, canu, plassembler, etc.)
                    cmd = f"pixi run -e env-b {cmd}"

                print(f"[RUN] {cmd}")
                run_start = time.time()
                ret = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                run_end = time.time()

                if ret.returncode != 0:
                    print(f"[ERROR] {assembler} failed for {sample_name}")
                    print(f"--- STDOUT ---\n{ret.stdout.strip()}")
                    print(f"--- STDERR ---\n{ret.stderr.strip()}")
                else:
                    print(f"[INFO] {assembler} completed successfully in {run_end - run_start:.1f}s")

        # ============================================================
        # Mark assembly batch complete
        # ============================================================
        with open(output.assembly_flag, "w") as f:
            f.write("done\n")
        print("[INFO] All assemblies completed.")


        # ==========================================================
        # Apply assembler-specific weights and log all files
        # ==========================================================
        import re, os, glob
        from datetime import datetime

        print("\n[INFO] Applying assembler-specific weights...")
        log_path = os.path.join(ASSEMBLY_INPUT_DIR, "autocycler_weight_check.log")

        with open(log_path, "w", encoding="utf-8") as LOG:
            LOG.write(f"Autocycler Weight Verification Log\n")
            LOG.write(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            LOG.write(f"{'Assembler':<15} {'File':<60} {'Status'}\n")
            LOG.write("=" * 90 + "\n")

            # --- Plassembler (cluster weight + trusted flag) ---
            for f in sorted(glob.glob(os.path.join(ASSEMBLY_INPUT_DIR, "*_plassembler_*.fasta"))):
                status = "No circular=True tag"
                try:
                    with open(f, "r+", encoding="utf-8") as fh:
                        text = fh.read()
                        if "Autocycler_cluster_weight" in text:
                            status = "Already present"
                        elif "circular=True" in text:
                            text = text.replace(
                                "circular=True",
                                f"circular=True Autocycler_cluster_weight={plassembler_weight} Autocycler_trusted"
                            )  
                            fh.seek(0); fh.write(text); fh.truncate()
                            status = f"Applied cluster_weight={plassembler_weight} + trusted"
                except Exception as e:
                    status = f"Error: {e}"
                LOG.write(f"{'plassembler':<15} {os.path.basename(f):<60} {status}\n")

            # --- Canu & Flye (consensus weight) ---
            for assembler, weight in (("canu", canu_weight), ("flye", flye_weight)):
                for f in sorted(glob.glob(os.path.join(ASSEMBLY_INPUT_DIR, f"*_{assembler}_*.fasta"))):
                    try:
                        with open(f, "r+", encoding="utf-8") as fh:
                            text = fh.read()
                            if "Autocycler_consensus_weight" not in text:
                                new_text = re.sub(
                                    r'^(>[^ \n]+)',
                                    rf'\1 Autocycler_consensus_weight={weight}',
                                    text,
                                    flags=re.M,
                                )
                                fh.seek(0)
                                fh.write(new_text)
                                fh.truncate()
                                status = f"Applied consensus_weight={weight}"
                            else:
                                status = "Already annotated"
                    except Exception as e:
                        status = f"Error: {e}"
                    LOG.write(f"{assembler:<15} {os.path.basename(f):<60} {status}\n")

        print(f"[INFO] Wrote weight verification log to {log_path}")
        print("[INFO] Weight tags applied successfully.\n")

        # -----------------------------
        # Mark assembly completion
        # -----------------------------
        with open(output.assembly_flag, "w") as f:
            f.write("done\n")
        print("[INFO] All assemblies completed successfully.")

# ============================================================
# RULE 2B: VERIFY WEIGHTS IN FASTA HEADERS
# ============================================================
rule verify_weights:
    input:
        flag=f"{ASSEMBLY_INPUT_DIR}/assembly_done.flag"
    output:
        log_file=f"{ASSEMBLY_INPUT_DIR}/autocycler_weight_check.log"
    run:
        import glob, re, os
        weights_expected = {
            "plassembler": "Autocycler_cluster_weight",
            "flye": "Autocycler_consensus_weight",
            "canu": "Autocycler_consensus_weight"
        }

        log_lines = []
        log_lines.append(f"{'Assembler':<15} {'File':<60} {'Status'}")
        log_lines.append("=" * 90)

        for assembler, key in weights_expected.items():
            for f in glob.glob(f"{ASSEMBLY_INPUT_DIR}/*_{assembler}_*.fasta"):
                if not os.path.exists(f):
                    log_lines.append(f"{assembler:<15} {f:<60} ❌ missing FASTA")
                    continue
                try:
                    with open(f) as fh:
                        content = fh.read()
                        if re.search(key, content): # or re.search(key, content, re.I)
                            log_lines.append(f"{assembler:<15} {os.path.basename(f):<60} ✅ found {key}")
                        else:
                            log_lines.append(f"{assembler:<15} {os.path.basename(f):<60} ⚠️  missing {key}")
                except Exception as e:
                    log_lines.append(f"{assembler:<15} {f:<60} ERROR reading file: {e}")

        os.makedirs(os.path.dirname(output.log_file), exist_ok=True)
        with open(output.log_file, "w") as out:
            out.write("\n".join(log_lines))
        print("\n".join(log_lines))
        print(f"\n[INFO] Wrote weight verification log to {output.log_file}")

# ============================================================
# RULE 2C: CLEANUP EMPTY FASTA FILES (CRITICAL FOR AUTOCYCLER)
# ============================================================
rule cleanup_empty_fastas:
    """
    Removes any zero-byte FASTA files before running autocycler compress.
    Autocycler cannot process empty FASTA files and will abort.
    This rule ensures the pipeline always proceeds even if 1–2 assemblers fail.
    """
    input:
        f"{ASSEMBLY_INPUT_DIR}/assembly_done.flag"
    output:
        touch(f"{ASSEMBLY_INPUT_DIR}/empty_cleanup_done.flag")
    run:
        import os, glob

        cleaned = 0
        for f in glob.glob(f"{ASSEMBLY_INPUT_DIR}/*.fasta"):
            if os.path.getsize(f) == 0:
                print(f"[WARNING] Removing empty FASTA: {f}")
                os.remove(f)
                cleaned += 1

        print(f"[INFO] Empty FASTA cleanup complete. Removed {cleaned} files.")

# ============================================================
# RULE 3: RUN AUTOCYCLER COMPRESS (TOLERANT MODE)
# ============================================================
rule compress_assemblies:
    """
    Runs autocycler compress using all non-empty assemblies.
    This version is SAFE: it will not break if some assemblers fail.
    """
    input:
        weight_check = f"{ASSEMBLY_INPUT_DIR}/autocycler_weight_check.log",
        cleanup_done = f"{ASSEMBLY_INPUT_DIR}/empty_cleanup_done.flag"
    output:
        touch(f"{AUTOCYCLER_DIR}/compress_done.flag")
    threads: THREADS
    shell:
        r"""
        set -euo pipefail

        # Ensure output directory exists
        mkdir -p {AUTOCYCLER_DIR}

        # Run autocycler compress
        autocycler compress \
            --assemblies_dir {ASSEMBLY_INPUT_DIR} \
            --autocycler_dir {AUTOCYCLER_DIR} \
            --threads {threads} \
            --max_contigs 100
        # Always produce the output flag so the pipeline continues
        touch {output}
        """

# ============================================================
# RULE 4: CLUSTER
# ... (Github-Portable version) ...
# ============================================================
rule cluster_graph:
    input: 
        flag=f"{AUTOCYCLER_DIR}/compress_done.flag"
    output: 
        touch(f"{AUTOCYCLER_DIR}/cluster_done.flag")
    threads: THREADS
    params:
        # PULL FROM YAML: We keep the YAML keys as they are, but map them to the correct CLI flags
        min_count = config.get("clustering", {}).get("min_assembly_count", 5),
        min_size  = config.get("clustering", {}).get("min_cluster_size", 3)
    shell:
        """
        autocycler cluster \
            --autocycler_dir {AUTOCYCLER_DIR} \
            --min_assemblies {params.min_count} \
            --max_contigs 100
        """

#rule cluster_graph:
#    input:
#        flag=f"{AUTOCYCLER_DIR}/compress_done.flag"
#    output:
#        touch(f"{AUTOCYCLER_DIR}/cluster_done.flag")
#    threads: THREADS
#    shell:
#        """
#        autocycler cluster \
#            --autocycler_dir {AUTOCYCLER_DIR} \
#            --max_contigs 100
#        touch {output}
#        """

# ============================================================
# RULE 5: TRIM AND RESOLVE
# ... (Rule body remains unchanged) ...
# ============================================================
rule trim_resolve:
    input:
        flag=f"{AUTOCYCLER_DIR}/cluster_done.flag"
    output:
        touch(f"{AUTOCYCLER_DIR}/resolve_done.flag")
    threads: THREADS
    shell:
        """
        # run trim and resolve for each cluster under qc_pass
        for CLUSTER_DIR in {AUTOCYCLER_DIR}/clustering/qc_pass/cluster_*; do
            echo "Processing $CLUSTER_DIR"
            autocycler trim \
                --cluster_dir "$CLUSTER_DIR" \
                --threads {THREADS}
            autocycler resolve \
                --cluster_dir "$CLUSTER_DIR"
        done
        touch {output}
        """

# ============================================================
# RULE 6: FINAL COMBINE
# ============================================================
rule final_combine:
    input:
        flag=f"{AUTOCYCLER_DIR}/resolve_done.flag"
    output:
        # CONFLICT RESOLUTION: Updated to use dynamic AUTOCYCLER_DIR [cite: 2025-12-29]
        fasta = os.path.join(AUTOCYCLER_DIR, "consensus_assembly.fasta"),
        pipeline_complete = touch(f"{AUTOCYCLER_DIR}/pipeline_complete.flag")
    threads: THREADS
    shell:
        r"""
        # Find GFAs within the sample-specific directory [cite: 2025-12-29]
        RESOLVED_GFAS=$(find {AUTOCYCLER_DIR}/clustering/qc_pass -type f -name "*_final.gfa" | tr '\n' ' ')
        echo "Found GFAs: $RESOLVED_GFAS"

        # Run combine tool
        autocycler combine \
            --autocycler_dir {AUTOCYCLER_DIR} \
            --in_gfas $RESOLVED_GFAS

        # Standardizing the output path for the Audit phase [cite: 2025-06-27]
        if [ -f "{AUTOCYCLER_DIR}/autocycler_assembly.fasta" ]; then
            cp "{AUTOCYCLER_DIR}/autocycler_assembly.fasta" "{output.fasta}"
        fi
        """

###############################################################################
# SECTION 4 — DFAST_QC → GTDB → BUSCO (Clean, BUSCO-compatible design)
###############################################################################

# =============================================================================
# 4.0  DIRECTORY STRUCTURE (refined – multi-BUSCO safe)
# =============================================================================
# DFAST_QC + GTDB lineage detection always stays in:
#     dfast_qc/consensus/
#
# BUSCO runs are separated by intent:
#     busco/consensus/   ← scientific result
#     busco/audit/       ← compliance / verification
#
# BUSCO plot (publication-grade) goes into:
#     busco/consensus/plots/
# =============================================================================
# Use ACTIVE_ID instead of SRA_ACCESSION to support both LAB and SRA samples
BUSCO_BASE_DIR  = os.path.join(BASE_RESULT_DIR, ACTIVE_ID, "busco")
BUSCO_CONS_DIR  = os.path.join(BUSCO_BASE_DIR, "consensus")
BUSCO_AUDIT_DIR = os.path.join(BUSCO_BASE_DIR, "audit")
BUSCO_PLOT_DIR  = os.path.join(BUSCO_CONS_DIR, "plots")

# Ensure directories exist so Snakemake doesn't complain
os.makedirs(BUSCO_CONS_DIR,  exist_ok=True)
os.makedirs(BUSCO_AUDIT_DIR, exist_ok=True)
os.makedirs(BUSCO_PLOT_DIR,  exist_ok=True)


# =============================================================================
# 4.X  Run DFAST_QC on consensus assembly
#       Produces: dfast_qc/consensus/result_gtdb.tsv and dqc_result.json
#       Note: --disable_cc avoids ete3 taxid crash (CheckM2 handles QC elsewhere)
#             --enable_gtdb provides species-level taxonomy for isolate genomes
#             For MAGs from novel/underrepresented taxa use MiGA + GTDB-Tk instead
# =============================================================================
rule dfast_qc_consensus:
    input:
        fasta = os.path.join(AUTOCYCLER_DIR, "consensus_assembly.fasta"),
        db_ref = os.path.join(config["paths"]["db_root"], "dfast_qc_ref")
    output:
        gtdb = os.path.join(DFAST_QC_DIR, "consensus/result_gtdb.tsv"),
        json = os.path.join(DFAST_QC_DIR, "consensus/dqc_result.json")
    threads: 8
    log:
        os.path.join(DFAST_QC_DIR, "consensus/dfast_qc.log")
    shell:
        r"""
        mkdir -p {DFAST_QC_DIR}/consensus
        pixi run -e env-checkm2 dfast_qc \
            -i {input.fasta} \
            -o {DFAST_QC_DIR}/consensus \
            -r {input.db_ref} \
            --enable_gtdb \
            --disable_cc \
            --force \
            -t {threads} \
            > {log} 2>&1
        """

# =============================================================================
# 4.1  Detect genus from DFAST_QC JSON
# =============================================================================
rule extract_genus_consensus:
    input:
        cc   = os.path.join(DFAST_QC_DIR, "consensus/result_gtdb.tsv"),
        json = os.path.join(DFAST_QC_DIR, "consensus/dqc_result.json")
    output:
        genus = os.path.join(DFAST_QC_DIR, "consensus/genus.txt")
    run:
        import json
        from pathlib import Path
        genus = "unknown"
        jf = Path(input.json)
        if jf.exists():
            data = json.load(jf.open())
            if "gtdb_result" in data and data["gtdb_result"]:
                best = max(data["gtdb_result"], key=lambda x: x.get("ani", 0))
                tax  = best.get("gtdb_taxonomy", "")
                parts = [p for p in tax.split(";") if p.startswith("g__")]
                if parts:
                    genus = parts[0].split("__", 1)[-1]
        Path(output.genus).write_text(genus + "\n")
        print(f"Sovereign Taxonomy Identified: {genus}")

# =============================================================================
# 4.3  Detect BUSCO lineage (GTDB-derived)
# =============================================================================
rule detect_busco_lineage_consensus:
    input:
        genus_file = os.path.join(DFAST_QC_DIR, "consensus/genus.txt")
    params:
        gtdb_db = config["busco"]["gtdb_taxonomy_path"],
        busco_db_lineages = "db_link/busco/lineages"
    output:
        lineage = os.path.join(DFAST_QC_DIR, "consensus/busco_lineage.txt")
    run:
        # This function now uses the gtdb_taxonomy.tsv to find the full hierarchy
        lineage = detect_best_busco_lineage_from_gtdb(
            input.genus_file, 
            params.gtdb_db, 
            params.busco_db_lineages
        )
        from pathlib import Path
        Path(output.lineage).write_text(lineage + "\n")

# =============================================================================
# 4.4  Run BUSCO with detected lineage (Direct Path Mapping)
# =============================================================================
rule run_busco_consensus:
    input:
        fasta = os.path.join(AUTOCYCLER_DIR, "consensus_assembly.fasta")
    output:
        # THE FIX: Use variables instead of hard-coded "LAB001"
        summary = os.path.join(BUSCO_AUDIT_DIR, "short_summary.txt"),
        plot    = os.path.join(BUSCO_PLOT_DIR, "busco_figure.png")
    log:
        os.path.join(LOG_BASE, "busco/busco_consensus.log")
    threads: 16
    shell:
        r"""
        # 1. Run BUSCO 6.0
        pixi run -e env-busco busco \
            -i {input.fasta} \
            -o temp_busco \
            --out_path {BUSCO_BASE_DIR} \
            -m genome \
            --auto-lineage-prok \
            --cpu {threads} -f > {log} 2>&1

        # 2. Built-in Plotting
        pixi run -e env-busco busco --plot {BUSCO_BASE_DIR}/temp_busco

        # 3. Normalization: Deliver to the exact strings Snakemake expects
        mkdir -p $(dirname {output.summary})
        mkdir -p $(dirname {output.plot})

        LATEST_SUMMARY=$(ls -t {BUSCO_BASE_DIR}/temp_busco/run_*/short_summary.txt | head -n 1)
        cp "$LATEST_SUMMARY" {output.summary}
        cp {BUSCO_BASE_DIR}/temp_busco/busco_figure.png {output.plot}
        """


# ============================================================
# 5. Download Bakta DB (only if missing)
#   - Expects DB in db/bakta_DB/db (as per config_bakta.yaml)
#   - Uses env-a to run bakta_db
# ============================================================
rule bakta_download_db:
    output:
        directory(BAKTA_DB_DIR)   # e.g. db/bakta_DB/db
    threads: 4
    shell:
        r"""
        echo "[INFO] Checking Bakta DB directory: {output}"

        mkdir -p {output}

        if [ ! -f "{output}/version.json" ]; then
            echo "[INFO] Bakta DB not found → downloading..."

            # Download into parent directory (db/bakta_DB)
            pixi run -e env-a bakta_db download --output $(dirname {output})

            echo "[INFO] Bakta DB successfully downloaded."
        else
            echo "[INFO] Bakta DB already exists."
        fi
        """

# ============================================================
# 6. Run Bakta annotation on Autocycler consensus assembly
# ============================================================
rule bakta_annotate:
    input:
        fasta = os.path.join(AUTOCYCLER_DIR, "consensus_assembly.fasta"),
        dbdir = BAKTA_DB_DIR
    output:
        gbk = os.path.join(BAKTA_OUTDIR, "consensus_annot.gbk")
    threads: BAKTA_CFG.get("threads", 8)
    params:
        prefix      = BAKTA_CFG.get("prefix", "consensus_annot"),
        locus_tag   = BAKTA_CFG.get("locus_tag", "LOCUS"),
        keep_contigs= "--keep-contig-headers" if BAKTA_CFG.get("keep_contigs", True) else "",
        min_length  = BAKTA_CFG.get("min_length", 200),
        outdir      = BAKTA_OUTDIR
    shell:
        r"""
        mkdir -p {params.outdir}

        # Run Bakta via Pixi Bridge [cite: 2025-12-29]
        pixi run -e env-a bakta \
            --db {input.dbdir} \
            --threads {threads} \
            --prefix {params.prefix} \
            --locus-tag {params.locus_tag} \
            {params.keep_contigs} \
            --min-contig-length {params.min_length} \
            --force \
            --output {params.outdir} \
            {input.fasta}

        # --- SOVEREIGN NORMALIZATION: Sealed Logic Chain [cite: 2025-06-27] ---
        if [ -f "{params.outdir}/{params.prefix}.gbk" ]; then
            cp "{params.outdir}/{params.prefix}.gbk" "{output.gbk}"
        elif [ -f "{params.outdir}/{params.prefix}.gbk.gz" ]; then
            gunzip -c "{params.outdir}/{params.prefix}.gbk.gz" > "{output.gbk}"
        elif [ -f "{params.outdir}/{params.prefix}.gbff" ]; then
            cp "{params.outdir}/{params.prefix}.gbff" "{output.gbk}"
        else
            echo "[ERROR] Bakta produced no usable GBK/GBFF file for audit." >&2
            ls -lh {params.outdir}
            exit 1
        fi

        echo "SUCCESS: {output.gbk} normalized and ready for 7810 audit."
        """

# ============================================================
# 7. MASTER RULE — Post-assembly QC & annotation
# ============================================================
rule run_post_assembly_qc:
    input:
        # POINT TO DYNAMIC PATHS: Matches Rule 6 and 4.x [cite: 2025-12-29]
        fasta         = os.path.join(AUTOCYCLER_DIR, "consensus_assembly.fasta"),
        genus         = os.path.join(DFAST_QC_DIR, "consensus/genus.txt"),
        gbk           = os.path.join(BAKTA_OUTDIR, "consensus_annot.gbk"),
        busco_summary = os.path.join(BUSCO_AUDIT_DIR, "short_summary.txt"),
        busco_plot    = os.path.join(BUSCO_PLOT_DIR, "busco_figure.png")
    output:
        "post_assembly_qc_done.flag"
    shell:
        "touch {output}"

# ============================================================
# DIAGNOSTIC RULE: Run this to see what Snakemake sees
# ============================================================
rule diagnostic_paths:
    run:
        print("\n" + "="*50)
        print("PATH DIAGNOSTIC FOR TOWER 7810")
        print("="*50)
        print(f"1. Rule All Summary path: {os.path.join(BUSCO_AUDIT_DIR, 'short_summary.txt')}")
        print(f"2. Rule All Plot path:    {os.path.join(BUSCO_PLOT_DIR, 'busco_figure.png')}")
        print(f"3. BUSCO_BASE_DIR:        {BUSCO_BASE_DIR}")
        print(f"4. ACTIVE_ID:             {ACTIVE_ID}")
        print("="*50 + "\n")

