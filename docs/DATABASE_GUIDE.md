# Database Installation & Management Guide

## Overview

Taxonomy Bundle uses an external vault system to manage large bioinformatics databases efficiently. This guide covers database installation, verification, and troubleshooting.

---

## Table of Contents

1. [Vault System Overview](#vault-system-overview)
2. [Database Inventory](#database-inventory)
3. [Installation Instructions](#installation-instructions)
4. [Verification Methods](#verification-methods)
5. [Troubleshooting](#troubleshooting)
6. [Maintenance](#maintenance)

---

## Vault System Overview

### Architecture

```
EXTERNAL_VAULT/                     # External storage location
├── bakta/                          # Bakta annotation database
├── gtdb_226/                       # GTDB-Tk r226 release
├── plassembler/                    # Plassembler plasmid database
├── checkm2/                        # CheckM2 quality database
├── taxonkit/                       # TaxonKit NCBI taxonomy
├── busco/                          # BUSCO datasets
├── dfast_qc_ref/                   # DFAST-QC reference
├── prokka_db/                      # Prokka annotation database
├── mytaxa/                         # MyTaxa taxonomy database
├── krona/                          # Krona taxonomy database
└── tmp/                            # Temporary storage

PROJECT_ROOT/db_link/               # Symlinks to vault (portable)
├── bakta -> $EXTERNAL_VAULT/bakta
├── gtdbtk -> $EXTERNAL_VAULT/gtdb_226
├── plassembler -> $EXTERNAL_VAULT/plassembler
└── ...
```

### Benefits

- **Space Efficiency**: Databases stored once, accessible from multiple projects
- **Portability**: Project remains small; only symlinks included in Git
- **Flexibility**: Easy to move vault to larger storage without breaking workflows
- **Performance**: Vault can be on fastest available drive

---

## Database Inventory

### Priority Database Installation Order

#### 1. Plassembler (TESTING - Install First)
- **Size**: 363 MB download, ~1 GB extracted
- **Time**: 5-10 minutes
- **Purpose**: Plasmid detection from assemblies
- **Workflows**: Autocycler, Hybracter
- **Installation**: `pixi run download-plassembler`

**Why install first**: Small size makes it perfect for testing the vault system.

#### 2. CheckM2 (QUALITY ASSESSMENT)
- **Size**: ~3.5 GB download, ~4 GB extracted
- **Time**: 30-60 minutes
- **Purpose**: Genome completeness and contamination assessment
- **Workflows**: Most assembly workflows
- **Installation**: `pixi run -e env-checkm2 download-checkm2`

**Essential for**: Validating assembly quality before annotation.

#### 3. Bakta (ANNOTATION - Critical)
- **Size**: ~62 GB download, ~90 GB extracted
- **Time**: 2-6 hours (network dependent)
- **Purpose**: Rapid & standardized genome annotation
- **Workflows**: Taxonomy workflows, general annotation
- **Installation**: `pixi run download-bakta`

**Why critical**: Required for most annotation workflows; modern replacement for Prokka.

#### 4. GTDB-Tk (TAXONOMY - Large)
- **Size**: 141 GB download, ~250 GB extracted
- **Time**: 6-12 hours
- **Purpose**: Taxonomic classification using GTDB database
- **Workflows**: Taxonomy classification workflows
- **Installation**: `pixi run download-gtdbtk`

**Note**: Largest database; run overnight in tmux session.

#### 5. Prokka (ANNOTATION - Alternative)
- **Size**: ~2 GB download, ~3 GB extracted
- **Time**: 20-40 minutes
- **Purpose**: Alternative annotation system; required for pangenomics
- **Workflows**: Pangenome analysis, legacy pipelines
- **Installation**: `pixi run setup-prokka-db`

**Use case**: Pangenome workflows; legacy compatibility.

#### 6. BUSCO Datasets (QUALITY - On-demand)
- **Size**: Variable (300-500 MB per lineage)
- **Time**: 5-15 minutes per dataset
- **Purpose**: Gene set completeness assessment
- **Workflows**: BUSCO quality assessment
- **Installation**: Auto-downloaded when BUSCO runs

**Note**: Downloaded automatically by BUSCO based on organism lineage.

---

## Installation Instructions

### Prerequisites

Before installing databases:

```bash
# 1. Verify EXTERNAL_VAULT is set
echo $EXTERNAL_VAULT
# Should output: /your/vault/path

# 2. Verify vault structure exists
pixi run setup-vault

# 3. Check available space
df -h $EXTERNAL_VAULT
# Need: 500+ GB free for all databases
```

### Installation Methods

#### Method 1: Quick Test Installation (Plassembler)

Use this to test the system before committing to large downloads:

```bash
# Test the vault system with small database
pixi run download-plassembler

# Verify installation
ls -lh $EXTERNAL_VAULT/plassembler/
# Should see: plsdb_2023_11_03_v2.msh and other files

# Verify symlink
ls -la db_link/plassembler
# Should point to: $EXTERNAL_VAULT/plassembler
```

#### Method 2: Standard Installation (Medium Databases)

For CheckM2, Prokka, and other medium-sized databases:

```bash
# CheckM2 (recommended for quality assessment)
pixi run -e env-checkm2 download-checkm2

# Verify
ls -lh $EXTERNAL_VAULT/checkm2/
checkm2 database --list

# Prokka (for pangenomics)
pixi run setup-prokka-db

# Verify
ls -lh $EXTERNAL_VAULT/prokka_db/
```

#### Method 3: tmux Installation (Large Databases)

**CRITICAL**: Use tmux for Bakta and GTDB-Tk to prevent download interruption.

##### Installing Bakta

```bash
# 1. Create tmux session
tmux new -s bakta

# 2. Inside tmux, start download
pixi run download-bakta

# 3. Monitor progress
# Watch for download completion messages

# 4. Detach safely (download continues)
# Press: Ctrl+B, then D

# 5. Reattach later to check progress
tmux attach -s bakta

# 6. When complete, verify
ls -lh $EXTERNAL_VAULT/bakta/
# Should see: db/ directory with ~90 GB data
```

##### Installing GTDB-Tk

```bash
# 1. WARNING: This is 141 GB download + 250 GB extracted
# 2. Ensure you have 400+ GB free space
df -h $EXTERNAL_VAULT

# 3. Create dedicated tmux session
tmux new -s gtdbtk

# 4. Start download (run overnight)
pixi run download-gtdbtk

# 5. Detach and check next day
# Press: Ctrl+B, then D

# 6. Verify installation (takes time)
tmux attach -s gtdbtk
ls -lh $EXTERNAL_VAULT/gtdb_226/
# Should see: metadata/, taxonomy/, markers/ directories

# 7. Verify GTDB-Tk can see database
pixi run -e env-a gtdbtk check_install
```

### Installation Priority Matrix

| Database | Priority | Size | Time | Use tmux? | Install When |
|----------|----------|------|------|-----------|--------------|
| Plassembler | HIGH | 363 MB | 10 min | No | First (testing) |
| CheckM2 | HIGH | 3.5 GB | 1 hour | No | Early (quality) |
| Bakta | CRITICAL | 62 GB | 2-6 hrs | YES | Before annotation |
| GTDB-Tk | MEDIUM | 141 GB | 6-12 hrs | YES | For taxonomy |
| Prokka | LOW | 2 GB | 30 min | No | For pangenomics |
| BUSCO | AUTO | 0.5 GB | Auto | No | Auto-downloaded |

---

## Verification Methods

### 1. File-Based Verification

Check if key database files exist:

```bash
# Plassembler
test -f "$EXTERNAL_VAULT/plassembler/plsdb_2023_11_03_v2.msh" && \
  echo "✓ Plassembler DB found" || echo "✗ Missing"

# Bakta
test -f "$EXTERNAL_VAULT/bakta/manifest.json" && \
  echo "✓ Bakta DB found" || echo "✗ Missing"

# GTDB-Tk
test -f "$EXTERNAL_VAULT/gtdb_226/metadata/metadata.txt" && \
  echo "✓ GTDB-Tk DB found" || echo "✗ Missing"

# CheckM2
test -f "$EXTERNAL_VAULT/checkm2/uniref100.KO.1.dmnd" && \
  echo "✓ CheckM2 DB found" || echo "✗ Missing"
```

### 2. Tool-Based Verification

Let tools verify their databases:

```bash
# Bakta verification
pixi run -e env-a bakta --db $EXTERNAL_VAULT/bakta --help

# GTDB-Tk verification (thorough)
pixi run -e env-a gtdbtk check_install

# CheckM2 verification
pixi run -e env-checkm2 checkm2 database --list

# BUSCO verification
pixi run -e env-busco busco --list-datasets
```

### 3. Vault Audit

Use the built-in audit tool:

```bash
# Complete vault status
pixi run vault-audit

# Shows:
# - Total vault size
# - Individual database sizes
# - Symlink status
```

### 4. Symlink Verification

Ensure symlinks are properly created:

```bash
# Check all symlinks
for link in db_link/*; do
  if [ -L "$link" ]; then
    echo "✓ $(basename $link) -> $(readlink $link)"
  else
    echo "✗ $(basename $link) NOT A SYMLINK"
  fi
done
```

---

## Troubleshooting

### Problem 1: Download Interruptions

**Symptom**: Download stops due to network issues or system interruption

**Solution**:
```bash
# Downloads use wget -c (resumable)
# Simply re-run the command:
pixi run download-bakta

# wget will resume from where it stopped
# Look for: "Resuming download at byte X"
```

### Problem 2: Insufficient Space

**Symptom**: "No space left on device" during extraction

**Solution**:
```bash
# 1. Check space
df -h $EXTERNAL_VAULT

# 2. Free up space
cd $EXTERNAL_VAULT
rm -f *.tar.gz *.tar.xz  # Remove archives after extraction

# 3. Move vault to larger drive
mv $EXTERNAL_VAULT /new/larger/drive/taxonomy_databases
export EXTERNAL_VAULT=/new/larger/drive/taxonomy_databases
echo 'export EXTERNAL_VAULT=/new/larger/drive/taxonomy_databases' >> ~/.bashrc

# 4. Re-create symlinks
pixi run setup-vault
```

### Problem 3: Corrupted Downloads

**Symptom**: Extraction fails with "invalid archive" or similar errors

**Solution**:
```bash
# 1. Remove incomplete download
cd $EXTERNAL_VAULT/bakta
rm -f *.tar.gz *.tar.xz

# 2. Download again with checksum verification
pixi run download-bakta

# 3. Verify file integrity before extraction
# For Bakta: Check file size should be ~62 GB
ls -lh db-v6.0.tar.xz
```

### Problem 4: Symlink Errors

**Symptom**: "File not found" errors when running workflows

**Solution**:
```bash
# 1. Verify EXTERNAL_VAULT is set
echo $EXTERNAL_VAULT

# 2. Re-create all symlinks
pixi run setup-vault

# 3. Verify specific symlink
ls -la db_link/bakta
# Should point to valid directory

# 4. Manual symlink creation if needed
ln -sfn $EXTERNAL_VAULT/bakta $PWD/db_link/bakta
```

### Problem 5: Tool Can't Find Database

**Symptom**: Tools report "Database not found" even though files exist

**Solution**:
```bash
# Different tools have different environment requirements

# Bakta (needs env-a)
pixi run -e env-a bakta --db db_link/bakta --help

# GTDB-Tk (needs env-a with GTDBTK_DATA_PATH set)
# This is handled automatically by pixi activation

# CheckM2 (needs env-checkm2)
pixi run -e env-checkm2 checkm2 database --current

# If still failing, set paths explicitly in config files
```

### Problem 6: Slow Download Speeds

**Symptom**: Download taking much longer than expected

**Solution**:
```bash
# Bakta has multiple mirrors - try alternate:
cd $EXTERNAL_VAULT/bakta

# Mirror 1: Uni-Giessen (usually faster)
wget -c https://s3.computational.bio.uni-giessen.de/bakta-db/db-v6.0.tar.xz

# Mirror 2: Zenodo (if Giessen fails)
wget -c https://zenodo.org/record/14916843/files/db.tar.xz

# GTDB-Tk only has one source - consider overnight download
```

---

## Maintenance

### Regular Maintenance Tasks

#### 1. Check Vault Health

Run monthly or before major projects:

```bash
# Full audit
pixi run vault-audit

# Check for disk errors
cd $EXTERNAL_VAULT
find . -type f -name "*.dmnd" -exec ls -lh {} \; | head
```

#### 2. Update Databases

Some databases release updates periodically:

```bash
# Bakta (check for new versions periodically)
# Visit: https://github.com/oschwengers/bakta#database-download
pixi run download-bakta  # Will download new version to same location

# GTDB-Tk (major updates ~2x per year)
# Check: https://gtdb.ecogenomic.org/
# Requires manual download of new version

# CheckM2 (stable, rarely updated)
# Usually no updates needed
```

#### 3. Clean Temporary Files

```bash
# Remove downloaded archives (if extraction successful)
cd $EXTERNAL_VAULT
rm -f */*.tar.gz */*.tar.xz

# Clean tmp directory
rm -rf $EXTERNAL_VAULT/tmp/*

# Reclaim space
pixi run vault-audit
```

#### 4. Backup Critical Databases

For databases that took long to download:

```bash
# Option 1: Rsync to backup drive
rsync -avP $EXTERNAL_VAULT/gtdb_226/ /backup/drive/gtdb_226/

# Option 2: Create compressed backup
cd $EXTERNAL_VAULT
tar -czf bakta_backup_$(date +%Y%m%d).tar.gz bakta/

# Store backup archive on separate drive
```

### Database Update Schedule

| Database | Update Frequency | Check Method |
|----------|------------------|--------------|
| Bakta | Quarterly | GitHub releases page |
| GTDB-Tk | Bi-annually | GTDB website |
| CheckM2 | Rarely | Tool documentation |
| Plassembler | Annually | Zenodo repository |
| Prokka | Stable | Via `prokka --setupdb` |
| BUSCO | On-demand | Auto-updates when run |

---

## Quick Reference

### Installation Commands

```bash
# Setup vault structure
pixi run setup-vault

# Small databases (no tmux needed)
pixi run download-plassembler
pixi run -e env-checkm2 download-checkm2
pixi run setup-prokka-db

# Large databases (use tmux)
tmux new -s bakta && pixi run download-bakta
tmux new -s gtdbtk && pixi run download-gtdbtk
```

### Verification Commands

```bash
# Vault audit
pixi run vault-audit

# Individual database checks
ls -lh $EXTERNAL_VAULT/*/
pixi run -e env-a gtdbtk check_install
pixi run -e env-checkm2 checkm2 database --list
```

### Troubleshooting Commands

```bash
# Re-create symlinks
pixi run setup-vault

# Check space
df -h $EXTERNAL_VAULT

# Verify EXTERNAL_VAULT
echo $EXTERNAL_VAULT
```

---

**Last Updated**: February 2026  
**Version**: 1.0
