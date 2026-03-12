# DRAM2 Guide: Metabolic Annotation via Nextflow

## Overview

**DRAM2** (Distilled and Refined Annotation of Metabolism v2) annotates prokaryotic
genomes and MAGs against multiple functional databases to produce metabolic profiles,
pathway completeness estimates, and interactive summary visualisations.

**Environment:** `env-nf` (Nextflow + Apptainer + OpenJDK 17)  
**Pipeline:** `WrightonLabCSU/DRAM` (branch: `dev`)  
**Database:** ~546 GB at `$EXTERNAL_VAULT/dram_db/`  
**RAM requirement:** ~220 GB with UniRef90 | ~50 GB with KOfam only (no UniRef)

---

## Understanding the conf/ Directory

This is the most commonly misunderstood aspect of DRAM2 for new users.

### What the conf/ files are

When you run `pixi run -e env-nf setup-dram-pipeline`, Nextflow downloads the full
DRAM2 pipeline to:

```
~/.nextflow/assets/WrightonLabCSU/DRAM/
├── nextflow.config          ← main config (includes the conf/ files below)
├── conf/
│   ├── base.config          ← CPU/memory resource requirements per process
│   ├── constants.config     ← pipeline-wide constants (container versions, paths)
│   ├── modules.config       ← per-module publish directory and mode settings
│   └── no_kegg.config       ← alternate resource settings when KEGG is skipped
├── main.nf                  ← main Nextflow workflow
├── modules/                 ← individual process definitions
└── subworkflows/            ← reusable workflow components
```

### Critical point: You do NOT create or edit these files

These conf files are **part of the DRAM2 pipeline source code** — they are downloaded
automatically by Nextflow and live inside `~/.nextflow/assets/WrightonLabCSU/DRAM/conf/`.
They define internal resource allocation (how many CPUs/GB RAM each pipeline step gets)
and are maintained by the WrightonLab team.

**You only interact with one file:** `nextflow.config` in your working directory
(your project root), which you download separately:

```bash
pixi run -e env-nf dram-get-config
# Downloads to: ~/software/taxonomy_bundle/nextflow.config
```

### What each conf file does (reference only)

| File | Purpose | Who edits it |
|------|---------|--------------|
| `conf/base.config` | Default CPU/RAM per Nextflow process label | Pipeline devs only |
| `conf/constants.config` | Container image tags, pipeline version constants | Pipeline devs only |
| `conf/modules.config` | Output publishing rules (copy/symlink, directories) | Pipeline devs only |
| `conf/no_kegg.config` | Reduced resource profile when KEGG db is absent | Pipeline devs only |

### The only file you edit: nextflow.config (in your project root)

This is your local override file. Key settings to check after downloading:

```groovy
// nextflow.config (in ~/software/taxonomy_bundle/)

params {
    max_cpus   = 32        // set to your machine's CPU count
    max_memory = '220.GB'  // set to your available RAM
    max_time   = '240.h'
}

apptainer {
    enabled    = true
    autoMounts = true
}
```

**Location matters:** Nextflow automatically reads `nextflow.config` from the
**directory where you launch the command**. Always run DRAM2 from your project root:
```bash
cd ~/software/taxonomy_bundle
pixi run -e env-nf dram-run
```

---

## Database Structure

The DRAM2 database has a nested structure that often causes confusion:

```
$EXTERNAL_VAULT/dram_db/           ← point --database_dir here
├── databases/                     ← actual annotation databases
│   ├── uniref/       477 GB       ← UniRef90 (largest, optional via --skip_uniref)
│   ├── db_descriptions/ 36 GB    ← functional descriptions lookup
│   ├── kofam/        14 GB        ← KOfam KEGG orthology HMMs
│   ├── pfam/          8.8 GB      ← Pfam protein families
│   ├── vogdb/         4.5 GB      ← Viral orthologous groups
│   ├── merops/        3.6 GB      ← Peptidase database
│   ├── viral/         1.6 GB      ← RefSeq viral sequences
│   ├── camper/        864 MB      ← Carbon/energy metabolism
│   ├── canthyd/       877 MB      ← Carbon/hydrogen cycling
│   ├── dbcan/         202 MB      ← CAZymes (carbohydrate-active enzymes)
│   ├── fegenie/       6.6 MB      ← Iron cycling genes
│   ├── sulfur/        1.7 MB      ← Sulfur cycling genes
│   ├── metals/        58 MB       ← Metal resistance/cycling
│   └── methyl/        56 KB       ← Methylotrophy
├── multiqc/                       ← QC reports from database build
└── pipeline_info/                 ← Nextflow pipeline execution info
```

**Important:** Pass `$EXTERNAL_VAULT/dram_db` as `--database_dir`, NOT
`$EXTERNAL_VAULT/dram_db/databases`. The pipeline resolves the nested path internally.

---

## Input File Requirements

### File format
- Extension must be `.fasta` (not `.fna` or `.fa`)
- DRAM2 uses the filename (minus extension) as the genome identifier throughout all outputs
- Nucleotide sequences only (not protein)
- Can be draft assemblies (multiple contigs per file)

### Renaming .fna to .fasta
```bash
# Single genome
cp genome.fna input_genomes/genome.fasta

# Batch rename
for f in /path/to/genomes/*.fna; do
    base=$(basename "$f" .fna)
    cp "$f" input_genomes/"${base}.fasta"
done
```

### Input directory structure
All genomes must be in a single flat directory (no subdirectories):
```
input_genomes/
├── Hyphomicrobium_sp_NDB2Meth4.fasta
├── bin21.fasta
└── bin22.fasta
```

---

## Running DRAM2

### Standard run (all databases including UniRef90)

```bash
cd ~/software/taxonomy_bundle
mkdir -p input_genomes

# Copy/rename your genome
cp /media/bharat/volume1/databases/test_genome/Hyphomicrobium_sp._NDB2Meth4.fna \
   input_genomes/Hyphomicrobium_sp_NDB2Meth4.fasta

# Run annotation
pixi run -e env-nf dram-run
```

### Memory-constrained run (skip UniRef90, ~50 GB RAM)

If your system has less than 220 GB RAM, skip UniRef90:

```bash
cd ~/software/taxonomy_bundle

nextflow run WrightonLabCSU/DRAM -r dev \
    -profile apptainer \
    --annotate \
    --input_fasta "$PIXI_PROJECT_ROOT/input_genomes" \
    --database_dir "$EXTERNAL_VAULT/dram_db" \
    --outdir "$EXTERNAL_VAULT/dram_results_$(date +%Y%m%d)" \
    -w "$NEXTFLOW_WORK" \
    --skip_uniref
```

### Single genome direct run

```bash
nextflow run WrightonLabCSU/DRAM -r dev \
    -profile apptainer \
    --annotate \
    --input_fasta "/path/to/genome.fasta" \
    --database_dir "$EXTERNAL_VAULT/dram_db" \
    --outdir "$EXTERNAL_VAULT/dram_Hyphomicrobium_$(date +%Y%m%d)" \
    -w "$NEXTFLOW_WORK"
```

### Resume interrupted run

Nextflow caches completed steps. If a run fails or is interrupted:

```bash
pixi run -e env-nf dram-run -resume
# Or directly:
nextflow run WrightonLabCSU/DRAM -r dev ... -resume
```

---

## Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--annotate` | Run annotation step | required |
| `--input_fasta` | Path to dir with `.fasta` files or single `.fasta` | required |
| `--database_dir` | Path to DRAM2 database root | required |
| `--outdir` | Output directory | required |
| `-w` | Nextflow work directory (temp files) | `$NEXTFLOW_WORK` |
| `--skip_uniref` | Skip UniRef90 (saves ~170 GB RAM, reduces annotation depth) | false |
| `-resume` | Resume from last successful checkpoint | — |
| `-profile apptainer` | Use Apptainer containers (required on this system) | — |
| `-r dev` | Use dev branch (required until v2 stable release) | — |

---

## Output Structure

```
$EXTERNAL_VAULT/dram_results_YYYYMMDD/
├── annotations/
│   └── Hyphomicrobium_sp_NDB2Meth4.annotations.tsv   ← per-gene annotations
├── genbank/
│   └── Hyphomicrobium_sp_NDB2Meth4.gbk               ← GenBank format
├── genes/
│   ├── Hyphomicrobium_sp_NDB2Meth4.faa                ← protein sequences
│   └── Hyphomicrobium_sp_NDB2Meth4.fna                ← gene sequences
└── distillate/
    ├── genome_stats.tsv                               ← completeness, quality
    ├── metabolism_summary.xlsx                        ← pathway summary (Excel)
    └── product.html                                   ← interactive visualisation
```

### Most useful outputs

**`metabolism_summary.xlsx`** — the primary deliverable. Contains sheets for:
- Carbon metabolism (methylotrophy, fermentation, aerobic respiration)
- Nitrogen metabolism (fixation, denitrification, nitrification)
- Sulfur cycling
- Electron transport chain
- Energy conservation

**`product.html`** — open in browser for an interactive heatmap of metabolic
pathways across all annotated genomes.

**`annotations.tsv`** — per-gene table with KEGG, Pfam, COG, EC numbers, and
product descriptions.

---

## Troubleshooting

### "Input fasta files must have .fasta extension"
Rename your `.fna` or `.fa` files to `.fasta` — see Input File Requirements above.

### Out of memory errors
Use `--skip_uniref` to reduce RAM requirements from ~220 GB to ~50 GB.

### Nextflow work directory fills disk
The `-w $NEXTFLOW_WORK` directory accumulates cached intermediate files. Clean after
successful runs:
```bash
# Only clean after confirming outputs are complete
nextflow clean -f
# Or remove specific runs:
rm -rf $NEXTFLOW_WORK/xx/yyyyyy...
```

### Pipeline not found
Re-pull the pipeline:
```bash
pixi run -e env-nf setup-dram-pipeline
# Runs: nextflow pull WrightonLabCSU/DRAM -r dev
```

### conf/ files not found error
This means the pipeline was not pulled correctly. The conf/ files live inside
`~/.nextflow/assets/WrightonLabCSU/DRAM/conf/` and are downloaded automatically
by `nextflow pull`. Run `setup-dram-pipeline` again.

---

## Memory Guide for This System

This system (Dell Precision Tower 7810) has the following relevant constraints:

| Config | RAM needed | Time (single MAG) | UniRef used |
|--------|-----------|-------------------|-------------|
| Full (default) | ~220 GB | 2-4 hrs | Yes |
| `--skip_uniref` | ~50 GB | 1-2 hrs | No |
| KOfam only | ~30 GB | <1 hr | No |

Check available RAM before running:
```bash
free -h
# Aim for at least 80% of required RAM to be free before starting
```

---

## Pixi Tasks Reference

```bash
# Pull/update pipeline
pixi run -e env-nf setup-dram-pipeline

# Download nextflow.config template to project root
pixi run -e env-nf dram-get-config

# Verify pipeline + database access
pixi run -e env-nf dram-verify

# Run annotation on input_genomes/
pixi run -e env-nf dram-run

# View all DRAM2 options
pixi run -e env-nf dram-help
```
