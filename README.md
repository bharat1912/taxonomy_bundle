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

The full suite totals ~1.2 TB. **You do not need all databases to get started.**
Each database is downloaded independently — add them one at a time as your work expands.

> **Note:** Adding a database later requires just one command — no reinstallation needed:
> ```bash
> pixi run download-kraken2       # add Kraken2 any time after initial setup
> pixi run download-miga-typemat  # add MiGA type strain DB when needed
> ```

### Tier 1 — Starter set (~150 GB) — isolate genomics

| Database | Tool | Size | Download command | Purpose |
|----------|------|------|-----------------|---------|
| GTDB-Tk r226 | GTDB-Tk | ~66 GB | `pixi run download-gtdbtk` | Species-level taxonomy |
| CheckM2 | CheckM2 | ~3 GB | `pixi run download-checkm2` | Genome completeness / contamination |
| Bakta DB | Bakta | ~70 GB | `pixi run download-bakta-db` | Full genome annotation |
| DFAST_QC compact | DFAST_QC | ~2 GB | `pixi run download-dfast-qc` | Quick taxonomy + QC check |

> A **500 GB external SSD** is sufficient for Tier 1. This is the recommended starting point.

### Tier 2 — Extended set (~400 GB additional) — adds metagenomics + MiGA

| Database | Tool | Size | Download command | Purpose |
|----------|------|------|-----------------|---------|
| TypeMat_Lite | MiGA | ~50 GB | `pixi run download-miga-typemat` | Type strain taxonomy (28,548 genomes) |
| Phyla_Lite | MiGA | ~5 GB | `pixi run download-miga-phyla` | Phylum-level classification |
| GTDB genomes (reps) | MiGA / DFAST_QC | ~127 GB | `pixi run download-dfast-qc-gtdb-genomes` | Offline GTDB search |
| Kraken2 standard | Kraken2 | ~100 GB | `pixi run download-kraken2` | Read-level taxonomic profiling |
| MyTaxa | MiGA | ~50 GB | `pixi run download-mytaxa` | Gene-based taxonomy screening |

### Tier 3 — Full suite (~650 GB additional) — adds metabolic annotation

| Database | Tool | Size | Download command | Purpose |
|----------|------|------|-----------------|---------|
| DRAM2 | DRAM2 | ~600 GB | `pixi run download-dram2` | Full metabolic annotation |
| BUSCO lineages | BUSCO | ~10 GB | `pixi run download-busco-prok` | Lineage-specific completeness |
| eggNOG | eggNOG-mapper | ~30 GB | `pixi run download-eggnog` | Functional annotation + COG |

### Cumulative storage by tier

| What you download | Storage needed |
|-------------------|---------------|
| Tier 1 only | ~150 GB |
| Tier 1 + Tier 2 | ~550 GB |
| Tier 1 + Tier 2 + Tier 3 | **~1.2 TB** |

---

## WSL2 users — additional setup

### Increase RAM allocation (important for GTDB-Tk and large assemblies)

By default WSL2 uses only 50% of your system RAM. For bioinformatics workloads
create a `.wslconfig` file on the **Windows** side:

```
# File location: C:\Users\YourWindowsUsername\.wslconfig
[wsl2]
memory=24GB
processors=8
```

Adjust `memory` and `processors` to match your hardware. Restart WSL2 after saving:
```powershell
# In PowerShell (Windows side)
wsl --shutdown
# Then reopen Ubuntu
```

### Windows drive paths inside WSL2

Your Windows drives are mounted automatically inside WSL2:
- C: drive → `/mnt/c/`
- D: drive → `/mnt/d/`
- External SSD → `/mnt/e/` (or similar)

Set `EXTERNAL_VAULT` to point to your external drive:
```bash
echo 'export EXTERNAL_VAULT="/mnt/d/databases"' >> ~/.bashrc
source ~/.bashrc
```

> **Performance note:** Large database operations (GTDB-Tk, DRAM2) run faster
> when databases are stored on the native WSL2 filesystem (`~/` or `/home/`)
> rather than on a Windows NTFS drive (`/mnt/d/`). For databases you access
> frequently, consider copying them to the WSL2 filesystem if space allows.

---

## Starter database set (~141 GB)

The full database suite is ~1.2 TB. You do not need all of it to get started.
Databases can be added at any time with a single command — no reinstallation needed.

| Database | Tool | Size | Pixi task | Good for |
|----------|------|------|-----------|----------|
| GTDB-Tk r226 | GTDB-Tk | ~66 GB | `download-gtdbtk` | Species-level taxonomy |
| CheckM2 | CheckM2 | ~3 GB | `download-checkm2` | Genome completeness & contamination |
| Bakta v6 | Bakta | ~70 GB | `download-bakta-db` | Gene annotation |
| DFAST_QC compact | DFAST_QC | ~2 GB | `download-dfast-qc` | Quick isolate taxonomy check |
| **Starter total** | | **~141 GB** | | |

### Add more databases later — one command each, no reinstallation needed

```bash
pixi run download-kraken2                    # Kraken2 k2_pluspf (~100 GB)
pixi run download-miga-typemat               # MiGA TypeMat_Lite (~50 GB)
pixi run download-miga-phyla                 # MiGA Phyla_Lite (~5 GB)
pixi run download-dfast-qc-gtdb-genomes      # DFAST_QC full GTDB (~127 GB extracted)
pixi run download-busco-prok                 # BUSCO prokaryotic lineages (~10 GB)
```

> **DRAM2 note:** The DRAM2 metabolic annotation database (~600 GB) is the
> largest single database. It is only needed for deep metabolic pathway analysis.
> Most isolate genomics workflows do not require it to get started.

---

## Notes on tool selection

- **Isolate taxonomy:** Use `dfast-qc-isolate` (GTDB search) — fast, suitable for
  well-characterised species with GTDB representatives
- **MAG taxonomy (environmental bins):** Use MiGA (`classify_wf` or daemon) +
  GTDB-Tk — handles novel/underrepresented taxa not in GTDB representative set
- **Completeness/contamination:** Use CheckM2 directly or via Snakemake workflows

---

## Running on Windows via WSL2

taxonomy_bundle runs identically on Windows using WSL2 (Windows Subsystem for Linux).
WSL2 provides a real Ubuntu Linux environment built into Windows 10/11 — not a virtual machine.

### WSL2 setup (one-time)

Open PowerShell as Administrator:
```powershell
wsl --install
```
Restart your computer. Ubuntu opens automatically. Set a username and password.

> **Institutional computers:** If your machine is managed by a university or hospital IT department,
> you may need admin rights or IT assistance to enable WSL2 and virtualisation in BIOS.

### Increase WSL2 memory allocation (recommended)

WSL2 defaults to 50% of system RAM. For GTDB-Tk and large assemblies, increase this:

Create the file `C:\Users\YourName\.wslconfig` on Windows with:
```ini
[wsl2]
memory=24GB
processors=8
```
Restart WSL2: `wsl --shutdown` in PowerShell, then reopen Ubuntu.

### Database paths in WSL2

Windows drives are accessible inside WSL2 as `/mnt/c/`, `/mnt/d/` etc.
Set your vault to an external drive:
```bash
echo 'export EXTERNAL_VAULT="/mnt/d/databases"' >> ~/.bashrc
source ~/.bashrc
```

> **Performance note:** For large jobs, databases stored on Windows NTFS drives (`/mnt/d/`) are
> slower than the native WSL2 filesystem. If possible, store databases on a dedicated Linux-formatted
> drive or within the WSL2 filesystem (`~/`).

### What works identically on WSL2
- All pixi environments and tools ✓
- All Snakemake workflows ✓
- All database download tasks ✓
- Ruby/gem (MiGA) managed by pixi — no system install needed ✓
- Java managed by pixi — no system install needed ✓

---

## Citing tools


If you use this bundle please cite the individual tools used in your analysis.
Key citations include MiGA, GTDB-Tk, Bakta, DFAST_QC, CheckM2, PHANTASM, and
BIT as appropriate.
