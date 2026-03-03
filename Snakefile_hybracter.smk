###############################################################################
# HYBRACTER HYBRID ASSEMBLY PIPELINE — HYBRID-ONLY VERSION
# Reads only hybrid data (short+long), from SRA or local sources.
# Outputs written to: hybrid_taxonomy_analysis/hybracter/{sample}/

# CONFIG:
#   Uses config/config_hybracter.yaml
##########################################################################################
configfile: "config/config_hybracter.yaml"

import os
import glob
import shutil
from pathlib import Path
from snakemake.shell import shell

###############################################################################
# SECTION 1 — SETUP, GLOBALS & INPUT SPACE (STRICT WHITELIST MODE)
###############################################################################
PROJECT_ROOT = os.getcwd()

RAW_DATA_DIR = "raw_data/hybracter"
OUT_DIR = "hybrid_taxonomy_analysis/hybracter"

# 1. Use direct access for mandatory top-level keys
THREADS = config["threads"]
DFAST_DB = config["dfast_qc_ref_dir"]

# 2. Safely access nested keys (e.g., gtotree and database_paths)
if "gtotree" in config and config["gtotree"] is not None:
    GTOTREE_HMM_DIR = config["gtotree"].get("hmm_dir")
else:
    GTOTREE_HMM_DIR = None

# Ensure PLASSEMBLER_DB is always a path string, falling back to the known default if config fails.
# The path must be relative to the PROJECT_ROOT
# We use .get(..., "default") to ensure a string is returned even if keys are missing.
PLASSEMBLER_DB = None 

# 1. Try to get the path safely from the config file, providing a default value.
if config.get("database_paths") is not None:
    # Use config value, but ensure it's a string, not None, with a default fallback
    PLASSEMBLER_DB = str(config["database_paths"].get("plassembler_db", "db/plassembler_db/"))

# 2. If config failed to load the path, force the known default path.
if PLASSEMBLER_DB is None or not PLASSEMBLER_DB:
    PLASSEMBLER_DB = "db/plassembler_db/" 

# Add a final check to ensure we have a string
if not isinstance(PLASSEMBLER_DB, str):
    raise TypeError(f"PLASSEMBLER_DB variable failed to resolve to a string path. Current type: {type(PLASSEMBLER_DB)}")

# --------------------------------------------
# ACCESSION SOURCES 
# --------------------------------------------
# Use explicit checks to set these variables to an empty dictionary {} if they are missing or null.
if "hybracter_sra_samples" in config and config["hybracter_sra_samples"] is not None:
    SRA_HYBRID = config["hybracter_sra_samples"]
else:
    SRA_HYBRID = {} 

if "hybracter_local_samples" in config and config["hybracter_local_samples"] is not None:
    LOCAL_HYBRID = config["hybracter_local_samples"]
else:
    LOCAL_HYBRID = {} 

# ALL_SAMPLES calculation is now safe because SRA_HYBRID and LOCAL_HYBRID are guaranteed to be dictionaries.
ALL_SAMPLES = list(SRA_HYBRID.keys()) + list(LOCAL_HYBRID.keys())

# -----------------------------------------------------------------
# RULE ORDER: Define priority for ambiguous rules.
# Snakemake will attempt to match download_sra_short_reads before provide_local_reads.
# -----------------------------------------------------------------
ruleorder: download_sra_long_reads > provide_local_reads
ruleorder: download_sra_short_reads > provide_local_reads


###############################################################################
# SECTION 2 — DOWNLOADS, ASSEMBLE AND QC
###############################################################################
# ----------------------------------------------------------------
# 2A. SRA LONG READ DOWNLOAD
# ---------------------------------------------------------------
rule download_sra_long_reads:
    output:
        long = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long.fastq.gz"
    params:
        table = SRA_HYBRID
    log:
        f"{OUT_DIR}/{{sample}}/logs/sra_long.log"
    threads: THREADS

    run:
        sample  = wildcards.sample
        long_id = params.table[sample]["long"]

        # Ensure log and output directories exist
        Path(os.path.dirname(output.long)).mkdir(parents=True, exist_ok=True)
        Path(str(log)).parent.mkdir(parents=True, exist_ok=True)

        # 1. Command to download file to project root
        download_cmd = (
            f"pixi run -e env-b kingfisher get -r {long_id} -m ena-ascp ena-ftp -f fastq.gz --force "
        )

        # 2. Command to move the downloaded file (SRRxxxxxx_subreads.fastq.gz) to the final output location
        # NOTE: We use the actual file name Kingfisher produces for long reads: SRA_ID + _subreads.fastq.gz
        move_cmd = (
            f"&& mv {long_id}_subreads.fastq.gz {output.long}"
        )

        # Execute both commands in sequence. Move only runs if download succeeds.
        shell(f"{download_cmd} {move_cmd} >> {log} 2>&1")

# ----------------------------------------------------------------
# 2B. LONG READ HEADER FIX (SEQKIT)
# ---------------------------------------------------------------
rule fix_long_read_headers:
    input:
        # Output from download_sra_long_reads
        long_raw = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long.fastq.gz"
    output:
        # Intermediate file with unique headers
        long_fixed = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long_unique.fastq.gz" 
    log:
        f"{OUT_DIR}/{{sample}}/logs/seqkit_rename.log"
    threads: 1 # seqkit rename is single-threaded
    
    # seqkit rename: uses an incremental ID for each read, ensuring uniqueness.
    run:
        Path(str(log)).parent.mkdir(parents=True, exist_ok=True)
        
        # Use seqkit to rename headers to fix the "duplicate read name" error
        cmd = (
            f"pixi run -e env-a seqkit rename "
            f"{input.long_raw} "
            f"-o {output.long_fixed}"
        )

        shell(f"{cmd} >> {log} 2>&1")

# ----------------------------------------------------------------
# 2C. RULE LOCAL READS
# ---------------------------------------------------------------
rule provide_local_reads:
    output:
        r1_out   = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R1.fastq.gz",
        r2_out   = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R2.fastq.gz",
        long     = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long.fastq.gz",
    log:
        f"{OUT_DIR}/{{sample}}/logs/local_reads.log"

    run:
        sample = wildcards.sample 
        outdir = Path(os.path.dirname(output.r1_out)) # Update references here
        outdir.mkdir(parents=True, exist_ok=True)

        Path(log).parent.mkdir(parents=True, exist_ok=True)

        r1_src   = Path(LOCAL_HYBRID[sample]["short_r1"]).resolve()
        r2_src   = Path(LOCAL_HYBRID[sample]["short_r2"]).resolve()
        long_src = Path(LOCAL_HYBRID[sample]["long"]).resolve()

        # Update references here
        for dest, src in [(output.r1_out, r1_src), (output.r2_out, r2_src), (output.long_out, long_src)]:
            Path(dest).unlink(missing_ok=True)
            Path(dest).symlink_to(src)

# ----------------------------------------------------------------
# 2D. RULE SELECTOR (SRA VS LOCAL)
# ---------------------------------------------------------------
# Split prepare_reads into two rules with distinct input functions:
rule prepare_sra_reads:
    input:
        r1 = lambda wc: f"{RAW_DATA_DIR}/{wc.sample}/hyb_{wc.sample}_R1.fastq.gz" if wc.sample in SRA_HYBRID else None,
        r2 = lambda wc: f"{RAW_DATA_DIR}/{wc.sample}/hyb_{wc.sample}_R2.fastq.gz" if wc.sample in SRA_HYBRID else None,
        long = lambda wc: f"{RAW_DATA_DIR}/{wc.sample}/hyb_{wc.sample}_long.fastq.gz" if wc.sample in SRA_HYBRID else None,
    # This rule only has inputs if the sample is in SRA_HYBRID

# ----------------------------------------------------------------
# 2E. SRA SHORT READ DOWNLOAD
# ---------------------------------------------------------------
rule download_sra_short_reads:
    output:
        r1 = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R1.fastq.gz",
        r2 = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R2.fastq.gz",
    params:
        table = SRA_HYBRID
    log:
        f"{OUT_DIR}/{{sample}}/logs/sra_short.log"
    threads: THREADS

    run:
        sample = wildcards.sample
        short_id = params.table[sample]["short"]

        out_dir = Path(os.path.dirname(output.r1))
        out_dir.mkdir(parents=True, exist_ok=True)

        log_file = Path(str(log))
        log_file.parent.mkdir(parents=True, exist_ok=True)

        shell(
            f"pixi run -e env-b kingfisher get -r {short_id} -m ena-ascp ena-ftp "
            f"-f fastq.gz --force >> {log_file} 2>&1"
        )

        cand_r1 = Path(f"{short_id}_1.fastq.gz")
        cand_r2 = Path(f"{short_id}_2.fastq.gz")

        if not cand_r1.exists() or not cand_r2.exists():
            raise ValueError(f"Short-read FASTQ files missing for SRA {short_id}")

        shutil.move(str(cand_r1), output.r1)
        shutil.move(str(cand_r2), output.r2)

# ----------------------------------------------------------------
# 2F. LONG READ FILTERING (FILTLONG)
# ---------------------------------------------------------------
rule filtlong_long_reads:
    input:
        # *** CHANGED INPUT: Use the file with unique headers ***
        long = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long_unique.fastq.gz"
    output:
        # **MUST MATCH** hybracter_assemble input exactly
        long_filtered = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long_filtered.fastq.gz"
    log:
        f"{OUT_DIR}/{{sample}}/logs/filtlong.log"
    params:
        # Pulling configuration parameters for the command
        genome_size = config["genome_size_mb"],
        target_coverage = config["target_coverage"],
        min_length = config["filtlong"]["min_length"]
    threads: THREADS

    run:
        Path(str(log)).parent.mkdir(parents=True, exist_ok=True)
        
        # Calculate the minimum number of bases to keep
        target_bases = int(params.genome_size * params.target_coverage * 1000000)
        
        # Define the filtlong command separately
        filtlong_cmd = (
            f"pixi run -e env-a filtlong --min_length {params.min_length} "
            f"--target_bases {target_bases} "
            # *** REMOVED -t {threads} AS FILTLONG DOES NOT SUPPORT IT ***
            f"{input.long}"
        )
        
        # Execute the command, piping stdout to the output file, and redirecting stderr to the log
        shell(
            f"({filtlong_cmd} 2>> {log}) > {output.long_filtered} 2>&1"
        )

# ----------------------------------------------------------------
# 2G. SHORT READ TRIMMING (FASTP)
# ---------------------------------------------------------------
rule fastp_trim:
    input:
        r1 = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R1.fastq.gz", # Output from download_sra_short_reads
        r2 = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R2.fastq.gz"
    output:
        # **MUST MATCH** hybracter_assemble input exactly
        r1_trim = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R1.trim.fastq.gz",
        r2_trim = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R2.trim.fastq.gz",
        html = f"{OUT_DIR}/{{sample}}/qc/fastp/report.html"
    log:
        f"{OUT_DIR}/{{sample}}/logs/fastp.log"
    threads: THREADS

    run:
        outdir = Path(os.path.dirname(output.html))
        outdir.mkdir(parents=True, exist_ok=True)
        Path(str(log)).parent.mkdir(parents=True, exist_ok=True)
        
        cmd = (
            f"pixi run -e env-a fastp "
            f"--in1 {input.r1} --in2 {input.r2} "
            f"--out1 {output.r1_trim} --out2 {output.r2_trim} "
            f"--html {output.html} "
            f"--thread {threads} "
            f"-w {threads}"
        )
        
        shell(f"{cmd} >> {log} 2>&1")

# ----------------------------------------------------------------
# 2H. HYBRACTER ASSEMBLY 
# ---------------------------------------------------------------
rule hybracter_assemble:
    input:
        r1 = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R1.trim.fastq.gz",
        r2 = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R2.trim.fastq.gz",
        long = f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long_filtered.fastq.gz"
    output:
        assembly = f"{OUT_DIR}/{{sample}}/assembly/assembly.fasta",
        flag = f"{OUT_DIR}/{{sample}}/assembly/hybracter_done.flag"
    log:
        f"{OUT_DIR}/{{sample}}/logs/hybracter.log"
    threads: THREADS # Use the global thread count

    run:
        # --- Python Setup (Remains) ---
        plassembler_db_path = os.path.abspath(os.path.join(PROJECT_ROOT, PLASSEMBLER_DB))
        
        # Use simple string paths for shell commands
        outdir = f"{OUT_DIR}/{wildcards.sample}/assembly"
        
        # Create directories with Python
        Path(outdir).mkdir(parents=True, exist_ok=True)
        Path(str(log)).parent.mkdir(parents=True, exist_ok=True)

        # Define paths used inside the shell command
        hybracter_output_src = os.path.join(outdir, "FINAL_OUTPUT/complete/sample_final.fasta")
        final_assembly_dest = output.assembly
        final_flag = output.flag
        
        # --- Atomic Shell Execution (The Fix) ---
        cmd = (
            # 1. Run hybracter (same command as before)
            f"pixi run -e env-a hybracter hybrid-single "
            f"--short_one {input.r1} "
            f"--short_two {input.r2} "
            f"--longreads {input.long} "
            f"--output {outdir} "
            f"--threads {threads} "
            f"--databases {plassembler_db_path} >> {log} 2>&1"
            
            # 2. IF Hybracter succeeds (&&), forcefully copy the final assembly file
            # This is the crucial atomic operation.
            f" && cp -f {hybracter_output_src} {final_assembly_dest}"
            
            # 3. IF Copy succeeds (&&), touch the final flag file
            f" && touch {final_flag}"
        )
        
        # Execute the entire atomic command
        shell(cmd)

# ----------------------------------------------------------------
# 2I. QUAST (ASSEMBLY QUALITY REPORT)
# ---------------------------------------------------------------
rule quast_qc:
    input:
        # Input is the final assembly file from hybracter_assemble
        asm = f"{OUT_DIR}/{{sample}}/assembly/assembly.fasta"
    output:
        html = f"{OUT_DIR}/{{sample}}/qc/quast/report.html",
        tsv  = f"{OUT_DIR}/{{sample}}/qc/quast/report.tsv"
    log:
        f"{OUT_DIR}/{{sample}}/logs/quast.log" # Using OUT_DIR/sample/logs
    threads: THREADS

    run:
        acc         = wildcards.sample # Renamed wildcard
        in_asm      = Path(str(input.asm))

        # QUAST output directory = parent of output.html
        quast_dir  = Path(str(output.html)).parent
        quast_dir.mkdir(parents=True, exist_ok=True)

        log_path   = Path(str(log))
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # -------------------------
        # 1. Build QUAST command
        # -------------------------
        # NOTE: You need to define MIN_CONTIG_LENGTH or use a hardcoded value if config is not set.
        cmd = [
            "pixi", "run", "-e", "env-a", "quast",
            # Assuming MIN_CONTIG_LENGTH is defined at the top of your Snakefile
            # "--min-contig", str(config.get("min_contig_length", MIN_CONTIG_LENGTH)),
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
# SECTION 3. TAXONOMY AND PHYLOGENY (Dfast and GToTree)
###############################################################################
# ----------------------------------------------------------------
# 3A. PREPARE GToTree INPUT (assembly.txt)
# ---------------------------------------------------------------
rule prepare_gtotree_input:
    input:
        # Input is the final assembly file from hybracter_assemble
        assembly = f"{OUT_DIR}/{{sample}}/assembly/assembly.fasta"
    output:
        assembly_txt = f"{OUT_DIR}/{{sample}}/gtotree/assembly.txt"
    run:
        out_path  = Path(output.assembly_txt)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        # Use resolve() to get the absolute path for GToTree
        real_path = Path(str(input.assembly)).resolve() 
        out_path.write_text(str(real_path) + "\n")
        print(f"[INFO] Created assembly.txt for {wildcards.sample}: {out_path}")

# ----------------------------------------------------------------
# 3B. DFAST-QC ANALYSIS (run dfast_qc)
# ---------------------------------------------------------------
# In Snakefile_hybracter_ver1.smk
rule run_dfast_qc:
    input:
        # CHANGE: DEPEND DIRECTLY ON THE FASTA FILE
        fasta_file = f"{OUT_DIR}/{{sample}}/assembly/assembly.fasta"
    output:
        cc_result_tsv = f"{OUT_DIR}/{{sample}}/qc/dfast_qc/cc_result.tsv", 
        dqc_result_json = f"{OUT_DIR}/{{sample}}/qc/dfast_qc/dqc_result.json"
    log:
        f"{OUT_DIR}/{{sample}}/logs/dfast_qc.log"
    threads: 4

# In rule run_dfast_qc, find the definition of log_path:
# log_path = Path(str(log))

# And replace the entire execution section (from 'out_dir.mkdir' to the end of the rule) with this:
    run:
        from pathlib import Path
        
        acc = wildcards.sample 
        fasta_path_absolute = Path(input.fasta_file).resolve()
        out_dir = Path(output.dqc_result_json).parent
        log_path = Path(str(log))

        # --- CRITICAL FIX: Ensure output directory is created (Still needed for output) ---
        out_dir.mkdir(parents=True, exist_ok=True)
        
        # 1. Build the command list (using 'cmd' since that is what you defined)
        cmd = [
            "pixi", "run", "-e", "env-checkm2", "dfast_qc",
            "-i", str(fasta_path_absolute),
            "--out_dir", ".",
            "--enable_gtdb",
            "--force",
            "--num_threads", str(threads),
        ]

        # 2. Convert to the final shell command string
        log_dir_str = str(log_path.parent)
        
        # Define the core command WITHOUT redirection
        core_command = (
            f"cd {out_dir} && " 
            + " ".join(cmd)
        )
        
        # 3. Create the final WRAPPED command for execution
        # We wrap the directory creation, the command, and the redirection
        # inside a single subshell '()' to change the order of parsing.
        final_wrapped_command = (
            f"( mkdir -p {log_dir_str} && {core_command} ) > {log_path} 2>&1"
        )
        
        # 4. Execute the command without Snakemake adding redirection
        shell(final_wrapped_command)

        # 5. Check for output existence (rest of your rule remains the same)
        missing = []
        if not (out_dir / "cc_result.tsv").exists():
            missing.append("cc_result.tsv")
        if not (out_dir / "dqc_result.json").exists():
            missing.append("dqc_result.json")

        if missing:
            raise ValueError(f"DFAST-QC failed for {acc}; missing: {missing}. Check log: {log_path.resolve()}")

# ----------------------------------------------------------------
# 3C. EXTRACT GENUS NAME FROM DFAST-QC JSON (extract_genus_name
# ---------------------------------------------------------------
rule extract_genus_name:
    input:
        json_path = f"{OUT_DIR}/{{sample}}/qc/dfast_qc/dqc_result.json",
        # ADD THE GTDB TSV to ensure Snakemake waits for it.
        gtdb_tsv = f"{OUT_DIR}/{{sample}}/qc/dfast_qc/result_gtdb.tsv" 
    output:
        # Use the /gtotree/ path for seamless integration with downstream rules.
        genus = f"{OUT_DIR}/{{sample}}/gtotree/genus.txt" 
    run:
        import json
        # import csv # (If you decide to use the TSV data later)

        acc  = wildcards.sample
        json_file = Path(str(input.json_path))
        # gtdb_tsv_file = Path(str(input.gtdb_tsv)) # Available if needed
        genus_out = Path(str(output.genus))

        genus_out.parent.mkdir(parents=True, exist_ok=True)

        genus = "unknown"
        
        # --- PRIMARY LOGIC: Extract from JSON ---
        if json_file.exists():
            try:
                with json_file.open() as f:
                    data = json.load(f)

                # Prefer GTDB result 
                if "gtdb_result" in data and data["gtdb_result"]:
                    # Find the best result based on ANI score
                    best = max(data["gtdb_result"], key=lambda x: x.get("ani", 0))
                    tax  = best.get("gtdb_taxonomy", "")
                    
                    # Parse the g__Genus part
                    parts = [p for p in tax.split(";") if p.startswith("g__")]
                    if parts:
                        genus = parts[0].split("__", 1)[-1]

            except Exception as e:
                # Log the issue but default to 'unknown'
                print(f"WARNING: Could not parse DFAST-QC JSON for {acc}. Error: {e}")

        # --- FALLBACK POSITION ADVICE ---
        if genus == "unknown":
            # If the JSON logic fails, this is where you would implement the 
            # fallback reading of the TSV file for the full taxonomic ranks, 
            # or simply rely on the default 'unknown' genus.
            # You can also add a line to the log here to advise the user.
            print(f"WARNING: Genus name could not be extracted for {acc}. Defaulting to 'unknown'.")
        
        genus_out.write_text(genus + "\n")

# ----------------------------------------------------------------
# 3D. FETCH GTDB ACCESSIONS FOR GToTree (gotree_get_gtdb_accessions)
# ---------------------------------------------------------------
rule gtotree_get_gtdb_accessions:
    input:
        # **CRITICAL FIX:** Ensure input matches the output of extract_genus_name rule (which is in /gtotree/)
        genus_file = f"{OUT_DIR}/{{sample}}/gtotree/genus.txt" 
    output:
        # **CRITICAL FIX:** Ensure this is the file name the NEXT rule (run_gtotree) is expecting.
        # This will be renamed to the final path later in the run block.
        accs     = f"{OUT_DIR}/{{sample}}/gtotree/gtdb_accessions.txt", 
        info     = f"{OUT_DIR}/{{sample}}/gtotree/temp_accessions/info.tsv",
        map      = f"{OUT_DIR}/{{sample}}/gtotree/temp_accessions/genome_to_id_map.tsv",
        temp_dir = directory(f"{OUT_DIR}/{{sample}}/gtotree/temp_accessions")
    log:
        f"{OUT_DIR}/{{sample}}/logs/gtt_get_accessions.log"
    threads: 4

    run:
        from pathlib import Path
        import subprocess

        # Mapping New Variables to Old Logic
        acc      = wildcards.sample
        genus_path = Path(str(input.genus_file))
        genus    = genus_path.read_text().strip() if genus_path.exists() else "unknown"

        # Output paths
        temp_dir = Path(str(output.temp_dir))
        # The tool writes to temp_dir, but the rule output is the final location:
        out_acc  = Path(str(output.accs))
        out_info = Path(str(output.info))
        out_map  = Path(str(output.map))
        log_path = Path(str(log))

        # Prepare directories
        temp_dir.mkdir(parents=True, exist_ok=True)
        out_acc.parent.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # Skip if no genus (WRITES FINAL OUTPUTS HERE TO SATISFY SNAKEMAKE)
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
        # Skip optional config check for now to simplify

        log_path.write_text("[CMD] " + " ".join(cmd) + "\n")

        # -------------------------
        # 2. Run inside temp dir
        # -------------------------
        # NOTE: Using shell() for simplicity and robust logging inside Snakemake
        shell_cmd = " ".join(cmd)

        subprocess.run(
            shell_cmd,
            cwd=str(temp_dir),
            shell=True,
            stdout=log_path.open("a"),
            stderr=log_path.open("a"),
            check=True # Add check=True to make sure Snakemake catches non-zero exit code
        )

        # -------------------------
        # 3. Find generated files (GTDB accessions writes to CWD/temp_dir)
        # -------------------------
        # We need to find the files written by gtt-get-accessions-from-GTDB inside temp_dir
        # Assuming the generated file name contains '_accs_'
        acc_file  = next(temp_dir.glob("*accs*.txt"), None)
        info_file = next(temp_dir.glob("*info*.tsv"), None)
        map_file  = next(temp_dir.glob("*map*.tsv"), None)

        # -------------------------
        # 4. Move files to FINAL OUTPUT locations
        # -------------------------
        # We must rename these files to the name Snakemake is expecting!
        
        # NOTE: The rule output is: accs: f"{OUT_DIR}/{{sample}}/gtotree/gtdb_accessions.txt"
        # The previous version used 'accessions_for_gtotree.txt'. We will use the simple name here 
        # for clean pathing to the next rule.
        
        # Rename the accessions file
        if acc_file and acc_file.exists():
            acc_file.rename(out_acc)
        else:
            raise Exception(f"Failed to find accession file in {temp_dir}. Check log for tool error.")

        # Rename info and map files
        if info_file and info_file.exists():
            info_file.rename(out_info)
        else:
             out_info.write_text("# No info returned.\n") # Write empty file to satisfy output

        if map_file and map_file.exists():
            map_file.rename(out_map)
        else:
            out_map.touch() # Write empty file to satisfy output

# ----------------------------------------------------------------
# 3E. RUN GToTree WITH GUNUS-SPECIES LABELS (run_gtotree)
# ---------------------------------------------------------------
rule run_gtotree:
    input:
        accessions = rules.gtotree_get_gtdb_accessions.output.accs,
        # The input contigs list points to the assembly.txt file
        contigs    = f"{OUT_DIR}/{{sample}}/gtotree/assembly.txt"
    output:
        tree_dir = directory(f"{OUT_DIR}/{{sample}}/gtotree/gtotree_temp/gtotree_output"),
        marker   = f"{OUT_DIR}/{{sample}}/gtotree/gtotree_temp/gtotree_output/done.txt"
    log:
        f"{OUT_DIR}/{{sample}}/logs/gtotree.log"
    threads: THREADS

    run:
        acc          = wildcards.sample
        accs_file    = Path(str(input.accessions))
        contigs      = Path(str(input.contigs))

        temp_out_dir = Path(output.tree_dir).parent
        final_dir    = Path(output.tree_dir)
        log_path     = Path(str(log))

        temp_out_dir.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)

        # -------------------------
        # 1. Build GToTree command (list-style)
        # -------------------------
        # NOTE: You need to ensure GTOTREE_HMM_DIR is defined globally.
        cmd = [
            "pixi", "run", "-e", "env-b", "GToTree",
            "-a", str(accs_file), # Reference accessions
            "-f", str(contigs),  # Input file list (containing path to assembly.fasta)
            "-H", GTOTREE_HMM_DIR, # The HMM database directory
            "-j", str(threads),
            "-F", # Filter for representative accessions
            "-t", # Use TaxonKit to add lineage info (for reference genomes)
            "-L", "Species", # Specify the desired lineage level for labels
            "-o", str(final_dir),
        ]

        # -------------------------
        # 2. Execute GToTree
        # -------------------------
        log_path.write_text("[INFO] Running GToTree with mapping\n")
        shell(" ".join(cmd) + f" >> {log} 2>&1")

        Path(str(output.marker)).touch()


###############################################################################
# SECTION 4 - FINAL AGGREGATION AND REPORTING 
###############################################################################
# -----------------------------------------------------
# 4A. DASHBOARD GENERATION (Full Implementation)
# -----------------------------------------------------
rule create_dashboard:
    input:
        # These paths are correctly set relative to OUT_DIR/sample/
        quast_html = f"{OUT_DIR}/{{sample}}/qc/quast/report.html",
        quast_tsv  = f"{OUT_DIR}/{{sample}}/qc/quast/report.tsv",
        dfast_json = f"{OUT_DIR}/{{sample}}/qc/dfast_qc/dqc_result.json",
        genus_txt  = f"{OUT_DIR}/{{sample}}/gtotree/genus.txt",
        gtt_done   = f"{OUT_DIR}/{{sample}}/gtotree/gtotree_temp/gtotree_output/done.txt"
    output:
        html = f"{OUT_DIR}/{{sample}}/dashboard/dashboard.html"
    log:
        f"{OUT_DIR}/{{sample}}/logs/dashboard.log"
    
    run:
        acc = wildcards.sample

        # ----------------------------
        # Load QUAST TSV (robust parser)
        # ----------------------------
        quast_data = {}
        # Use Path objects for reliable file access
        quast_tsv_path = Path(input.quast_tsv)
        if quast_tsv_path.exists():
            with quast_tsv_path.open() as f:
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
        dfast_json_path = Path(input.dfast_json)
        dfast = {}
        if dfast_json_path.exists():
            with dfast_json_path.open() as f:
                dfast = json.load(f)

        cc   = dfast.get("cc_result", {})
        gtdb = dfast.get("gtdb_result", {})
        # Note: We don't need tc_result (total contig result) for the summary table.

        genus_path = Path(input.genus_txt)
        genus = genus_path.read_text().strip() if genus_path.exists() else "NA"

        # --- GToTree links ---
        # Relative path calculation: The dashboard is in OUT_DIR/{acc}/dashboard/
        # The GToTree directory is in OUT_DIR/{acc}/gtotree/
        # The relative path from dashboard/ to gtotree/ is just ../gtotree/
        gtt_html_link = "../gtotree/gtotree_temp/gtotree_output/"
        gtt_tree_hint = "*.tre"

        # --- Ensure output dir ---
        outdir = Path(output.html).parent
        outdir.mkdir(parents=True, exist_ok=True)
        Path(str(log)).parent.mkdir(parents=True, exist_ok=True)


        # --- HTML CONTENT (Modified to use correct variables) ---
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
<p><a href='../qc/quast/report.html'>View full QUAST report</a></p>
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
<p><b>Tree files:</b> {gtt_tree_hint}</p>
</div>

</body>
</html>
"""

        Path(output.html).write_text(html)
        Path(str(log)).write_text("[INFO] Dashboard built successfully\n")

# -----------------------------------------------------
# 4B. SUMMARIZE RESULTS
# -----------------------------------------------------
rule summarize_results:
    input:
        genus_files = expand(f"{OUT_DIR}/{{sample}}/gtotree/genus.txt", sample=ALL_SAMPLES),

    output:
        tsv = f"{OUT_DIR}/results_summary.tsv",
        md  = f"{OUT_DIR}/final_report.md"
    params:
        samples = ALL_SAMPLES
    run:
        out_tsv = Path(str(output.tsv))
        out_md  = Path(str(output.md))
        out_tsv.parent.mkdir(parents=True, exist_ok=True)

        # -------------------------
        # 1. Write TSV
        # -------------------------
        lines = ["Accession\tGenus"]
        for acc in params.samples:
            gfile = Path(OUT_DIR) / acc / "gtotree/genus.txt"
            genus = gfile.read_text().strip() if gfile.exists() else "NA"
            lines.append(f"{acc}\t{genus}")

        out_tsv.write_text("\n".join(lines) + "\n")

        # -------------------------
        # 2. Write Markdown
        # -------------------------
        md_lines = [
            "# Taxonomy Summary Report",
            "",
            "## Genus Identification Summary",
            "",
            "| Accession | Genus |",
            "| :--- | :--- |",
        ]

        for acc in params.samples:
            genus_path = Path(OUT_DIR) / acc / "gtotree/genus.txt"
            genus = genus_path.read_text().strip() if genus_path.exists() else "NA"
            md_lines.append(f"| {acc} | {genus} |")

        md_lines += [
            "",
            "## Notes",
            f"* GToTree phylogenies under: `{OUT_DIR}/{{sample}}/gtotree/`",
            "",
        ]

        out_md.write_text("\n".join(md_lines) + "\n")

###############################################################################
# SECTION 5 - RULE ALL (TEMPORARY DFAST-QC TARGET)
###############################################################################
#rule all:
#    input:
#        # 1. Assembly completion marker (ensures assembly is done)
#        expand(f"{OUT_DIR}/{{sample}}/assembly/hybracter_done.flag", sample=ALL_SAMPLES),
#
#        # 2. DFAST-QC's primary output (the target we want to test)
#        expand(f"{OUT_DIR}/{{sample}}/qc/dfast_qc/dqc_result.json", sample=ALL_SAMPLES)

###############################################################################
# SECTION 5 - RULE ALL (TOP-LEVEL TARGETS)
###############################################################################
rule all:
    input:
        # 1. Pipeline Start Point (Assembly check)
        expand(f"{OUT_DIR}/{{sample}}/assembly/hybracter_done.flag", sample=ALL_SAMPLES),
        
        # 2. Final QC Reports (QUAST)
        expand(f"{OUT_DIR}/{{sample}}/qc/quast/report.html", sample=ALL_SAMPLES),
        expand(f"{OUT_DIR}/{{sample}}/qc/quast/report.tsv", sample=ALL_SAMPLES),
        
        # --- NEW TAXONOMY CHAIN DEPENDENCIES ---
        
        # 3. Genus Extraction (Output of extract_genus_name)
        # Note the path: {OUT_DIR}/{sample}/gtotree/genus.txt (This is a small deviation 
        # from your old dfast_qc path, but matches the new extract_genus_name rule output)
        expand(f"{OUT_DIR}/{{sample}}/gtotree/genus.txt", sample=ALL_SAMPLES),
        
        # 4. Final Accession List (Output of gtotree_get_gtdb_accessions)
        expand(f"{OUT_DIR}/{{sample}}/gtotree/gtdb_accessions.txt", sample=ALL_SAMPLES),
        
        # 5. Final GToTree Marker
        expand(f"{OUT_DIR}/{{sample}}/gtotree/gtotree_temp/gtotree_output/done.txt", sample=ALL_SAMPLES),
        
        # 6. Dashboard (Assuming a rule generates this)
        expand(f"{OUT_DIR}/{{sample}}/dashboard/dashboard.html", sample=ALL_SAMPLES),

        # 7. Final summary outputs
        f"{OUT_DIR}/final_report.md",
        f"{OUT_DIR}/results_summary.tsv",
        
        # 8. Raw Data (ensures data is present)
        expand(f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_R1.fastq.gz", sample=SRA_HYBRID.keys()),
        expand(f"{RAW_DATA_DIR}/{{sample}}/hyb_{{sample}}_long.fastq.gz", sample=SRA_HYBRID.keys())


###############################################################################
# END OF PIPELINE
###############################################################################
