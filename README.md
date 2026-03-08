# taxonomy_bundle

A pixi-based bioinformatics workflow bundle for isolate genome taxonomy, annotation, and comparative genomics.

## Prerequisites

### System requirements
- Ubuntu 24.04 LTS (Noble Numbat) — other Linux distros may work but are untested
- 16 GB RAM minimum (32 GB+ recommended for GTDB-Tk and large assemblies)
- 50 GB free on home partition (for pixi environments)
- **1.2 TB+ external storage** for databases (set as `EXTERNAL_VAULT`)

> **Note:** `ruby` and `Java (JRE)` do **not** need to be installed system-wide —
> they are fully managed by pixi within the project environments.

---

## Installation

### 1. Install system dependencies

```bash
sudo apt update && sudo apt install -y \
    git \
    curl \
    wget \
    tmux \
    aria2 \
    rsync \
    unzip \
    build-essential
```

| Package | Purpose |
|---------|---------|
| `git` | Clone this repository and version control |
| `curl` | Install pixi and download tools |
| `wget` | Download databases and tools |
| `tmux` | Keep large downloads running after terminal disconnect |
| `aria2` | Fast multi-connection downloads (used by `download-kraken2`) |
| `rsync` | Vault sync between drives |
| `unzip` / `build-essential` | General build dependencies |

---

### 2. Install Pixi (tested on pixi 0.55.0)

```bash
curl -fsSL https://pixi.sh/install.sh | bash
source ~/.bashrc
pixi --version
```

---

### 3. Clone the repository

```bash
git clone git@github.com:bharat1912/taxonomy_bundle.git
cd taxonomy_bundle
```

---

### 4. Configure the database vault

Databases total ~1.2 TB and must be stored on an external or high-capacity drive.
Set `EXTERNAL_VAULT` in your `~/.bashrc` to point to that drive **before** running
any download tasks.

```bash
# Add to ~/.bashrc — replace with your actual drive path
echo 'export EXTERNAL_VAULT="/media/your_drive/databases"' >> ~/.bashrc
source ~/.bashrc
```

> **Fallback:** If `EXTERNAL_VAULT` is not set, databases will install to
> `taxonomy_bundle/db_local/` — only suitable for testing as this will likely
> exhaust space on your primary drive with full databases.

Verify it is set correctly:

```bash
echo $EXTERNAL_VAULT   # Should print your drive path
```

---

### 5. Install all environments

```bash
pixi install --all
```

> This installs all pixi environments (default, env-a, env-b, env-checkm2,
> env-busco, etc). Takes 10–30 minutes on first run.
>
> **Note:** `pixi install` alone only installs the default environment.
> Use `pixi install --all` to install every environment defined in `pixi.toml`.

---

### 6. Setup vault and database symlinks

```bash
pixi run setup-vault
```

This creates the `db_link/` symlink tree inside the project, pointing all tools
to the correct database locations under `EXTERNAL_VAULT`.

---

### 7. Install MiGA gem

```bash
pixi run install-miga-gem
```

MiGA (Microbial Genomes Atlas) requires a specific Ruby gem (`miga-base 1.4.1.6`)
installed into the pixi Ruby environment. This step handles that — no system-wide
Ruby or gem install is needed.

---

### 8. Download databases

Download databases relevant to your workflow. Each task is independently runnable:

```bash
# Core taxonomy databases
pixi run download-gtdbtk          # GTDB-Tk r226 (~66 GB)
pixi run download-checkm2         # CheckM2 (~3 GB)
pixi run download-kraken2         # Kraken2 standard (~100 GB)
pixi run download-bakta-db        # Bakta annotation DB (~70 GB)

# MiGA reference databases
pixi run download-miga-typemat    # TypeMat_Lite — type strain genomes (~50 GB)
pixi run download-miga-phyla      # Phyla_Lite (~5 GB)

# DFAST_QC reference
pixi run download-dfast-qc        # DFAST_QC compact reference (<2 GB)
pixi run download-dfast-qc-gtdb-genomes  # Full GTDB genomes for offline search (~127 GB extracted)
```

> **Tip:** Run all large downloads inside a `tmux` session so they continue
> after terminal disconnect:
> ```bash
> tmux new -s downloads
> # run download commands here
> # Detach: Ctrl+B then D
> ```

---

## Quick start

```bash
# Taxonomy classify a single isolate genome
pixi run miga classify_wf \
    --db-path $MIGA_HOME/TypeMat_Lite \
    --type genome \
    -o results/miga_classify \
    genome.fasta

# GTDB taxonomy + quality check for an isolate
pixi run -e env-checkm2 dfast-qc-isolate \
    -i genome.fasta \
    -o results/dfast_qc/sample_name \
    -n 8
```

---

## Tool environments

| Environment | Key tools |
|-------------|-----------|
| `default` | MiGA, GTDB-Tk, Bakta, PHANTASM, BIT, GToTree, PhyKit |
| `env-a` | Bakta, RDP Classifier, OGRI, env-specific tools |
| `env-b` | Additional annotation and comparative tools |
| `env-checkm2` | DFAST_QC, CheckM2 |
| `env-busco` | BUSCO 6 |
| `env-pan` | PIRATE, Panaroo pangenome tools |

---

## Database storage summary

| Database | Tool | Size |
|----------|------|------|
| GTDB-Tk r226 | GTDB-Tk | ~66 GB |
| TypeMat_Lite | MiGA | ~50 GB |
| GTDB genomes (reps) | MiGA / DFAST_QC | ~127 GB extracted |
| Kraken2 standard | Kraken2 | ~100 GB |
| Bakta DB | Bakta | ~70 GB |
| CheckM2 | CheckM2 | ~3 GB |
| DFAST_QC ref | DFAST_QC | ~2 GB compact / full >100 GB |
| DRAM2 | DRAM2 | ~600 GB |
| Other tools | Various | ~100 GB |
| **Total** | | **~1.2 TB** |

---

## Notes on tool selection

- **Isolate taxonomy:** Use `dfast-qc-isolate` (GTDB search) — fast, suitable for
  well-characterised species with GTDB representatives
- **MAG taxonomy (environmental bins):** Use MiGA (`classify_wf` or daemon) +
  GTDB-Tk — handles novel/underrepresented taxa not in GTDB representative set
- **Completeness/contamination:** Use CheckM2 directly or via Snakemake workflows

---

## Citing tools

If you use this bundle please cite the individual tools used in your analysis.
Key citations include MiGA, GTDB-Tk, Bakta, DFAST_QC, CheckM2, PHANTASM, and
BIT as appropriate.
