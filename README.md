# taxonomy_bundle

A pixi-based bioinformatics workflow bundle for isolate genome taxonomy, annotation, and comparative genomics.

## Overview

This repository provides reproducible workflows for:
- **Long-read assembly** — Autocycler-based assembly pipeline
- **Hybrid assembly** — Hybracter (long + short reads)
- **Taxonomy & annotation** — GTDB-Tk, Bakta, DFAST-QC, GToTree
- **SRA data retrieval** — Automated download and search

## Requirements

- [pixi](https://pixi.sh) package manager
- External storage vault (set `EXTERNAL_VAULT` in `.env`)

## Setup
```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/taxonomy_bundle.git
cd taxonomy_bundle

# 2. Copy and configure environment
cp .env.template .env
# Edit .env with your local paths

# 3. Install all environments
pixi install

# 4. Setup databases and vault
pixi run setup-vault
```

## Workflows

| Task | Command | Config |
|------|---------|--------|
| Long-read assembly | `pixi run run-autocycler` | `config/config_auto.yaml` |
| Hybrid assembly | `pixi run run-hybracter` | `config/config_hybracter.yaml` |
| Taxonomy & annotation | `pixi run run-hybrid-taxonomy` | `config/config_taxonomy_merged.yaml` |
| SRA search | `pixi run run-sra-search` | `config/config_SRAsearch.yaml` |

## Dry runs (test without executing)
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
