##########################################################################################
# Snakefile_hybrid_taxonomy_merged_ver3.smk  (PART 1 — updated)
# Integrated workflow for SRA hybrid genome assembly and taxonomy analysis
# Author: Bharat K.C. Patel
# Location: /home/bharat/software/taxonomy_bundle
#
# PURPOSE:
#   - Download SRA short + long reads (Kingfisher)
#   - Normalise filenames:
#       short raw:     {acc}_1.fastq.gz, {acc}_2.fastq.gz, {acc}_unpaired.fastq.gz
#       short trimmed: {acc}_1.trim.fastq.gz, {acc}_2.trim.fastq.gz, {acc}_unpaired.trim.fastq.gz
#       long raw:      {acc}_long.fastq.gz
#       long filtered: {acc}_long_filtered.fastq.gz
#   - Filter long reads (Filtlong)
#   - Trim Illumina reads (Fastp)  [handles PE + SE/unpaired]
#   - Perform hybrid/short-only assembly (Unicycler, with optional -s, -l)
#   - Trim contigs (seqkit / bbduk.sh)
#   - Evaluate assemblies (QUAST)
#   - Prepare assembly path list for DFAST/GToTree (assembly.txt)
#
# CONFIG:
#   Uses config/config_taxonomy_merged.yaml
##########################################################################################
configfile: "config/config_taxonomy_merged.yaml"

import os
import glob
import shutil
from pathlib import Path
from snakemake.shell import shell

###############################################################################
# RULE ORDERING: Prioritize local data rules over SRA download rules
###############################################################################
ruleorder: provide_local_hybrid_short_reads > download_sra_short_reads
ruleorder: provide_dummy_long_reads > download_sra_long_reads


###############################################################################
# SECTION 1 — GLOBALS & INPUT SPACE (STRICT WHITELIST MODE)
###############################################################################
PROJECT_ROOT = os.getcwd()
RAW_DATA_DIR = os.path.join(PROJECT_ROOT, "raw_data")

# Central analysis output directory
ANALYSIS_DIR = os.path.join(PROJECT_ROOT, "hybrid_taxonomy_analysis")

# 1. Root for all unicycler-related outputs
OUT_DIR = os.path.join(ANALYSIS_DIR, "unicycler_merger")

# 2. HELPER: Defines the path to a specific sample's folder
# This makes rules much cleaner and ensures logs/summaries stay together.
SAMPLE_DIR = os.path.join(OUT_DIR, "{accession}")

# 3. Global paths for Logs and Merged summaries
# Note: LOGS_DIR is now a general top-level log folder if needed, 
# but per-sample logs will use SAMPLE_DIR.
LOGS_DIR       = os.path.join(OUT_DIR, "logs")
OUT_DIR_MERGED = os.path.join(OUT_DIR, "merged_summary")

# 4. Config variables
THREADS           = int(config.get("threads", 8))
MIN_CONTIG_LENGTH = int(config.get("min_contig_length", 200))
DFAST_DB          = config.get("dfast_qc_ref_dir")
GTOTREE_HMM_DIR   = config.get("gtotree", {}).get("hmm_dir")


# --------------------------------------------------------------------------
# STRICT WHITELIST ACCESSION SOURCES (CONFIG ONLY)
# --------------------------------------------------------------------------
SRA_ACCESSIONS      = config.get("sra_accessions", [])
HYBRID_SAMPLES      = config.get("sra_hybrid_samples", {})
LOCAL_FASTQ_PATHS   = config.get("local_fastq_paths", {})
LOCAL_LONG_READS    = config.get("local_long_reads_paths", {})
LOCAL_HYBRID_SAMPLES = LOCAL_LONG_READS # Option 5 (local hybrid samples): short_r1, short_r2, long

# Build whitelist of accessions
ALL_ACCESSIONS = sorted(set(
    list(SRA_ACCESSIONS) +
    list(HYBRID_SAMPLES.keys()) +
    list(LOCAL_FASTQ_PATHS.keys()) +
    list(LOCAL_LONG_READS.keys())
))

# Enforce whitelist must not be empty
if not ALL_ACCESSIONS:
    raise ValueError(
        "[CONFIG ERROR] No accessions defined. "
        "Set one of: sra_accessions, sra_hybrid_samples, "
        "local_fastq_paths, local_long_reads_paths."
    )

print(f"[INFO] Project root: {PROJECT_ROOT}")
print(f"[INFO] Analysis output root: {ANALYSIS_DIR}")
print(f"[INFO] Loaded config: config/config_taxonomy_merged.yaml")
print(f"[INFO] Accessions WHITELISTED from config only: {ALL_ACCESSIONS}")


###############################################################################
# SECTION 2 — RULE ALL (TOP-LEVEL TARGETS)
###############################################################################
rule all:
    input:
        # Use OUT_DIR or SAMPLE_DIR variables to ensure absolute paths match the rules
        expand(os.path.join(OUT_DIR, "{accession}", "{accession}_summary.tsv"),
               accession=ALL_ACCESSIONS),

        expand(os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "genus.txt"),
               accession=ALL_ACCESSIONS),

        expand(os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "gtotree_temp", "gtotree_output", "done.txt"),
               accession=ALL_ACCESSIONS),

        expand(os.path.join(OUT_DIR, "{accession}", "qc", "quast", "report.html"),
               accession=ALL_ACCESSIONS),

        expand(os.path.join(OUT_DIR, "{accession}", "reports", "dashboard", "dashboard.html"),
               accession=ALL_ACCESSIONS)


###############################################################################
# SECTION 3 — HELPER FUNCTIONS
###############################################################################
def skip_if_done(output_files):
    """Return True if all output files already exist."""
    if isinstance(output_files, str):
        output_files = [output_files]
    return all(os.path.exists(f) for f in output_files)

def _raise(error):
    raise error


###############################################################################
# SECTION 4 — Summarize Single Accession Results
# PURPOSE: Gathers key info into the sample folder
###############################################################################
rule summarize_single_accession:
    input:
        # These must match the actual output paths of your DFAST/QUAST rules
        genus = os.path.join(SAMPLE_DIR, "taxonomy", "dfast_qc", "genus.txt"),
        quast = os.path.join(SAMPLE_DIR, "qc", "quast", "report.tsv")
    output:
        # This exactly matches what rule all is looking for
        summary = os.path.join(SAMPLE_DIR, "{accession}_summary.tsv")
    log:
        os.path.join(SAMPLE_DIR, "logs", "summary_generation.log")
    shell:
        """
        echo -e "Accession\tGenus\tN50" > {output.summary}
        
        # Extract data (example logic)
        GENUS_VAL=$(cat {input.genus} 2>/dev/null || echo "Unknown")
        N50_VAL=$(grep "N50" {input.quast} | cut -f2 2>/dev/null || echo "N/A")
        
        echo -e "{wildcards.accession}\t$GENUS_VAL\t$N50_VAL" >> {output.summary}
        """


###############################################################################
# SECTION 5A — PROVIDE LOCAL HYBRID SHORT READS (Option 5: r1+r2+long from local)
###############################################################################
rule provide_local_hybrid_short_reads:
    input:
        lambda wc: LOCAL_HYBRID_SAMPLES[wc.accession]["short_r1"],
        lambda wc: LOCAL_HYBRID_SAMPLES[wc.accession]["short_r2"]
    output:
        r1 = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_1.fastq.gz"),
        r2 = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_2.fastq.gz"),
        unp = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_unpaired.fastq.gz")
    log:
        os.path.join(LOGS_DIR, "local_reads", "{accession}_short.log")
    run:
        acc = wildcards.accession
        log_path = Path(str(log))
        out_r1 = Path(output.r1)
        out_r2 = Path(output.r2)
        out_unp = Path(output.unp)

        out_r1.parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # Link R1 and R2
        r1_src = Path(LOCAL_HYBRID_SAMPLES[acc]["short_r1"]).resolve()
        r2_src = Path(LOCAL_HYBRID_SAMPLES[acc]["short_r2"]).resolve()

        if not r1_src.exists() or not r2_src.exists():
            raise FileNotFoundError(f"[LOCAL ERROR] Missing short reads for {acc}")

        out_r1.unlink(missing_ok=True)
        out_r2.unlink(missing_ok=True)
        out_unp.unlink(missing_ok=True)

        out_r1.symlink_to(r1_src)
        out_r2.symlink_to(r2_src)
        out_unp.touch()   # no unpaired reads

        log_path.write_text(
            f"[LOCAL HYBRID] Using local short reads for {acc}\n"
            f"R1 → {r1_src}\n"
            f"R2 → {r2_src}\n"
        )


###############################################################################
# SECTION 5B — SHORT READ DOWNLOAD (SRA via Kingfisher)
###############################################################################
# Naming (raw):
#   {acc}_1.fastq.gz       # R1 (if PE)
#   {acc}_2.fastq.gz       # R2 (if PE)
#   {acc}_unpaired.fastq.gz  # SE dataset OR leftover unpaired reads
###############################################################################

rule download_sra_short_reads:
    output:
        r1        = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_1.fastq.gz"),
        r2        = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_2.fastq.gz"),
        unpaired  = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_unpaired.fastq.gz"),
    params:
        sra_id = lambda wc: (
            HYBRID_SAMPLES[wc.accession]["short"]
            if wc.accession in HYBRID_SAMPLES
            else wc.accession
        )
    log:
        os.path.join(LOGS_DIR, "sra_download_short", "{accession}.log")
    threads: THREADS

    run:
        accession = wildcards.accession
        sra_id    = params.sra_id

        # Define paths early
        out_r1       = Path(output.r1)
        out_r2       = Path(output.r2)
        out_unpaired = Path(output.unpaired)
        out_dir      = out_r1.parent
        log_path     = Path(str(log))

        out_dir.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        ########################################################################
        # LOCAL short-read sample (Option 4)
        ########################################################################
        if accession in LOCAL_FASTQ_PATHS:
            print(f"[SKIP] SRA short-read download skipped for local sample {accession}.")

            r1_src = Path(LOCAL_FASTQ_PATHS[accession]["r1"]).resolve()
            r2_src = Path(LOCAL_FASTQ_PATHS[accession]["r2"]).resolve()

            out_r1.unlink(missing_ok=True)
            out_r2.unlink(missing_ok=True)
            out_unpaired.unlink(missing_ok=True)

            out_r1.symlink_to(r1_src)
            out_r2.symlink_to(r2_src)
            out_unpaired.touch()

            log_path.write_text(
                f"[SKIP] Using LOCAL short reads for {accession}\n"
                f"R1 → {r1_src}\n"
                f"R2 → {r2_src}\n"
            )
            return

        ########################################################################
        # NON-LOCAL: SRA download
        ########################################################################

        # Run Kingfisher
        cmd = [
            "pixi", "run", "-e", "env-b", "kingfisher", "get",
            "-r", sra_id,
            "-m", "ena-ascp", "ena-ftp",
            "-f", "fastq.gz",
            "--download-threads", str(threads),
            "--force",
        ]
        shell(" ".join(cmd) + f" >> {log} 2>&1")

        # Detect results
        cand_r1 = Path(f"{sra_id}_1.fastq.gz")
        cand_r2 = Path(f"{sra_id}_2.fastq.gz")
        cand_se = Path(f"{sra_id}.fastq.gz")

        extra = sorted(glob.glob(f"{sra_id}*.fastq.gz"))

        if cand_r1.exists() and cand_r2.exists():
            shutil.move(str(cand_r1), str(out_r1))
            shutil.move(str(cand_r2), str(out_r2))
            out_unpaired.touch()
            return

        if cand_se.exists():
            shutil.move(str(cand_se), str(out_unpaired))
            out_r1.touch()
            out_r2.touch()
            return

        if extra:
            shutil.move(extra[0], str(out_unpaired))
            out_r1.touch()
            out_r2.touch()
            return

        raise ValueError(f"No FASTQ files found for SRA ID {sra_id}")


###############################################################################
# SECTION 5C — PROVIDE DUMMY LONG READS (For short-read-only local samples)
###############################################################################
def is_local_short_only(wildcards):
    """Checks if the accession is a local short-read sample and is not hybrid/long-read."""
    acc = wildcards.accession
    # If the accession is in LOCAL_FASTQ_PATHS and NOT in LOCAL_LONG_READS, we provide a dummy long read file.
    return acc in LOCAL_FASTQ_PATHS and acc not in LOCAL_LONG_READS

rule provide_dummy_long_reads:
    # Only run for accessions that qualify as short-read-only local data
    output:
        long = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_long.fastq.gz")
    log:
        os.path.join(LOGS_DIR, "local_data_dummy_long", "{accession}.log")

    # Use a dynamic checker to restrict the rule's wildcards
    # The run block ensures the rule only acts on qualifying samples
    run:
        acc = wildcards.accession
        log_path = Path(str(log))
        Path(output.long).parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        
        if not is_local_short_only(wildcards):
             # This should be unreachable if DAG is built correctly
             log_path.write_text(f"[ERROR] Dummy long read rule ran for non-local short sample {acc}.")
             raise Exception(f"Dummy long read rule error for {acc}")

        print(f"[INFO] Creating empty placeholder file for long reads for {acc} (short-read-only sample).")
        # Create dummy empty file to satisfy the output
        Path(output.long).touch()
        log_path.write_text(f"[SKIP] Short-read-only local sample {acc}; created empty placeholder.\n")


###############################################################################
# SECTION 5D — LONG READ DOWNLOAD (SRA via Kingfisher) 
###############################################################################
# Naming (raw long):
#   {acc}_long.fastq.gz
###############################################################################
rule download_sra_long_reads:
    output:
        long = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_long.fastq.gz")
    params:
        # NEW LOGIC:
        # - If hybrid sample → return long SRA ID
        # - If local hybrid sample → return special tag
        # - Otherwise (Option 1 & Option 4) → return None (short-read-only)
        sra_id = lambda wc: (
            HYBRID_SAMPLES[wc.accession]["long"]
            if wc.accession in HYBRID_SAMPLES
            else (
                "LOCAL_SAMPLE_NO_SRA"
                if wc.accession in LOCAL_LONG_READS
                else None   # ← IMPORTANT CHANGE
            )
        )
    log:
        os.path.join(LOGS_DIR, "sra_download_long", "{accession}.log")
    threads: THREADS

    run:
        acc      = wildcards.accession
        log_path = Path(str(log))
        out_long = Path(output.long)

        out_long.parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        ########################################################################
        # 0A. SHORT-READ-ONLY (Option 1 & Option 4)
        ########################################################################
        if params.sra_id is None:
            out_long.touch()
            log_path.write_text(
                f"[SKIP] No long-read SRA ID for short-read-only sample {acc}; "
                f"created empty placeholder long-read file.\n"
            )
            return

        ########################################################################
        # 0B. LOCAL HYBRID (Option 5)
        ########################################################################
        if acc in LOCAL_LONG_READS:

            long_src = Path(LOCAL_LONG_READS[acc]["long"]).resolve()

            if not long_src.exists():
                log_path.write_text(f"[ERROR] Local long-read file not found: {long_src}\n")
                raise FileNotFoundError(f"Local long-read file missing for {acc}")

            out_long.unlink(missing_ok=True)
            out_long.symlink_to(long_src)

            log_path.write_text(
                f"[SKIP] Using LOCAL long-read file for {acc}\n"
                f"[INFO] Linked: {out_long} → {long_src}\n"
            )
            return

        ########################################################################
        # FROM HERE ONWARD: REAL SRA HYBRID LONG-READ DOWNLOAD
        ########################################################################

        acc       = wildcards.accession
        sra_id    = params.sra_id

        # Ensure directories
        out_dir  = out_long.parent
        out_dir.mkdir(parents=True, exist_ok=True)

        with log_path.open("w") as lf:
            lf.write(f"[INFO] Starting Kingfisher long-read download for {acc} (SRA ID: {sra_id})\n")

        # -------------------------
        # 1. Run Kingfisher
        # -------------------------
        cmd = [
            "pixi", "run", "-e", "env-b", "kingfisher", "get",
            "-r", sra_id,
            "-m", "ena-ascp", "ena-ftp",
            "-f", "fastq.gz",
            "--download-threads", str(threads),
            "--force",
        ]

        shell(
            "(" + " ".join(cmd) + f" >> {log} 2>&1) || "
            f"(echo '[ERROR] Kingfisher failed for {sra_id}' >> {log} ; exit 1)"
        )

        ########################################################################
        # 2. Detect downloaded long-read file
        ########################################################################
        dl_dir = Path(PROJECT_ROOT)
        patterns = [
            f"{sra_id}.fastq.gz",
            f"{sra_id}_1.fastq.gz",
            f"{sra_id}_pass.fastq.gz",
            f"{sra_id}.subreads.fastq.gz",
            f"{sra_id}*.fastq.gz",
        ]

        candidate = None
        for pat in patterns:
            matches = sorted(dl_dir.glob(pat))
            if matches:
                candidate = matches[0]
                break

        if not candidate:
            out_long.touch()
            with log_path.open("a") as lf:
                lf.write(f"[WARN] No FASTQ file found for {sra_id}. Created empty placeholder.\n")
            return

        ########################################################################
        # 3. Move into pipeline structure
        ########################################################################
        shutil.move(str(candidate), str(out_long))

        with log_path.open("a") as lf:
            lf.write(f"[INFO] Long reads saved: {out_long}\n")
            lf.write(f"[INFO] Source file was: {candidate}\n")


###############################################################################
# SECTION 6 — LONG READ DOWNSAMPLING (FILTlong)
###############################################################################
# CONFIG SECTION (config_taxonomy_merged.yaml):
#
# long_read_filter:
#   min_length:   1000         # Discard reads shorter than this (bp)
#   keep_percent: 90           # Keep best X% of bases
#   target_bases: 500000000    # Downsample to this many bases (approx X× coverage)
#   mean_q_weight: 1.0         # Weight for quality in scoring
#   length_weight: 1.0         # Weight for length in scoring
#
# Only flags present in config are applied.
###############################################################################
rule filtlong_downsample:
    input:
        long_raw = rules.download_sra_long_reads.output.long
    output:
        long_filtered = os.path.join(
            RAW_DATA_DIR, "filtered_long_reads", "{accession}", "{accession}_long_filtered.fastq.gz"
        )
    log:
        os.path.join(LOGS_DIR, "filtlong", "{accession}.log")
    params:
        target = lambda w: int(config.get("genome_size_mb", 2.0) * config.get("target_coverage", 100) * 1000000),
        min_len = lambda w: config.get("filtlong", {}).get("min_length", 1000)
    threads: 4
    shell:
        """
        echo "[INFO] Resolving Name Collisions via Universal Header Reset..." > {log}
        
        # 1. Force unique names for every read (Read_1, Read_2, etc.)
        # The {{nr}} is a seqkit variable for 'record number'
        pixi run -e env-a seqkit replace -p ".*" -r "Read_{{nr}}" {input.long_raw} -o tmp_renamed.fastq.gz >> {log} 2>&1
        
        echo "[INFO] Headers reset. Running Filtlong..." >> {log}
        pixi run -e env-a filtlong --min_length {params.min_len} --target_bases {params.target} \
            tmp_renamed.fastq.gz 2>> {log} | gzip > {output.long_filtered}
        
        # Cleanup
        rm -f tmp_renamed.fastq.gz
        """


###############################################################################
# SECTION 7 — READ TRIMMING (FASTP: PE + SE/UNPAIRED)
###############################################################################
# RAW short reads (from download):
#   raw_data/raw_reads/{acc}/{acc}_1.fastq.gz
#   raw_data/raw_reads/{acc}/{acc}_2.fastq.gz
#   raw_data/raw_reads/{acc}/{acc}_unpaired.fastq.gz
#
# TRIMMED short reads:
#   raw_data/trimmed_reads/{acc}/{acc}_1.trim.fastq.gz
#   raw_data/trimmed_reads/{acc}/{acc}_2.trim.fastq.gz
#   raw_data/trimmed_reads/{acc}/{acc}_unpaired.trim.fastq.gz
###############################################################################
rule fastp_trim:
    input:
        r1        = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_1.fastq.gz"),
        r2        = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_2.fastq.gz"),
        unpaired  = os.path.join(RAW_DATA_DIR, "raw_reads", "{accession}", "{accession}_unpaired.fastq.gz"),
    output:
        r1        = os.path.join(RAW_DATA_DIR, "trimmed_reads", "{accession}", "{accession}_1.trim.fastq.gz"),
        r2        = os.path.join(RAW_DATA_DIR, "trimmed_reads", "{accession}", "{accession}_2.trim.fastq.gz"),
        unpaired  = os.path.join(RAW_DATA_DIR, "trimmed_reads", "{accession}", "{accession}_unpaired.trim.fastq.gz"),
    log:
        os.path.join(LOGS_DIR, "fastp", "{accession}.log")
    threads: THREADS

    run:
        acc        = wildcards.accession
        in_r1      = Path(str(input.r1))
        in_r2      = Path(str(input.r2))
        in_unp     = Path(str(input.unpaired))
        out_r1     = Path(str(output.r1))
        out_r2     = Path(str(output.r2))
        out_unp    = Path(str(output.unpaired))
        log_path   = Path(str(log))

        out_r1.parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        report_base = log_path.with_suffix("")  # same base for .html and .json

        # Base fastp command
        base_cmd = [
            "pixi", "run", "-e", "env-a", "fastp",
            "--thread", str(threads),
            "--html", f"{report_base}.html",
            "--json", f"{report_base}.json",
        ]

        # --------- Case detection ----------
        r1_ok  = in_r1.exists()  and in_r1.stat().st_size > 0
        r2_ok  = in_r2.exists()  and in_r2.stat().st_size > 0
        unp_ok = in_unp.exists() and in_unp.stat().st_size > 0

        # 1) Paired-end present (possibly with extra unpaired)
        if r1_ok and r2_ok:
            print(f"[INFO] Running fastp (PE) for {acc}")
            cmd = base_cmd + [
                "-i", str(in_r1),
                "-I", str(in_r2),
                "-o", str(out_r1),
                "-O", str(out_r2),
            ]
            shell(" ".join(cmd) + f" >> {log} 2>&1")

            # If unpaired also exists, trim it separately in SE mode
            if unp_ok:
                print(f"[INFO] Running fastp (SE) for unpaired reads of {acc}")
                cmd_unp = base_cmd + [
                    "-i", str(in_unp),
                    "-o", str(out_unp),
                ]
                shell(" ".join(cmd_unp) + f" >> {log} 2>&1")
            else:
                out_unp.touch()

        # 2) SE-only case
        elif unp_ok:
            print(f"[INFO] Running fastp (SE) for {acc}")
            cmd = base_cmd + [
                "-i", str(in_unp),
                "-o", str(out_unp),
            ]
            shell(" ".join(cmd) + f" >> {log} 2>&1")
            out_r1.touch()
            out_r2.touch()

        # 3) No reads at all
        else:
            print(f"[WARN] No short reads found for {acc}; creating dummy trimmed outputs.")
            out_r1.touch()
            out_r2.touch()
            out_unp.touch()
            # dummy reports
            Path(str(report_base) + ".html").touch()
            Path(str(report_base) + ".json").touch()

###############################################################################
# SECTION 8 — ASSEMBLY (UNICYCLER, HYBRID OR SHORT-ONLY)
###############################################################################
# Inputs:
#   trimmed short:
#       {acc}_1.trim.fastq.gz
#       {acc}_2.trim.fastq.gz
#       {acc}_unpaired.trim.fastq.gz
#   filtered long:
#       {acc}_long_filtered.fastq.gz
#
# Assembly:
#   hybrid_taxonomy_analysis/assembly/{acc}/assembly.fasta
###############################################################################
rule assemble_genome_unicycler:
    input:
        r1            = os.path.join(RAW_DATA_DIR, "trimmed_reads", "{accession}", "{accession}_1.trim.fastq.gz"),
        r2            = os.path.join(RAW_DATA_DIR, "trimmed_reads", "{accession}", "{accession}_2.trim.fastq.gz"),
        unpaired_trim = os.path.join(RAW_DATA_DIR, "trimmed_reads", "{accession}", "{accession}_unpaired.trim.fastq.gz"),
        long_filtered = os.path.join(RAW_DATA_DIR, "filtered_long_reads", "{accession}", "{accession}_long_filtered.fastq.gz"),
    output:
        contigs = os.path.join(OUT_DIR, "{accession}", "assembly", "assembly.fasta")
    log:
        os.path.join(LOGS_DIR, "unicycler", "{accession}.log")
    threads: THREADS

    run:
        acc          = wildcards.accession
        out_dir_unicycler = Path(OUT_DIR) / acc / "assembly"
        out_dir_unicycler.mkdir(parents=True, exist_ok=True)
        
        log_path     = Path(str(log))
        log_path.parent.mkdir(parents=True, exist_ok=True)

        in_r1        = Path(str(input.r1))
        in_r2        = Path(str(input.r2))
        in_unp       = Path(str(input.unpaired_trim))
        in_long      = Path(str(input.long_filtered))

        r1_ok        = in_r1.exists() and in_r1.stat().st_size > 0
        r2_ok        = in_r2.exists() and in_r2.stat().st_size > 0
        unp_ok       = in_unp.exists() and in_unp.stat().st_size > 0
        long_ok      = in_long.exists() and in_long.stat().st_size > 0

        # -------------------------
        # 1. Build unicycler command as list
        # -------------------------
        cmd = [
            "pixi", "run", "-e", "env-b", "unicycler",
            "-t", str(threads),
            "-o", str(out_dir_unicycler),
        ]

        if r1_ok and r2_ok:
            cmd += ["-1", str(in_r1), "-2", str(in_r2)]
            if unp_ok:
                cmd += ["-s", str(in_unp)]
            mode_desc = "PE"
        elif unp_ok:
            # SE-only assembly
            cmd += ["-s", str(in_unp)]
            mode_desc = "SE-only"
        else:
            log_path.write_text(f"[ERROR] No short reads available for assembly of {acc}.\n")
            raise ValueError(f"No short reads available for assembly of {acc}")

        if long_ok:
            cmd += ["-l", str(in_long)]
            assembly_mode = f"{mode_desc} + long (hybrid)"
        else:
            assembly_mode = f"{mode_desc} (no long reads)"

        with log_path.open("w") as lf:
            lf.write(f"[INFO] Running Unicycler for {acc} in mode: {assembly_mode}\n")

        shell(" ".join(cmd) + f" >> {log} 2>&1")


###############################################################################
# SECTION 9 — CONTIG TRIMMING (SEQKIT OR BBDUK)
###############################################################################
# Input:
#   hybrid_taxonomy_analysis/assembly/{acc}/assembly.fasta
#
# Output:
#   hybrid_taxonomy_analysis/trimmed/{acc}/contigs_trimmed.fasta
###############################################################################
rule trim_contigs:
    input:
        assembly = rules.assemble_genome_unicycler.output.contigs
    output:
        # **FIXED OUTPUT:** Using the hierarchical QC path
        trimmed = os.path.join(OUT_DIR, "{accession}", "contig_qc", "filtered_assembly", "contigs_trimmed.fasta")
    params:
        tool    = config.get("trimming_tool", "seqkit"),
        min_len = MIN_CONTIG_LENGTH
    log:
        os.path.join(LOGS_DIR, "trim_contigs", "{accession}.log")

    run:
        acc        = wildcards.accession
        tool       = params.tool
        min_len    = params.min_len
        in_asm     = Path(str(input.assembly))
        out_path   = Path(str(output.trimmed))
        log_path   = Path(str(log))

        out_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        if tool == "seqkit":
            msg = "[INFO] Trimming contigs with seqkit..."
            cmd = [
                "pixi", "run", "-e", "env-a", "seqkit", "seq",
                "-m", str(min_len),
                str(in_asm),
            ]
            log_path.write_text(f"{msg}\n")
            shell(" ".join(cmd) + f" > {output.trimmed} 2>> {log}")
        else:
            # bbduk.sh
            msg = "[INFO] Trimming contigs with bbduk.sh..."
            cmd = [
                "pixi", "run", "-e", "env-a", "bbduk.sh",
                f"in={in_asm}",
                f"out={out_path}",
                f"minlength={min_len}",
            ]
            log_path.write_text(f"{msg}\n")
            shell(" ".join(cmd) + f" >> {log} 2>&1")


###############################################################################
# SECTION 10 — Create GToTree Input List (gtotree_input.txt)
###############################################################################
rule create_gtotree_input_list:
    input:
        # **FIXED INPUT:** Pointing to the *filtered* assembly contigs
        trimmed = os.path.join(OUT_DIR, "{accession}", "contig_qc", "filtered_assembly", "contigs_trimmed.fasta")
    output:
        # **FIXED OUTPUT:** Using the hierarchical taxonomy path
        gtt_input = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "gtotree_input.txt")
    run:
        out_path = Path(str(output.gtt_input))
        out_path.parent.mkdir(parents=True, exist_ok=True)

        # The content of the file is the absolute path to the input contigs
        real_path = Path(str(input.trimmed)).resolve()
        out_path.write_text(str(real_path) + "\n")

        print(f"[INFO] Created GToTree input list for {wildcards.accession}: {out_path}")


###############################################################################
# SECTION 11 — QUAST (ASSEMBLY QUALITY REPORT)
###############################################################################
# Input:
#   hybrid_taxonomy_analysis/trimmed/{acc}/contigs_trimmed.fasta
#
# Output:
#   hybrid_taxonomy_analysis/quast/{acc}/report.html
#   hybrid_taxonomy_analysis/quast/{acc}/report.tsv
#
# Notes:
#   • QUAST writes *all* output files directly inside -o <dir>
#   • report.html and report.tsv are already generated with those exact names
#   • No copying/renaming is required (avoids SameFileError)
###############################################################################
rule quast_report:
    input:
        # Final confirmed path for QUAST input (The filtered contigs)
        asm = os.path.join(OUT_DIR, "{accession}", "contig_qc", "filtered_assembly", "contigs_trimmed.fasta")
    output:
        html = os.path.join(OUT_DIR, "{accession}", "qc", "quast", "report.html"),
        tsv  = os.path.join(OUT_DIR, "{accession}", "qc", "quast", "report.tsv")
    log:
        os.path.join(LOGS_DIR, "quast", "{accession}.log")
    threads: THREADS

    run:
        acc        = wildcards.accession
        in_asm     = Path(str(input.asm))

        # QUAST output directory = parent of output.html
        quast_dir  = Path(str(output.html)).parent
        quast_dir.mkdir(parents=True, exist_ok=True)

        log_path   = Path(str(log))
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # -------------------------
        # 1. Build QUAST command
        # -------------------------
        cmd = [
            "pixi", "run", "-e", "env-a", "quast",
            "--min-contig", str(config.get("min_contig_length", MIN_CONTIG_LENGTH)),
            "-t", str(threads),
            "-o", str(quast_dir),
            str(in_asm),
        ]

        # -------------------------
        # 2. Execute
        # -------------------------
        log_path.write_text(f"[INFO] Running QUAST for {acc}\n")
        shell(" ".join(cmd) + f" >> {log} 2>&1")

        # -------------------------
        # 3. Validate expected outputs
        # -------------------------
        if not Path(output.html).exists():
            raise ValueError(f"QUAST failed: missing {output.html}")
        if not Path(output.tsv).exists():
            raise ValueError(f"QUAST failed: missing {output.tsv}")


###############################################################################
# SECTION 12 — PREPARE GToTree INPUT (assembly.txt)
###############################################################################
# Input:
#    {accession}/contig_qc/filtered_assembly/contigs_trimmed.fasta (Filtered Contigs)
#
# Output:
#    {accession}/taxonomy/gtotree/assembly.txt
###############################################################################
rule prepare_gtotree_input:
    input:
        # **FIXED INPUT:** Pointing to the *filtered* contigs for taxonomy analysis
        assembly = os.path.join(OUT_DIR, "{accession}", "contig_qc", "filtered_assembly", "contigs_trimmed.fasta")
    output:
        # **FIXED OUTPUT:** Using the hierarchical taxonomy path
        assembly_txt = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "assembly.txt")
    run:
        out_path  = Path(output.assembly_txt)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        # Note: The output file contains the absolute path to the input assembly file
        real_path = Path(str(input.assembly)).resolve() 
        out_path.write_text(str(real_path) + "\n")
        print(f"[INFO] Created assembly.txt for {wildcards.accession}: {out_path}")


###############################################################################
# SECTION 13 — DFAST-QC ANALYSIS
###############################################################################
# Input:
#   gtotree/{acc}/assembly.txt
#
# Output:
#   dfast_qc/{acc}/cc_result.tsv
#   dfast_qc/{acc}/dqc_result.json
#
# Notes:
#   • Uses env-checkm2 because dfast_qc depends on checkm2
#   • GTDB taxonomy is enabled
#   • One of the most time-consuming steps
###############################################################################

rule run_dfast_qc:
    input:
        fasta_txt = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "assembly.txt")
    output:
        # **FIXED OUTPUT:** Using the hierarchical taxonomy path
        tsv  = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "cc_result.tsv"),
        json = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "dqc_result.json")
    log:
        os.path.join(LOGS_DIR, "dfast_qc", "{accession}.log")
    threads: 4

# ADD THIS PARAMS BLOCK
    params:
        # Resolve the relative path to an absolute path for the tool
        db_path = Path(config.get("dfast_qc_ref_dir", "db_link/dfast_qc_ref")).resolve()
    run:
        acc         = wildcards.accession
        fasta_path  = Path(str(input.fasta_txt)).read_text().strip()
        # **FIXED out_dir:** Pointing to the new hierarchical path for DFAST-QC
        out_dir     = Path(OUT_DIR) / acc / "taxonomy" / "dfast_qc"
        log_path    = Path(str(log))

        out_dir.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # -------------------------
        # 1. Build DFAST-QC command (Including the -r flag)
        # -------------------------
        cmd = [
            "pixi", "run", "-e", "env-checkm2", "dfast_qc",
            "-i", fasta_path,
            "-r", str(params.db_path), # Force flag
            "--out_dir", ".",
            "--enable_gtdb",
            "--force",
            "--num_threads", str(threads),
        ]

        # -------------------------
        # 2. Execute
        # -------------------------
#        shell(f"cd {out_dir} && " + " ".join(cmd) + f" > {log} 2>&1")
        # We add 'export DQC_REFERENCE_DIR={params.db_path}' to force the tool to look there.
        shell(
            f"export DQC_REFERENCE_DIR={params.db_path} && "
            f"cd {out_dir} && " 
            + " ".join(cmd) + 
            f" > {log} 2>&1"
        )

        # -------------------------
        # 3. Confirm expected outputs
        # -------------------------
        missing = []
        if not (out_dir / "cc_result.tsv").exists():
            missing.append("cc_result.tsv")
        if not (out_dir / "dqc_result.json").exists():
            missing.append("dqc_result.json")

        if missing:
            raise ValueError(f"DFAST-QC failed for {acc}; missing: {missing}")


###############################################################################
# SECTION 14 — EXTRACT GENUS FROM DFAST-QC JSON
###############################################################################
# Input:
#    {accession}/taxonomy/dfast_qc/dqc_result.json
#
# Output:
#    {accession}/taxonomy/dfast_qc/genus.txt
###############################################################################
rule extract_genus_name:
    input:
        # **FIXED INPUT:** Pointing to the new hierarchical DFAST-QC path
        json_path = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "dqc_result.json")
    output:
        # **FIXED OUTPUT:** Pointing to the new hierarchical DFAST-QC path
        genus = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "genus.txt")
    run:
        import json

        acc  = wildcards.accession
        json_file = Path(str(input.json_path))
        genus_out = Path(str(output.genus))

        genus_out.parent.mkdir(parents=True, exist_ok=True)

        genus = "unknown"
        if json_file.exists():
            with json_file.open() as f:
                data = json.load(f)

            # Prefer GTDB result
            if "gtdb_result" in data and data["gtdb_result"]:
                best = max(data["gtdb_result"], key=lambda x: x.get("ani", 0))
                tax  = best.get("gtdb_taxonomy", "")
                parts = [p for p in tax.split(";") if p.startswith("g__")]
                if parts:
                    genus = parts[0].split("__", 1)[-1]

        genus_out.write_text(genus + "\n")


###############################################################################
# SECTION 15 — FETCH GTDB ACCESSIONS FOR GToTree, version 1.8.16
###############################################################################
# Input:
#   genus.txt
#
# Output:
#   gtotree/{acc}/temp_accessions/accessions_for_gtotree.txt
#   gtotree/{acc}/temp_accessions/info.tsv
#   directory gtotree/{acc}/temp_accessions
#
# NOTE:
#   • Your installed `gtt-get-accessions-from-GTDB` DOES NOT support --output-prefix
#   • It ALWAYS writes output to the current working directory (CWD)
#   • Therefore we run it inside `temp_dir` and rename the outputs afterward
###############################################################################
rule gtotree_get_gtdb_accessions:
    input:
        genus_file = rules.extract_genus_name.output.genus
    output:
        accs   = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "temp_accessions", "accessions_for_gtotree.txt"),
        info   = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "temp_accessions", "info.tsv"),
        map    = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "temp_accessions", "genome_to_id_map.tsv"),
        temp_dir = directory(os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "temp_accessions"))
    log:
        os.path.join(LOGS_DIR, "gtt_get_accessions", "{accession}.log")
    threads: 4

    run:
        import subprocess

        acc        = wildcards.accession
        genus_path = Path(str(input.genus_file))
        genus      = genus_path.read_text().strip() if genus_path.exists() else "unknown"

        temp_dir = Path(str(output.temp_dir))
        out_acc  = Path(str(output.accs))
        out_info = Path(str(output.info))
        out_map  = Path(str(output.map))
        log_path = Path(str(log))

        # Prepare directories
        temp_dir.mkdir(parents=True, exist_ok=True)
        out_acc.parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # Skip if no genus
        if genus == "unknown":
            out_acc.write_text("# Genus unknown; GTDB search skipped.\n")
            out_info.write_text("# Genus unknown; GTDB search skipped.\n")
            out_map.touch()
            return

        # -------------------------
        # 1. Build command
        # -------------------------
        cmd = [
            "pixi", "run", "-e", "env-b",
            "gtt-get-accessions-from-GTDB",
            "-t", genus,
            "--GTDB-representatives-only"
        ]

        # Optional: use ecogenomics mirror
        if config.get("gtdb", {}).get("use_ecogenomics", False):
            cmd.append("--use-ecogenomics")

        log_path.write_text("[CMD] " + " ".join(cmd) + "\n")

        # -------------------------
        # 2. Run inside temp dir
        # -------------------------
        subprocess.run(
            cmd,
            cwd=str(temp_dir),
            stdout=log_path.open("a"),
            stderr=log_path.open("a"),
        )

        # ---------------------------------------------------------
        # 3 & 4. IDENTIFICATION & CONFLICT RESOLUTION
        # ---------------------------------------------------------
        acc_file  = next(temp_dir.glob("*accs*.txt"), None)
        info_file = next(temp_dir.glob("*info*.tsv"), None)
        map_file  = next(temp_dir.glob("*map*.tsv"), None)

        # 1. Process Accessions (with Uniqueness filter)
        if acc_file and acc_file.exists():
            raw_lines = acc_file.read_text().splitlines()
            unique_accs = []
            seen = set()
            for line in raw_lines:
                clean = line.strip()
                if clean and not clean.startswith("#") and clean not in seen:
                    unique_accs.append(clean)
                    seen.add(clean)
            out_acc.write_text("\n".join(unique_accs) + "\n")
            if acc_file != out_acc: # Avoid unlinking if they are the same path
                acc_file.unlink()
        else:
            out_acc.write_text("# No accessions returned.\n")

        # 2. Handle Info File (Rename or Create Placeholder)
        if info_file and info_file.exists():
            if info_file != out_info:
                info_file.rename(out_info)
        else:
            out_info.write_text("accession\tinfo\n") # Create a valid TSV header placeholder

        # 3. Handle Map File (Rename or Create Placeholder)
        if map_file and map_file.exists():
            if map_file != out_map:
                map_file.rename(out_map)
        else:
            out_map.touch() # Ensure the file exists for Snakemake


###############################################################################
# SECTION 16 — RUN GToTree WITH GENUS-SPECIES LABELS
###############################################################################
# Input:
#   accessions_for_gtotree.txt
#   gtotree_input.txt  (list of trimmed contigs)
#
# Output:
#   gtotree/{acc}/gtotree_temp/gtotree_output/*
#   gtotree/{acc}/gtotree_temp/gtotree_output/done.txti
#
# Flags - https://github.com/AstrobioMike/GToTree/wiki/user-guide#options-set-for-programs-run  
#            -o {params.work_dir}/gtotree_output

###############################################################################
rule run_gtotree:
    input:
        fasta = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "assembly.txt"),
        accs  = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "temp_accessions", "accessions_for_gtotree.txt")
    output:
        done = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "gtotree_temp", "gtotree_output", "done.txt")
    params:
        hmm_path = GTOTREE_HMM_DIR, 
        # This is the 'Parent' folder where the output folder will be created
        work_dir = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree", "gtotree_temp"),
        threads  = 16

    shell:
        """
        # 1. Ensure the work directory exists and move into it
        mkdir -p {params.work_dir}
        cd {params.work_dir}

        # 2. Run GToTree
        # Note: Using the name 'Bacteria' for -H is safer than the path 
        # for pre-packaged sets inside Pixi environments.
        pixi run -e env-b GToTree \
            -a $(realpath {input.accs}) \
            -f $(realpath {input.fasta}) \
            -H Bacteria \
            -j {params.threads} \
            -F \
            -t \
            -D \
            -L Phylum,Class,Order,Family,Genus,Species,Strain \
            -o gtotree_output

        # 3. Create the completion flag inside the correct output folder
        touch $(realpath {output.done})
        """

###############################################################################
# SECTION 17 — FINAL RESULTS SUMMARY
###############################################################################
# Produces:
#    merged_summary/results_summary.tsv
#    merged_summary/final_report.md
###############################################################################
rule summarize_results:
    input: 
        genus = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "genus.txt"),
        # Add other inputs if required by your original rule
        quast = os.path.join(OUT_DIR, "{accession}", "qc", "quast", "report.tsv")
    output:
        # --- FIX 3: ADD {accession} TO THE OUTPUT FILENAMES ---
        results = os.path.join(OUT_DIR_MERGED, "{accession}_results_summary.tsv"),
        report  = os.path.join(OUT_DIR_MERGED, "{accession}_final_report.md")
    params:
        accessions = ALL_ACCESSIONS
    run:
        # Access the specific accession via wildcards
        acc = wildcards.accession
        # FIX: Changed 'tsv' -> 'results' and 'md' -> 'report'
        out_tsv = Path(str(output.results)) 
        out_md  = Path(str(output.report))
        out_tsv.parent.mkdir(parents=True, exist_ok=True)

        # -------------------------
        # 1. Write TSV
        # -------------------------
        lines = ["Accession\tGenus"]
        for acc in params.accessions:
            # **FIXED INTERNAL PATH:** Use OUT_DIR and hierarchical path
            gfile = Path(OUT_DIR) / acc / "taxonomy" / "dfast_qc" / "genus.txt"
            genus = gfile.read_text().strip() if gfile.exists() else "NA"
            lines.append(f"{acc}\t{genus}")

        out_tsv.write_text("\n".join(lines) + "\n")

        # -------------------------
        # 2. Write Markdown
        # -------------------------
        md_lines = [
            # ... (lines 1-8 remain the same) ...
        ]

        for acc in params.accessions:
            # **FIXED INTERNAL PATH:** Use f-string with OUT_DIR and hierarchical path
            genus_path = os.path.join(OUT_DIR, acc, "taxonomy", "dfast_qc", "genus.txt")
            genus = Path(genus_path).read_text().strip()
            md_lines.append(f"| {acc} | {genus} |")

        md_lines += [
            "",
            "## Notes",
            # **FIXED LINK HINT:** Use OUT_DIR and hierarchical path
            f"* GToTree phylogenies under: `{os.path.join(OUT_DIR, 'SAMPLE_ID', 'taxonomy', 'gtotree')}`",
            "",
        ]

        out_md.write_text("\n".join(md_lines) + "\n")


###############################################################################
# SECTION 18 — HTML DASHBOARD REPORT (QUAST + DFAST_QC + GToTree)
###############################################################################
rule build_html_dashboard:
    input:
        quast_html = os.path.join(OUT_DIR, "{accession}", "qc", "quast", "report.html"),
        quast_tsv  = os.path.join(OUT_DIR, "{accession}", "qc", "quast", "report.tsv"),
        dfast_json = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "dqc_result.json"),
        genus_txt  = os.path.join(OUT_DIR, "{accession}", "taxonomy", "dfast_qc", "genus.txt"),
        gtt_done   = os.path.join(OUT_DIR, "{accession}", "taxonomy", "gtotree",
                                  "gtotree_temp", "gtotree_output", "done.txt")
    output:
        # **FIXED OUTPUT:** Using the hierarchical reports path
        html = os.path.join(OUT_DIR, "{accession}", "reports", "dashboard", "dashboard.html")
    log:
        os.path.join(OUT_DIR, "{accession}", "logs", "dashboard.log")
    run:
        acc = wildcards.accession

        # ----------------------------
        # Load QUAST TSV (robust parser)
        # ----------------------------
        quast_data = {}
        with open(input.quast_tsv) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("Assembly"):
                    continue
                try:
                    key, value = line.split("\t", 1)
                    quast_data[key.strip()] = value.strip()
                except ValueError:
                    continue
        
        # --- DFAST JSON ---
        import json
        with open(input.dfast_json) as f:
            dfast = json.load(f)

        cc   = dfast.get("cc_result", {})
        tc   = dfast.get("tc_result", [])
        gtdb = dfast.get("gtdb_result", {})

        genus = Path(input.genus_txt).read_text().strip()

        # --- GToTree links ---
        # UPDATED: Changed from ../../../ to ../../ to reflect the new 2-level depth
        # Path: dashboard/ -> reports/ -> {acc}/ -> unicycler_merger/
        gtt_html_link = "../../taxonomy/gtotree/gtotree_temp/gtotree_output/"
        gtt_tree_hint = "*.tre"

        # --- Ensure output dir ---
        outdir = Path(output.html).parent
        outdir.mkdir(parents=True, exist_ok=True)

        # --- HTML CONTENT ---
        html = f"""
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Genome Dashboard – {acc}</title>
<style>
body {{ font-family: Arial; margin:30px; background:#fafafa; }}
.section {{
  background:white; padding:20px; margin-bottom:25px;
  border-radius:10px; box-shadow:0 2px 5px rgba(0,0,0,0.1);
}}
table {{ border-collapse:collapse; width:100%; }}
td, th {{ border:1px solid #ccc; padding:8px; }}
th {{ background:#eee; }}
</style>
</head>

<body>

<h1>Genome Dashboard – {acc}</h1>
<p><b>Genus Prediction:</b> {genus}</p>

<div class='section'>
<h2>QUAST Assembly Metrics</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Total Length</td><td>{quast_data.get('Total length', 'NA')}</td></tr>
<tr><td># Contigs</td><td>{quast_data.get('# contigs', 'NA')}</td></tr>
<tr><td>N50</td><td>{quast_data.get('N50', 'NA')}</td></tr>
<tr><td>Largest Contig</td><td>{quast_data.get('Largest contig', 'NA')}</td></tr>
<tr><td>GC (%)</td><td>{quast_data.get('GC (%)', 'NA')}</td></tr>
</table>
<p><a href='../../qc/quast/report.html'>View full QUAST report</a></p>
</div>

<div class='section'>
<h2>DFAST_QC Metrics</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Completeness</td><td>{cc.get('completeness','NA')}</td></tr>
<tr><td>Contamination</td><td>{cc.get('contamination','NA')}</td></tr>
<tr><td>Strain Heterogeneity</td><td>{cc.get('strain_heterogeneity','NA')}</td></tr>
<tr><td>Ungapped Genome Size</td><td>{cc.get('ungapped_genome_size','NA')}</td></tr>
</table>
</div>

<div class='section'>
<h2>GToTree Results</h2>
<p><a href="{gtt_html_link}">Open GToTree output directory</a></p>
<p><b>Tree files:</b> <a href="{gtt_html_link}">{gtt_tree_hint}</a></p>
</div>

</body>
</html>
"""

        Path(output.html).write_text(html)
        Path(str(log)).write_text("[INFO] Dashboard built successfully\n")


###############################################################################
# END OF UNICYCLER & TAXONOMY PIPELINE
###############################################################################

