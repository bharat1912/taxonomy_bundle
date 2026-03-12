# Taxonomy Bundle - Installation & Setup Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Initial Installation](#initial-installation)
3. [External Vault Setup](#external-vault-setup)
4. [Database Installation](#database-installation)
5. [Environment Usage Guide](#environment-usage-guide)
6. [Workflow Execution](#workflow-execution)
7. [Testing Your Installation](#testing-your-installation)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04+ recommended)
- **CPU**: Multi-core processor (8+ cores recommended)
- **RAM**: 32 GB minimum, 64 GB recommended
- **Storage**: 
  - 50 GB for Pixi environments
  - 500+ GB for external databases (on separate drive recommended)

### Required Software
1. **Pixi Package Manager**
   ```bash
   # Install Pixi
   curl -fsSL https://pixi.sh/install.sh | bash
   
   # Verify installation
   pixi --version
   ```

2. **Git** (for cloning repository)
   ```bash
   sudo apt-get install git
   ```

3. **tmux** (for long-running database downloads)
   ```bash
   sudo apt-get install tmux
   ```

---

## Initial Installation

### Step 1: Clone the Repository

```bash
# Clone from GitHub
git clone https://github.com/YOUR_USERNAME/taxonomy_bundle.git
cd taxonomy_bundle
```

### Step 2: Install Pixi Environments

```bash
# Install the default environment (this will take time)
pixi install

# Verify installation
pixi info
```

This will install all environments defined in `pixi.toml`:
- `default` - Core tools and dependencies
- `env-a` - Python 3.9 stack (BIT, Bakta, GTDB-Tk)
- `env-b` - Python 3.12 stack (Snakemake, GToTree)
- `env-busco` - BUSCO 6.x with Python 3.9
- `env-ezaai` - Legacy environment with Java 8
- `env-checkm2` - CheckM2 for genome quality
- `env-auto` - Autocycler workflow environment
- `env-hybracter` - Hybracter hybrid assembly

---

## External Vault Setup

The "vault" is an external storage location for large databases. This keeps your main project directory clean and allows database sharing across projects.

### Step 1: Choose Your Vault Location

Pick a location with plenty of space (500+ GB):
```bash
# Example: External drive
export EXTERNAL_VAULT=/media/YOUR_USERNAME/external_drive/taxonomy_databases

# Example: Secondary internal drive
export EXTERNAL_VAULT=/mnt/data/taxonomy_databases

# Example: Network storage
export EXTERNAL_VAULT=/nfs/shared/databases/taxonomy
```

### Step 2: Make It Permanent

Add to your `~/.bashrc` or `~/.zshrc`:
```bash
echo 'export EXTERNAL_VAULT=/your/chosen/path' >> ~/.bashrc
source ~/.bashrc
```

### Step 3: Create Vault Structure

```bash
# Run the vault setup task
pixi run setup-vault
```

This creates:
- Database directories in `$EXTERNAL_VAULT`
- Symlinks in `db_link/` directory of your project
- All necessary subdirectories

### Step 4: Verify Vault Setup

```bash
# Check vault status
pixi run vault-audit

# Verify symlinks
ls -la db_link/
```

---

## Database Installation

Databases are large and slow to download. It's recommended to use `tmux` sessions for downloads.

### Database Overview

| Database | Size (Download) | Size (Extracted) | Installation Time | Command |
|----------|-----------------|------------------|-------------------|---------|
| Plassembler | 363 MB | ~1 GB | 5-10 min | `pixi run download-plassembler` |
| Bakta | ~62 GB | ~90 GB | 2-6 hours | `pixi run download-bakta` |
| GTDB-Tk | 141 GB | ~250 GB | 6-12 hours | `pixi run download-gtdbtk` |
| CheckM2 | ~3.5 GB | ~4 GB | 30-60 min | `pixi run -e env-checkm2 download-checkm2` |
| Prokka | ~2 GB | ~3 GB | 20-40 min | `pixi run setup-prokka-db` |

### Using tmux for Long Downloads

```bash
# Start a new tmux session
tmux new -s downloads

# Inside tmux, start download
pixi run download-bakta

# Detach from tmux (downloads continue)
# Press: Ctrl+B, then D

# Reattach later to check progress
tmux attach -s downloads

# List all tmux sessions
tmux ls
```

### Recommended Installation Order

1. **Start with Plassembler (quick test)**
   ```bash
   pixi run download-plassembler
   ```

2. **Bakta (needed for many workflows)**
   ```bash
   tmux new -s bakta
   pixi run download-bakta
   # Ctrl+B, D to detach
   ```

3. **GTDB-Tk (largest, run overnight)**
   ```bash
   tmux new -s gtdbtk
   pixi run download-gtdbtk
   # Ctrl+B, D to detach
   ```

4. **CheckM2 (for genome quality)**
   ```bash
   pixi run -e env-checkm2 download-checkm2
   ```

5. **Prokka (for pangenomics)**
   ```bash
   pixi run setup-prokka-db
   ```

### Verifying Database Installation

```bash
# Check what's installed
pixi run vault-audit

# Verify specific database
ls -lh $EXTERNAL_VAULT/bakta/
ls -lh $EXTERNAL_VAULT/gtdb_226/
ls -lh $EXTERNAL_VAULT/plassembler/
```

---

## Environment Usage Guide

### Understanding the Environments

Each environment is designed for specific tools and Python version requirements.

#### **Default Environment**
Core tools available across all workflows.
```bash
# No special flag needed
pixi run <command>
```

#### **env-a (Python 3.9 Stack)**
For: BIT, Bakta, GTDB-Tk, RDP Classifier, Krona
```bash
# Run BIT analysis
pixi run -e env-a bit --help

# Run Bakta annotation
pixi run -e env-a bakta --help

# Run GTDB-Tk
pixi run -e env-a gtdbtk --help
```

#### **env-b (Python 3.12 + Snakemake)**
For: Snakemake workflows, GToTree, BUSCO phylogenomics
```bash
# Run Snakemake workflows
pixi run -e env-b snakemake -s Snakefile_SRAsearch_general.smk --cores 8

# Run GToTree
pixi run -e env-b gtt-hmms --help
```

#### **env-busco (BUSCO 6.x)**
For: BUSCO genome completeness assessment
```bash
# Run BUSCO
pixi run -e env-busco busco --help

# List available datasets
pixi run -e env-busco busco --list-datasets
```

#### **env-ezaai (Legacy Java 8)**
For: EZAAI tool only (requires Java 8)
```bash
# Run EZAAI
pixi run -e env-ezaai ezaai --help
```

#### **env-checkm2**
For: CheckM2 genome quality assessment
```bash
# Run CheckM2
pixi run -e env-checkm2 checkm2 --help

# Download CheckM2 database
pixi run -e env-checkm2 download-checkm2
```

#### **env-auto (Autocycler)**
For: Long-read assembly consensus workflows
```bash
# Run autocycler workflow
pixi run -e env-auto snakemake -s Snakefile_autocycler_Jan15_testing_changes.smk --cores 16
```

#### **env-hybracter**
For: Hybrid assembly with Hybracter
```bash
# Run hybracter workflow
pixi run -e env-hybracter snakemake -s Snakefile_hybracter.smk --cores 16
```

### Common Environment Commands

```bash
# List all environments
pixi info

# List packages in a specific environment
pixi list -e env-a

# Check Python version in an environment
pixi run -e env-a python --version

# Install additional package to an environment
pixi add -e env-a package_name
```

---

## Workflow Execution

### Configuration Files

Each workflow uses a specific config file in the `config/` directory:

| Workflow | Config File | Snakefile |
|----------|-------------|-----------|
| SRA Search | `config/config_SRAsearch.yaml` | `Snakefile_SRAsearch_general.smk` |
| Taxonomy (Hybrid) | `config/config_taxonomy.yaml` | `snakefile_hybrid_taxonomy_16DecX.smk` |
| Taxonomy (Merged) | `config/config_taxonomy_merged.yaml` | `snakefile_hybrid_taxonomy_16DecX.smk` |
| Autocycler | `config/config_auto.yaml` | `Snakefile_autocycler_Jan15_testing_changes.smk` |
| Hybracter | `config/config_hybracter.yaml` | `Snakefile_hybracter.smk` |
| BUSCO | `config/config_busco.yaml` | (Integrated workflow) |

### Workflow 1: SRA Search (Metadata Discovery)

**Purpose**: Search and download metadata from SRA/ENA/GEO databases

**Environment**: `env-a`

**Configuration**: Edit `config/config_SRAsearch.yaml`

```yaml
# Example: Search for hot spring metagenomes
search_filters:
  query: '("hot spring" OR "volcanic") AND (WGS)'
  strategy: "WGS"
  max: 100
  detailed: true
  verbosity: 3
```

**Execute**:
```bash
# Dry run (check syntax)
pixi run -e env-a snakemake -s Snakefile_SRAsearch_general.smk --dry-run

# Run with 8 cores
pixi run -e env-a snakemake -s Snakefile_SRAsearch_general.smk --cores 8
```

**Output**: `sra_search_output/search_data/*.csv`

### Workflow 2: Taxonomy Analysis (Hybrid Assembly)

**Purpose**: Download SRA data, assemble genomes, perform taxonomic classification

**Environment**: `env-b`

**Configuration**: Edit `config/config_taxonomy.yaml`

```yaml
# Example: Hybrid assembly from SRA
sra_hybrid_samples:
  my_hybrid_sample:
    short: "SRR8113456"  # Illumina reads
    long: "SRR8113455"   # PacBio/ONT reads

genome_size_mb: 3.0
target_coverage: 100
trimming_tool: "bbduk"
```

**Execute**:
```bash
# Dry run
pixi run -e env-b snakemake -s snakefile_hybrid_taxonomy_16DecX.smk --dry-run

# Run with 16 cores
pixi run -e env-b snakemake -s snakefile_hybrid_taxonomy_16DecX.smk --cores 16

# Generate workflow DAG
pixi run -e env-b snakemake -s snakefile_hybrid_taxonomy_16DecX.smk --dag | dot -Tpng > workflow.png
```

### Workflow 3: Autocycler (Consensus Assembly)

**Purpose**: Long-read assembly with multiple assemblers for consensus

**Environment**: `env-auto`

**Configuration**: Edit `config/config_auto.yaml`

```yaml
# Example: PacBio CLR assembly
sra:
  accession: "SRR12989396"
  genus_name: "Thermaerobacillus"
  tech_tag: "pacbio_clr"
  genome_size: "3100000"

skip_sra_download: false
read_type: "pacbio_clr"
```

**Execute**:
```bash
# Dry run
pixi run -e env-auto snakemake -s Snakefile_autocycler_Jan15_testing_changes.smk --dry-run

# Run with 16 cores
pixi run -e env-auto snakemake -s Snakefile_autocycler_Jan15_testing_changes.smk --cores 16
```

### Workflow 4: Hybracter (Hybrid Assembly)

**Purpose**: Specialized hybrid assembly with plasmid detection

**Environment**: `env-hybracter`

**Configuration**: Edit `config/config_hybracter.yaml`

```yaml
# Example: Hybrid sample from SRA
hybracter_sra_samples:
  SRR5413257_HYBRID:
    short: "SRR5413257"
    long: "SRR5413256"

genome_size_mb: 1.7
target_coverage: 100
```

**Execute**:
```bash
pixi run -e env-hybracter snakemake -s Snakefile_hybracter.smk --cores 16
```

---

## Testing Your Installation

### Run the Comprehensive Test Script

```bash
# Make script executable
chmod +x test_taxonomy_bundle_setup.sh

# Run full test suite
./test_taxonomy_bundle_setup.sh

# Run quick test (skip database checks)
./test_taxonomy_bundle_setup.sh --skip-databases
```

### Manual Testing

**Test 1: Environment Verification**
```bash
# Check all environments
pixi info

# Test Python versions
pixi run -e env-a python --version   # Should be 3.9.x
pixi run -e env-b python --version   # Should be 3.12.x
```

**Test 2: Tool Availability**
```bash
# Test key tools
pixi run -e env-a bit --version
pixi run -e env-b snakemake --version
pixi run -e env-busco busco --version
pixi run -e env-checkm2 checkm2 --version
```

**Test 3: Vault Setup**
```bash
# Check vault structure
pixi run vault-audit

# Verify symlinks
ls -la db_link/
```

**Test 4: Workflow Dry Runs**
```bash
# Test SRA search workflow
pixi run -e env-a snakemake -s Snakefile_SRAsearch_general.smk --dry-run

# Test taxonomy workflow
pixi run -e env-b snakemake -s snakefile_hybrid_taxonomy_16DecX.smk --dry-run
```

---

## Troubleshooting

### Issue 1: EXTERNAL_VAULT Not Set

**Symptom**: `setup-vault` fails or databases not found

**Solution**:
```bash
# Set the variable
export EXTERNAL_VAULT=/path/to/your/storage

# Make it permanent
echo 'export EXTERNAL_VAULT=/path/to/your/storage' >> ~/.bashrc
source ~/.bashrc

# Re-run vault setup
pixi run setup-vault
```

### Issue 2: Database Download Failures

**Symptom**: Download stops or fails midway

**Solution**:
```bash
# Downloads are resumable with wget -c flag
# Just re-run the command:
pixi run download-bakta

# For interrupted large downloads, check and resume:
cd $EXTERNAL_VAULT/bakta
wget -c https://s3.computational.bio.uni-giessen.de/bakta-db/db-v6.0.tar.xz
```

### Issue 3: Environment Installation Slow

**Symptom**: `pixi install` takes very long or hangs

**Solution**:
```bash
# Update Pixi
curl -fsSL https://pixi.sh/install.sh | bash

# Clear cache and reinstall
rm -rf .pixi
pixi install
```

### Issue 4: Snakemake Workflow Errors

**Symptom**: Workflow fails with "rule X not found" or config errors

**Solution**:
```bash
# Check config file syntax
cat config/config_taxonomy.yaml

# Verify you're in the right environment
pixi run -e env-b snakemake --version

# Use absolute path for Snakefile
pixi run -e env-b snakemake -s $(pwd)/snakefile_hybrid_taxonomy_16DecX.smk --dry-run
```

### Issue 5: Symlink Errors

**Symptom**: "No such file or directory" for databases

**Solution**:
```bash
# Check if vault exists
ls -la $EXTERNAL_VAULT

# Re-create symlinks
pixi run setup-vault

# Manually create if needed
ln -sfn $EXTERNAL_VAULT/bakta $PWD/db_link/bakta
```

### Issue 6: Memory Errors During Assembly

**Symptom**: Unicycler/assembly crashes with "Out of memory"

**Solution**:
```yaml
# Edit config file to reduce memory usage
# In config_taxonomy.yaml or config_taxonomy_merged.yaml:
rule_resources:
  assemble_genome_unicycler:
    mem_mb: 32000  # Reduce if you have less RAM
```

### Issue 7: CheckM2 Database Issues

**Symptom**: CheckM2 can't find database

**Solution**:
```bash
# Download CheckM2 database explicitly
pixi run -e env-checkm2 download-checkm2

# Verify installation
ls -lh $EXTERNAL_VAULT/checkm2/

# Check symlink
ls -la db_link/checkm2
```

---

## Post-Installation Checklist

- [ ] Pixi installed and working (`pixi --version`)
- [ ] Repository cloned (`cd taxonomy_bundle && ls pixi.toml`)
- [ ] All environments installed (`pixi info` shows all envs)
- [ ] EXTERNAL_VAULT set and persistent (`echo $EXTERNAL_VAULT`)
- [ ] Vault structure created (`pixi run setup-vault`)
- [ ] Symlinks verified (`ls -la db_link/`)
- [ ] At least Plassembler DB installed (for testing)
- [ ] Test script passes (`./test_taxonomy_bundle_setup.sh`)
- [ ] Sample workflow dry-run succeeds

---

## Quick Reference Commands

```bash
# Environment Management
pixi info                                    # List all environments
pixi list -e env-a                          # List packages in env-a
pixi run -e env-a <command>                 # Run command in env-a

# Database Management
pixi run setup-vault                        # Create vault structure
pixi run vault-audit                        # Check vault status
pixi run download-plassembler               # Download Plassembler DB
pixi run download-bakta                     # Download Bakta DB
pixi run download-gtdbtk                    # Download GTDB-Tk DB

# Workflow Execution
pixi run -e env-a snakemake -s <snakefile> --dry-run    # Dry run
pixi run -e env-b snakemake -s <snakefile> --cores 16   # Execute
pixi run -e env-b snakemake -s <snakefile> --dag | dot -Tpng > dag.png  # Visualize

# Testing
./test_taxonomy_bundle_setup.sh             # Full test
./test_taxonomy_bundle_setup.sh --skip-databases  # Quick test

# tmux Session Management
tmux new -s <name>                          # Create session
Ctrl+B, D                                   # Detach from session
tmux attach -s <name>                       # Reattach to session
tmux ls                                     # List sessions
```

---

## Support and Documentation

- **Project Repository**: https://github.com/YOUR_USERNAME/taxonomy_bundle
- **Pixi Documentation**: https://pixi.sh
- **Snakemake Documentation**: https://snakemake.readthedocs.io

---

**Version**: 1.0  
**Last Updated**: February 2026  
**Author**: Bharat K.C. Patel
