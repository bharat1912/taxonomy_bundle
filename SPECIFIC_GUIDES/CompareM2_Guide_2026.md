# CompareM2 Guide 2026
## Genome-to-Report Pipeline — Installation, Database Setup & Usage

**taxonomy_bundle — CompareM2 v2.16.2 via Pixi**
**Bharat Patel — March 2026**

---

## 0. Overview

CompareM2 is a Snakemake-based pipeline that takes prokaryotic genome assemblies (isolates or MAGs) and produces a comprehensive report including quality control, annotation, metabolic analysis, phylogenetics, and comparative genomics. It is designed as a "genomes-to-report" tool, meaning a single command can run the entire workflow.

### Key features

| Rule group | Tools included |
|-----------|----------------|
| Q.C. | CheckM2, assembly-stats, sequence lengths |
| Annotate | Prokka, Bakta |
| Advanced annotate | eggNOG, dbCAN, AntiSMASH, AMRFinder, MLST, KEGG, InterProScan |
| Phylogenetic | GTDB-Tk, Mashtree, FastTree, IQ-TREE, SNP-dists |
| Core-pan | Panaroo |

### Pseudo-rules (shortcuts)

| Pseudo-rule | What it runs |
|-------------|-------------|
| `fast` | Quick rules only (assembly-stats, sequence-lengths) |
| `isolate` | Rules relevant for isolate genomes |
| `meta` | Rules relevant for MAGs |
| `downloads` | Download all databases |
| `report` | Re-render the HTML report |

---

## 1. Installing CompareM2 in Pixi

CompareM2 is installed in the `env-cm2` environment in taxonomy_bundle.

### pixi.toml entries

```toml
[feature.comparem2-stack.dependencies]
python = "3.10.*"
comparem2 = ">=2.16.2"
apptainer = "*"
snakemake = { version = "*", channel = "bioconda" }
# Core tools called by CompareM2 rules
gtdbtk = ">=2.6.1,<3"
hmmer = ">=3.4,<4"
prodigal = "*"
mash = "*"
fasttree = "*"
iqtree = "*"

[feature.comparem2-stack.activation.env]
EXTERNAL_VAULT       = "${EXTERNAL_VAULT:-$PIXI_PROJECT_ROOT/db_local}"
CHECKM2DB            = "$PIXI_PROJECT_ROOT/db_link/checkm2"
GTDBTK_DATA_PATH     = "$PIXI_PROJECT_ROOT/db_link/gtdbtk"
BAKTA_DB             = "$PIXI_PROJECT_ROOT/db_link/bakta"
COMPAREM2_DATABASES  = "$EXTERNAL_VAULT/comparem2_db"
COMPAREM2_CONDA_PREFIX = "$EXTERNAL_VAULT/comparem2_conda"
```

### Verify installation

```bash
cd ~/software/taxonomy_bundle

# Check version
pixi run -e env-cm2 comparem2 --version

# Show help and available rules
pixi run -e env-cm2 comparem2 -h
```

---

## 2. Database Setup — Reusing Existing Vault Databases

CompareM2 manages its databases via **flag files** in a versioned directory structure:

```
$COMPAREM2_DATABASES/cm2_v2.16/<tool>/comparem2_<tool>_database_representative.flag
```

When CompareM2 finds a flag file it skips the download for that tool. This allows us to reuse databases already present in our vault (`/media/bharat/volume1/databases/`) by creating symlinks and flag files.

### Vault databases available for CompareM2

| Tool | Vault path | Size |
|------|-----------|------|
| Bakta | `/media/bharat/volume1/databases/bakta/` | ~90GB |
| CheckM2 | `/media/bharat/volume1/databases/checkm2/` | ~3GB |
| EggNOG | `/media/bharat/volume1/databases/eggnog/` | ~50GB |
| AntiSMASH | `/media/bharat/volume1/databases/antismash/` | ~2GB |
| GTDB-Tk | `/media/bharat/volume1/databases/gtdb_226/` | ~66GB |
| AMRFinder | `/media/bharat/volume1/databases/bakta/amrfinderplus-db/` | ~1GB |
| DBCan | see Section 3 | ~5GB |

### Create symlinks and flag files

Run this once to set up all vault databases for CompareM2:

```bash
CM2_DB="/media/bharat/volume1/databases/comparem2_db/cm2_v2.16"

# Create directory structure
mkdir -p $CM2_DB/{bakta,checkm2,eggnog,dbcan,antismash,gtdb,amrfinder}

# Bakta
ln -sfn /media/bharat/volume1/databases/bakta      $CM2_DB/bakta/db
touch $CM2_DB/bakta/comparem2_bakta_database_representative.flag

# CheckM2
ln -sfn /media/bharat/volume1/databases/checkm2    $CM2_DB/checkm2/db
touch $CM2_DB/checkm2/comparem2_checkm2_database_representative.flag

# EggNOG
ln -sfn /media/bharat/volume1/databases/eggnog     $CM2_DB/eggnog/db
touch $CM2_DB/eggnog/comparem2_eggnog_database_representative.flag

# AntiSMASH
ln -sfn /media/bharat/volume1/databases/antismash  $CM2_DB/antismash/db
touch $CM2_DB/antismash/comparem2_antismash_database_representative.flag

# GTDB-Tk
ln -sfn /media/bharat/volume1/databases/gtdb_226   $CM2_DB/gtdb/db
touch $CM2_DB/gtdb/comparem2_gtdb_database_representative.flag

# AMRFinder (inside Bakta directory)
ln -sfn /media/bharat/volume1/databases/bakta/amrfinderplus-db $CM2_DB/amrfinder/db
touch $CM2_DB/amrfinder/comparem2_amrfinder_database_representative.flag

echo "Vault database symlinks created:"
find $CM2_DB -name "*.flag" | sort
```

### Verify flag files

```bash
find /media/bharat/volume1/databases/comparem2_db/cm2_v2.16 -name "*.flag" | sort
```

Expected output:
```
.../amrfinder/comparem2_amrfinder_database_representative.flag
.../antismash/comparem2_antismash_database_representative.flag
.../bakta/comparem2_bakta_database_representative.flag
.../checkm2/comparem2_checkm2_database_representative.flag
.../dbcan/comparem2_dbcan_database_representative.flag
.../eggnog/comparem2_eggnog_database_representative.flag
.../gtdb/comparem2_gtdb_database_representative.flag
```

---

## 3. Downloading DBCan

DBCan (Carbohydrate-Active enZyme database) is the only database not already present in our vault. CompareM2 uses `dbcan=4` via its own conda environment to download it.

### Current status (March 2026)

> ⚠️ **The bcb.unl.edu server is currently offline** due to a cyberattack. Use the AWS S3 backup instead.

### Download via AWS S3 (recommended)

```bash
# Install AWS CLI if not present
cd ~/software/taxonomy_bundle
pixi run pip install awscli --break-system-packages

# Create DBCan directory
mkdir -p /media/bharat/volume1/databases/comparem2_db/cm2_v2.16/dbcan

# Download from AWS S3 backup
cd /media/bharat/volume1/databases/comparem2_db/cm2_v2.16/dbcan

pixi run aws s3 cp s3://dbcan/db_v5-2_9-13-2025/ . \
    --recursive --no-sign-request \
    2>&1 | tee ~/software/taxonomy_bundle/dbcan_s3_download.log

# Create flag file after successful download
touch /media/bharat/volume1/databases/comparem2_db/cm2_v2.16/dbcan/comparem2_dbcan_database_representative.flag
echo "DBCan download complete"
```

### Download via CompareM2 (when server is restored)

Once the bcb.unl.edu server is back online, CompareM2 can download DBCan automatically:

```bash
cd ~/software/taxonomy_bundle

pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config input_genomes="/path/to/any/genome.fa" \
    output_directory="/tmp/cm2_test" \
    --until downloads
```

### Add DBCan to config YAML

After download, add to `config/config_comparem2.yaml`:

```yaml
set_dbcan--db_dir: "/media/bharat/volume1/databases/comparem2_db/cm2_v2.16/dbcan"
```

---

## 4. Configuration File

CompareM2 uses a YAML config file to pass database paths and parameters. This avoids the Snakemake CLI restriction on hyphenated keys (use `--configfile` not `--config` for these).

### config/config_comparem2.yaml

```yaml
# CompareM2 Configuration
# taxonomy_bundle — March 2026
# Usage: comparem2 --configfile config/config_comparem2.yaml --config input_genomes="..." output_directory="..."

# Annotator: bakta (recommended) or prokka
annotator: "bakta"

# Default output directory (override per run with --config output_directory=...)
output_directory: "results_comparem2"

# Database paths — point to vault to avoid re-downloading
# Bakta (~90GB full database)
set_bakta--db: "/media/bharat/volume1/databases/bakta"

# EggNOG (~50GB)
set_eggnog--data_dir: "/media/bharat/volume1/databases/eggnog"

# CheckM2 (handled by CHECKM2DB env variable in pixi.toml)
# set_checkm2--database_path: "/media/bharat/volume1/databases/checkm2/CheckM2_database/uniref100.KO.1.dmnd"

# AMRFinder (inside Bakta directory)
set_amrfinder--database: "/media/bharat/volume1/databases/bakta/amrfinderplus-db"

# AntiSMASH
set_antismash--databases: "/media/bharat/volume1/databases/antismash"

# DBCan (download from AWS S3 — see Section 3)
# set_dbcan--db_dir: "/media/bharat/volume1/databases/comparem2_db/cm2_v2.16/dbcan"
```

> **Note:** The `--configfile` flag is required (not `--config`) because Snakemake v8.17+ rejects hyphenated keys on the command line. The YAML parser handles them correctly.

### pixi.toml changes required

The following environment variables must be set in `pixi.toml` for the `comparem2-stack` feature:

```toml
[feature.comparem2-stack.activation.env]
COMPAREM2_DATABASES    = "$EXTERNAL_VAULT/comparem2_db"
COMPAREM2_CONDA_PREFIX = "$EXTERNAL_VAULT/comparem2_conda"
CHECKM2DB              = "$PIXI_PROJECT_ROOT/db_link/checkm2"
GTDBTK_DATA_PATH       = "$PIXI_PROJECT_ROOT/db_link/gtdbtk"
BAKTA_DB               = "$PIXI_PROJECT_ROOT/db_link/bakta"
```

> ⚠️ **GitHub note:** After editing `pixi.toml`, commit and push:
> ```bash
> cd ~/software/taxonomy_bundle
> git add pixi.toml config/config_comparem2.yaml
> git commit -m "Add CompareM2 config and vault database symlink setup"
> git push
> ```

---

## 5. Running CompareM2 — Example with GAB MAGs

### Input

| Parameter | Value |
|-----------|-------|
| Genomes | 106 GAB MAGs (CS1BS, CS1GB, POND, SRR) |
| File extension | `.fa` |
| Location | `/media/bharat/volume2/MAGS_2023_Metawrap_final/MAGS_2023/5_BIN_REFINEMENT/metawrap_70_10_bins/` |
| Config | `~/software/taxonomy_bundle/config/config_comparem2.yaml` |

### Basic run — all meta rules

```bash
cd ~/software/taxonomy_bundle

pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config \
        input_genomes="/media/bharat/volume2/MAGS_2023_Metawrap_final/MAGS_2023/5_BIN_REFINEMENT/metawrap_70_10_bins/*.fa" \
        output_directory="/media/bharat/volume1/databases/comparem2_GAB_106bins/" \
    --until meta \
    2>&1 | tee ~/software/taxonomy_bundle/comparem2_GAB_run.log
```

### Dry run first (always recommended)

```bash
cd ~/software/taxonomy_bundle

pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config \
        input_genomes="/media/bharat/volume2/MAGS_2023_Metawrap_final/MAGS_2023/5_BIN_REFINEMENT/metawrap_70_10_bins/*.fa" \
        output_directory="/media/bharat/volume1/databases/comparem2_GAB_106bins/" \
    --until meta \
    --dry-run
```

### Run specific rules only

```bash
# Q.C. only (fast — minutes)
pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config input_genomes="path/to/genomes/*.fa" output_directory="results/" \
    --until checkm2 assembly_stats

# Annotation only
pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config input_genomes="path/to/genomes/*.fa" output_directory="results/" \
    --until bakta

# Phylogenetics only
pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config input_genomes="path/to/genomes/*.fa" output_directory="results/" \
    --until gtdbtk mashtree

# Re-render report only
pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config input_genomes="path/to/genomes/*.fa" output_directory="results/" \
    --until report
```

### Use a file-of-filenames (FOFN) instead of glob

```bash
# Create FOFN
ls /path/to/genomes/*.fa > my_genomes.txt

pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config fofn="my_genomes.txt" output_directory="results/"
```

### Check run status

```bash
cd ~/software/taxonomy_bundle

pixi run -e env-cm2 comparem2 \
    --configfile config/config_comparem2.yaml \
    --config input_genomes="path/to/genomes/*.fa" output_directory="results/" \
    --status
```

---

## 6. Output Files

All outputs are written to `output_directory/` (default: `results_comparem2/`).

### Key output files

| File | Description |
|------|-------------|
| `results_comparem2/report.html` | Main HTML report — open in browser |
| `results_comparem2/checkm2/quality_report.tsv` | Completeness/contamination for all genomes |
| `results_comparem2/assembly-stats/assembly-stats.tsv` | N50, contig count, genome size |
| `results_comparem2/samples/<name>/bakta/<name>.gff` | Bakta annotation per genome |
| `results_comparem2/samples/<name>/bakta/<name>.faa` | Protein sequences per genome |
| `results_comparem2/samples/<name>/eggnog/<name>.emapper.annotations` | EggNOG functional annotations |
| `results_comparem2/samples/<name>/antismash/<name>.json` | BGC predictions |
| `results_comparem2/samples/<name>/dbcan/overview.txt` | CAZyme annotations |
| `results_comparem2/gtdbtk/` | GTDB-Tk taxonomy results |
| `results_comparem2/mashtree/mashtree.nwk` | Mash distance tree |
| `results_comparem2/benchmarks/` | Runtime benchmarks per rule |

---

## 7. Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Invalid config definition` | Hyphen in `--config` key | Use `--configfile` for hyphenated keys |
| `Missing flag file` | Database not found | Create symlink + flag file (Section 2) |
| `SSL certificate error` | bcb.unl.edu offline | Download DBCan from AWS S3 (Section 3) |
| `Singularity not found` | Apptainer not installed | Install apptainer in `pixi.toml` |
| `Snakemake lock` | Previous run crashed | Run `rm -rf results/.snakemake/locks/` |
| `checkm2 DB not found` | `CHECKM2DB` env var not set | Check `pixi.toml` activation env |
| `bakta: database not found` | Wrong db path | Check `set_bakta--db` in config YAML |

---

## 8. Quick Reference

| Task | Command |
|------|---------|
| Check version | `pixi run -e env-cm2 comparem2 --version` |
| Dry run | `comparem2 --configfile config/config_comparem2.yaml --config input_genomes="*.fa" ... --dry-run` |
| Run all meta rules | `... --until meta` |
| Run Q.C. only | `... --until checkm2 assembly_stats` |
| Check status | `... --status` |
| List available rules | `pixi run -e env-cm2 comparem2 -h` |
| Download databases | `... --until downloads` |

---

*taxonomy_bundle — CompareM2 v2.16.2 — https://comparem2.readthedocs.io*
