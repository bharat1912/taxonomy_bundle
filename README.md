# taxonomy_bundle

A pixi-based bioinformatics workflow bundle for isolate genome taxonomy, annotation, and comparative genomics.

## Prerequisites

### System requirements
- Ubuntu 24.04 LTS (Noble Numbat) — other Linux distros may work but are untested
- 16 GB RAM minimum (32 GB+ recommended for GTDB-Tk and large assemblies)
- 50 GB free on home partition (for pixi environments)
- 500 GB+ external storage for databases (set as `EXTERNAL_VAULT`)

### 1. Install system dependencies
```bash
sudo apt update && sudo apt install -y \
    git \
    curl \
    wget \
    tmux \
    aria2 \
    ruby \
    default-jre \
    rsync \
    unzip \
    build-essential
```

- **git** — clone this repository and version control
- **curl / wget** — download databases and tools
- **tmux** — keep large downloads running after terminal disconnect
- **aria2** — fast multi-connection downloads (used by `download-kraken2`)
- **ruby + gem** — required for MiGA taxonomy engine
- **java (default-jre)** — required for AliView sequence viewer
- **rsync** — vault sync between drives
- **unzip / build-essential** — general build dependencies

### 2. Install Pixi (tested on pixi 0.55.0)
```bash
curl -fsSL https://pixi.sh/install.sh | bash
source ~/.bashrc
pixi --version
```

### 3. Clone the repository
```bash
git clone git@github.com:bharat1912/taxonomy_bundle.git
cd taxonomy_bundle
```

### 4. Configure environment
```bash
cp .env.template .env
# Edit .env with your local paths:
# EXTERNAL_VAULT=/path/to/your/external/storage
# PIXI_PROJECT_ROOT=/path/to/taxonomy_bundle
nano .env
```

### 5. Install all environments
```bash
pixi install
```
This installs all pixi environments (env-a, env-b, env-busco, etc). Takes 10-30 minutes on first run.

### 6. Setup vault and database links
```bash
pixi run setup-vault
```

## Overview

Reproducible workflows for:
- **Long-read assembly** — Autocycler-based pipeline
- **Hybrid assembly** — Hybracter (long + short reads)
- **Taxonomy & annotation** — GTDB-Tk, Bakta, DFAST-QC, GToTree
- **SRA data retrieval** — Automated download and search

## Workflows

| Task | Command | Config |
|------|---------|--------|
| Long-read assembly | `pixi run run-autocycler` | `config/config_auto.yaml` |
| Hybrid assembly | `pixi run run-hybracter` | `config/config_hybracter.yaml` |
| Taxonomy & annotation | `pixi run run-hybrid-taxonomy` | `config/config_taxonomy_merged.yaml` |
| SRA search | `pixi run run-sra-search` | `config/config_SRAsearch.yaml` |

## Test without data (dry runs)
```bash
pixi run dry-autocycler
pixi run dry-hybracter
pixi run dry-hybrid-taxonomy
pixi run dry-sra-search
```

## Database downloads
```bash
pixi run download-gtdbtk      # GTDB-Tk r226 (141GB)
pixi run download-bakta       # Bakta v6
pixi run download-checkm2     # CheckM2
pixi run download-kraken2     # Kraken2 k2_pluspf
pixi run download-busco-prok  # BUSCO prokaryotic lineages
```

## Directory structure
```
taxonomy_bundle/
├── Snakefile_autocycler.smk       # Long-read assembly
├── Snakefile_hybracter.smk        # Hybrid assembly
├── Snakefile_hybrid_taxonomy.smk  # Taxonomy & annotation
├── Snakefile_SRAsearch.smk        # SRA search
├── config/                        # Workflow configs
├── scripts/                       # Helper scripts
├── raw_data/                      # Input reads (gitignored)
├── local_data/                    # Local genomes (gitignored)
├── results/                       # Pipeline outputs (gitignored)
└── logs/                          # Run logs (gitignored)
```

## Tested on
- Ubuntu 24.04 LTS (Noble Numbat)
- pixi 0.55.0
- x86_64 architecture
