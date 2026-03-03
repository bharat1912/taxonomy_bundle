# ============================================================
# Snakefile_SRAsearch_general.smk
# Modular SRA / ENA / GEO Metadata Search Pipeline
# Author: Bharat K.C. Patel
# ============================================================

import os
import sys
from pathlib import Path

# NEUTRALIZING MANEUVER: Add the project root to the Python Path
# This ensures Python can see the 'scripts' folder as a module
sys.path.append(os.getcwd())

# Change from lib.helpers import slugify, build_search_flags to:
from scripts.helpers import slugify, build_search_flags

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------
configfile: "config/config_SRAsearch.yaml"
#configfile: "config/config_SRAAnoxybacillus.yaml"

OUTPUT_DIR = Path("sra_search_output")
SEARCH_DIR = OUTPUT_DIR / "search_data"
PROJECT_DIR = OUTPUT_DIR / "project_data"
LOGS_DIR = OUTPUT_DIR / "logs"

for d in [SEARCH_DIR, PROJECT_DIR, LOGS_DIR]:
    d.mkdir(parents=True, exist_ok=True)

# ============================================================
# METADATA PROTOCOL GUIDANCE
# ------------------------------------------------------------
# 1. SEARCH MODE: Use 'search_filters' for discovery (Taxa, Boolean queries).
#    Options: query, platform, strategy, selection, detailed, verbosity.
# 2. PROJECT MODE: Use 'sra_project' for known IDs (PRJNA, SRP, ERP).
#    Options: detailed, suppress_one_to_many_warning.
# 3. DOI MODE: Use 'doi_conversion' for paper-to-SRA mapping.
# ============================================================

def get_workflow_target():
    if "doi_conversion" in config:
        # New DOI logic: uses the filename specified in YAML or a default
        out_name = config["doi_conversion"].get("output", "doi_identifiers.tsv")
        return str(SEARCH_DIR / out_name)

    elif "search_filters" in config:
        # Existing search logic...
        f = config["search_filters"]
        name = slugify([f.get("query", ""), f.get("strategy", ""), f.get("selection", "")])
        return str(SEARCH_DIR / f"{name}.csv")

    elif "sra_project" in config:
        # Existing project logic...
        proj = config["sra_project"]
        detailed = config.get("metadata_options", {}).get("detailed", False)
        suffix = "_detailed_metadata.csv" if detailed else "_metadata.csv"
        return str(PROJECT_DIR / f"{proj}{suffix}")

    else:
        raise ValueError("Config must define 'search_filters', 'sra_project', or 'doi_conversion'.")

# Determine which mode we’re in
if "doi_conversion" in config:
    MODE = "doi"
elif "search_filters" in config:
    MODE = "search"
else:
    MODE = "project"

TARGET_FILE = Path(get_workflow_target())

# ------------------------------------------------------------
# RULE ALL
# ------------------------------------------------------------
rule all:
    input:
        str(TARGET_FILE)

# ============================================================
# RULE: sra_search
# ============================================================
if MODE == "search":
    rule sra_search:  # This must be indented 4 spaces
        output:
            str(TARGET_FILE)
        params:
            search_flags=lambda w: build_search_flags(config.get("search_filters", {}))
        log:
            LOGS_DIR / "sra_search.log"
        shell:
            """
            echo "=== pysradb metadata search ===" > {log}
            # Add this line to see the exact command in your log
            echo "Running: pysradb search {params.search_flags} --saveto {output}" >> {log}
            
            # Execute
            pysradb search {params.search_flags} --saveto {output} >> {log} 2>&1 || true

            if [ ! -s {output} ]; then
                echo "[WARN] Search produced no results." >> {log}
                touch {output}
            fi
            """

# ============================================================
# RULE: fetch_project_metadata
# ------------------------------------------------------------
# Active only in PROJECT mode
# ============================================================
if MODE == "project":
    rule fetch_project_metadata:
        output:
            str(TARGET_FILE)
        params:
            project_id=lambda w: config.get("sra_project"),
            metadata_flags=lambda w: " ".join(
                [f"--{k}" for k, v in config.get("metadata_options", {}).items() if v]
            )
        log:
            LOGS_DIR / "project_metadata.log"
        shell:
            """
            echo "=== pysradb project metadata fetch ===" > {log}
            echo "Command: pysradb metadata {params.metadata_flags} {params.project_id}" >> {log}
            pysradb metadata {params.metadata_flags} {params.project_id} --saveto {output} >> {log} 2>&1 || true

            if [ ! -s {output} ]; then
                echo "[WARN] No project metadata found for {params.project_id}" >> {log}
                touch {output}
            fi
            """

# ============================================================
# RULE: summarize_random_selection
# ------------------------------------------------------------
# Optional diagnostic table summarizing RANDOM vs PCR counts
# ============================================================
rule summarize_random_selection:
    input:
        str(TARGET_FILE)
    output:
        OUTPUT_DIR / "summary_RANDOM_vs_PCR.tsv"
    run:
        import pandas as pd
        from pathlib import Path

        f = input[0]
        if not Path(f).exists() or Path(f).stat().st_size == 0:
            print(f"[WARN] Input {f} missing or empty — skipping summary.")
            Path(output[0]).touch()
            raise SystemExit(0)

        df = pd.read_csv(f, sep=",", low_memory=False)
        if "experiment_library_selection" in df.columns:
            summary = df["experiment_library_selection"].value_counts()
            summary.to_csv(output[0], sep="\t")
            print(f"[INFO] Summary written: {output[0]}")
        else:
            print("[WARN] 'experiment_library_selection' column missing.")
            Path(output[0]).touch()

# ============================================================
# RULE: doi_to_identifiers
# ------------------------------------------------------------
# Active only in DOI mode
# ============================================================
if MODE == "doi":
    rule doi_to_identifiers:
        output:
            str(TARGET_FILE)
        params:
            doi = lambda w: config["doi_conversion"].get("doi")
        log:
            LOGS_DIR / "doi_conversion.log"
        shell:
            """
            echo "=== pysradb DOI to Identifier conversion ===" > {log}
            pysradb doi-to-identifiers '{params.doi}' --saveto {output} >> {log} 2>&1
            """
