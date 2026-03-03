# Taxonomy Bundle — Usage Guide

## Quick Reference: Workflows vs Single Commands

### Pipelines (Snakemake workflows — run end-to-end)

| Command | What it does | Config to edit |
|---------|-------------|----------------|
| `pixi run run-autocycler` | Long-read assembly → BUSCO → Bakta annotation | `config/config_auto.yaml` |
| `pixi run run-hybracter` | Hybrid assembly (long + short reads) → QC → annotation | `config/config_hybracter.yaml` |
| `pixi run run-hybrid-taxonomy` | Download SRA → assemble → GTDB-Tk → GToTree → dashboard | `config/config_taxonomy_merged.yaml` |
| `pixi run run-sra-search` | Search NCBI SRA by keyword → download metadata | `config/config_SRAsearch.yaml` |

**Dry-run first (always recommended):**
```bash
pixi run dry-autocycler           # Shows DAG without running
pixi run dry-hybrid-taxonomy      # Check sample names resolve
pixi run dry-sra-search
```

**Resume after interruption:**
```bash
pixi run -e env-a snakemake -s Snakefile_autocycler.smk \
    --configfile config/config_auto.yaml \
    --cores 32 --rerun-triggers mtime
```

---

## Environments

| Environment | Python | Key tools | Use for |
|-------------|--------|-----------|---------|
| `env-a` | 3.9 | snakemake, gtdbtk, bakta, hybracter, autocycler, krona | Main workflows |
| `env-b` | 3.12 | snakemake, gtdbtk, busco | Alternative/newer tools |
| `env-busco` | 3.x | busco | BUSCO quality assessment |
| `env-checkm2` | 3.x | checkm2, dfast_qc | Genome quality |
| `env-cm2` | 3.x | comparem2, snakemake | Comparative genomics |
| `env-pan` | 3.x | PIRATE, panaroo | Pangenomics |
| `env-nf` | 3.x | nextflow | Nextflow pipelines |
| `env-baclife` | 3.x | snakemake | bacLIFE pipeline |
| `env-anti` | 3.x | antismash | Secondary metabolites |
| `env-egg` | 3.x | eggnog-mapper | Functional annotation |
| `env-salmon` | 3.x | salmon | RNA quantification |

**Activate an environment interactively:**
```bash
pixi shell -e env-a           # Drop into env-a shell
pixi shell -e env-busco       # Drop into busco env
exit                          # Leave environment
```

**Run a single tool:**
```bash
pixi run -e env-a gtdbtk --version
pixi run -e env-a bakta --help
pixi run -e env-busco busco --list-datasets
pixi run -e env-checkm2 checkm2 --help
pixi run -e env-cm2 comparem2 --help
pixi run -e env-pan PIRATE --help
```

---

## Single-Tool Commands (pixi tasks)

### Database management
```bash
pixi run setup-vault              # Create vault dirs + symlinks (run first!)
pixi run vault-audit              # Show vault size and contents
pixi run list-db                  # Check all database symlinks
pixi run vault-sync               # Sync local db/ to vault
```

### Database downloads
```bash
# Small (no tmux needed)
pixi run download-plassembler     # 363 MB - plasmid DB
pixi run -e env-checkm2 download-checkm2  # 3.5 GB - quality DB
pixi run setup-prokka-db          # 2 GB   - Prokka DB
pixi run download-busco-prok      # 0.5 GB - BUSCO lineages
pixi run download-dfast-qc        # DFAST-QC reference data
pixi run update-krona-db          # Update Krona taxonomy

# Large (use tmux!)
tmux new -s bakta
pixi run download-bakta           # 62 GB - annotation DB
# Ctrl+B then D to detach

tmux new -s gtdbtk
pixi run download-gtdbtk          # 141 GB - GTDB taxonomy
# Ctrl+B then D to detach

tmux new -s kraken2
pixi run download-kraken2         # 110 GB - Kraken2 k2_pluspf
# Ctrl+B then D to detach
```

### MiGA (taxonomy via MyTaxa)
```bash
pixi run install-miga-gem         # Install MiGA engine
pixi run miga-setup-proxies       # Deploy wrappers
pixi run miga-setup-vault-config  # Configure vault paths
pixi run miga-check-env           # Verify installation
pixi run miga-new-project         # Create new MiGA project
pixi run get-miga-type            # Download TypeMat_Lite (52 GB, use tmux)
```

### Comparative genomics (CompareM2)
```bash
pixi run cm2-help                 # Show CompareM2 options
pixi run cm2-run -- --input ./my_genomes/*.fna --output ./cm2_results
```

### Pangenomics
```bash
pixi run run-pirate               # PIRATE pangenome (results/all_annotations/)
pixi run run-panaroo              # Panaroo pangenome (strict mode)
```

### Utility tools
```bash
pixi run wget_genbank_wgs         # Download GenBank WGS assemblies
pixi run map-isolates             # Generate iTOL mapping table from .faa files
pixi run color-tree               # Generate iTOL color strip
pixi run gan-genus -- --genus Bacillus  # GAN genus lookup
pixi run cm2-run -- --input genomes/ --output results/cm2/
```

### Globus (large file transfer)
```bash
pixi run globus-setup             # Download Globus client
pixi run globus-connect           # Link your account (interactive)
pixi run globus-start             # Start Globus in background
```

---

## Workflow Examples

### Example 1: Assemble a PacBio CLR genome (Autocycler)

1. Edit `config/config_auto.yaml`:
```yaml
# Set your sample
hybracter_local_samples:
  MY_SAMPLE:
    long: input_reads/MY_SAMPLE.fastq.gz
    genome_size: 3000000
    min_length: 1000
```

2. Run:
```bash
pixi run dry-autocycler           # Check DAG first
pixi run run-autocycler           # Full run
```

3. Results in `results/MY_SAMPLE/`:
```
assembly.fasta          # Final assembly
busco/                  # BUSCO completeness
bakta/                  # Genome annotation
```

---

### Example 2: Hybrid assembly (Illumina + Nanopore)

1. Edit `config/config_hybracter.yaml`:
```yaml
hybracter_local_samples:
  STRAIN_001:
    long: input_reads/STRAIN_001_long.fastq.gz
    short1: input_reads/STRAIN_001_R1.fastq.gz
    short2: input_reads/STRAIN_001_R2.fastq.gz
    min_length: 500
```

2. Run:
```bash
pixi run dry-hybracter
pixi run run-hybracter
```

---

### Example 3: Download from SRA + full taxonomy pipeline

1. Edit `config/config_taxonomy_merged.yaml`:
```yaml
# Download from SRA
hybracter_sra_samples:
  SRR12345678:
    genome_size: 3100000
    tech_tag: pacbio_clr

# Or use local files
hybracter_local_samples:
  my_isolate:
    long: input_reads/my_isolate.fastq.gz
```

2. Run:
```bash
pixi run dry-hybrid-taxonomy      # Preview DAG
pixi run run-hybrid-taxonomy      # Full pipeline
```

3. Pipeline runs: download → QC → assembly → DFAST-QC → GTDB-Tk → GToTree → dashboard

---

### Example 4: Search SRA for environmental genomes

1. Edit `config/config_SRAsearch.yaml`:
```yaml
search_terms:
  - "hot spring metagenome WGS"
  - "thermophilic bacteria 16S"
max_results: 50
```

2. Run:
```bash
pixi run run-sra-search
# Results in sra_search_output/
```

---

### Example 5: Comparative genomics with CompareM2

```bash
# Collect your genomes
ls results/*/assembly.fasta > genome_list.txt

# Run CompareM2
pixi run cm2-run -- \
    --input results/*/assembly.fasta \
    --output results/comparem2/ \
    --threads 16
```

---

### Example 6: Pangenome analysis

```bash
# Collect Bakta GFF files
ls results/*/bakta/*.gff3 > gff_list.txt

# Run PIRATE (flexible species)
pixi run run-pirate

# Run Panaroo (same species, high stringency)
pixi run run-panaroo
```

---

## Tips

**Speed up runs:**
```bash
# Use all cores
pixi run -e env-a snakemake -s Snakefile_autocycler.smk \
    --configfile config/config_auto.yaml --cores 32

# Skip already-completed steps
pixi run -e env-a snakemake -s Snakefile_hybrid_taxonomy.smk \
    --configfile config/config_taxonomy_merged.yaml \
    --cores 32 --rerun-triggers mtime
```

**Run in tmux (recommended for long jobs):**
```bash
tmux new -s assembly
pixi run run-autocycler
# Ctrl+B then D to detach safely
tmux attach -s assembly   # Reattach to check progress
```

**Check all available tasks:**
```bash
pixi task list
```

**Check installed tools in an environment:**
```bash
pixi list -e env-a | grep -E "bakta|gtdbtk|autocycler"
```
