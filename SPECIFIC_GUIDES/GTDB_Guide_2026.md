# GTDB-Tk Guide 2026
## Genome Taxonomy Database Toolkit — Installation, Database Setup, Classification & Tree Visualisation

**taxonomy_bundle — GTDB-Tk v2.6.1 via Pixi**
**Bharat Patel — March 2026**

---

## 0. How GTDB-Tk Works — Overview

GTDB-Tk (Genome Taxonomy Database Toolkit) classifies prokaryotic genomes using the **Genome Taxonomy Database (GTDB)**, a phylogenomics-based taxonomy that is independent of the NCBI taxonomy system.

### Classification approach

GTDB-Tk identifies **120 conserved bacterial marker genes** (bac120) or **53 archaeal marker genes** (ar53) in your input genomes, aligns them to a reference multiple sequence alignment, and places your genomes into the GTDB reference tree using **pplacer**. Taxonomy is then assigned using **Relative Evolutionary Divergence (RED)** values and **Average Nucleotide Identity (ANI)** comparisons.

### Key concepts

| Concept | Description |
|---------|-------------|
| **RED value** | Relative Evolutionary Divergence — measures how far a genome sits from reference nodes. Determines rank assignment (phylum → species) |
| **ANI** | Average Nucleotide Identity — ≥95% ANI to a reference = same species |
| **Marker genes** | bac120 (bacteria) or ar53 (archaea) — conserved single-copy genes used for placement |
| **Backbone tree** | Compressed reference tree used for pplacer placement; smaller than full tree |
| **Classify mode** | Uses pplacer placement + RED + ANI — recommended for routine use |
| **De novo mode** | Builds a new tree from scratch using IQ-TREE or FastTree — needed for novel lineages |

### Important: GTDB vs NCBI taxonomy

GTDB uses genome-based phylogeny and renames many phyla. **Names differ from NCBI/Kraken2** — this is by design, not an error. See Section 6 for a conversion table.

| NCBI (Kraken2) | GTDB r226 |
|----------------|-----------|
| Proteobacteria | Pseudomonadota |
| Actinobacteria | Actinomycetota |
| Firmicutes | Bacillota |
| Euryarchaeota | Halobacteriota / Methanobacteriota (split) |
| Crenarchaeota | Thermoproteota |
| Ignavibacteriae | Bacteroidota_A |

---

## 1. Installation in Pixi

GTDB-Tk is installed in the `env-a` environment in taxonomy_bundle. It is also available in the `default` environment used by CompareM2.

### pixi.toml entries

```toml
[feature.env-a.dependencies]
gtdbtk = ">=2.6.1,<3"
hmmer = ">=3.4,<4"
prodigal = "*"
mash = "*"
fasttree = "*"
iqtree = "*"

[feature.env-a.activation.env]
GTDBTK_DATA_PATH = "$PIXI_PROJECT_ROOT/db_link/gtdbtk"
```

### Verify installation

```bash
cd ~/software/taxonomy_bundle

# Check GTDB-Tk version
pixi run -e env-a gtdbtk --version

# Check database is linked
ls -la db_link/gtdbtk

# Full installation check (requires database)
pixi run -e env-a gtdbtk check_install
```

### Check all pixi environments

```bash
# List all environments
pixi info

# Check env-a specifically
pixi run -e env-a python3 --version
pixi run -e env-a gtdbtk --version

# Check database symlink
ls -la ~/software/taxonomy_bundle/db_link/gtdbtk
# Should point to: /media/bharat/volume1/databases/gtdb_226
```

---

## 2. Installing the Database

> ⚠️ **Warning: 141GB download, ~250GB extracted. Always run in tmux.**

```bash
tmux new-session -s gtdb_download

# Download and install GTDB r226 database
pixi run download-gtdbtk
```

This task:
1. Creates `$EXTERNAL_VAULT/gtdb_226/` directory
2. Downloads `gtdbtk_r226_data.tar.gz` (141GB, resumable with `-c`)
3. Extracts to vault directory
4. Removes the tar.gz to reclaim 141GB
5. Runs `gtdbtk check_install` to verify

Monitor download progress:
```bash
# In another terminal
watch -n 60 'du -sh $EXTERNAL_VAULT/gtdb_226/'
```

Detach tmux: `Ctrl+B` then `D`

---

## 3. Checking the Database

```bash
# Verify installation
pixi run -e env-a gtdbtk check_install

# List database contents
ls /media/bharat/volume1/databases/gtdb_226/

# Check taxonomy files
ls /media/bharat/volume1/databases/gtdb_226/taxonomy/
# Should contain:
#   ar53_taxonomy_r226_reps.tsv
#   bac120_taxonomy_r226_reps.tsv
#   gtdb_taxonomy.tsv

# Check database version
cat /media/bharat/volume1/databases/gtdb_226/metadata/genome_paths.tsv | head -2
```

---

## 4. Running GTDB-Tk Classification

### 4.1 classify_wf — Standard classification (recommended)

The `classify_wf` workflow is the standard approach for classifying genomes or MAGs. It runs marker gene identification, alignment, pplacer placement, RED assignment, and ANI comparison in one command.

```bash
# Basic usage
pixi run -e env-a gtdbtk classify_wf \
    --genome_dir /path/to/genomes/ \
    --out_dir /path/to/output/ \
    --extension fa \
    --cpus 24

# For large datasets (>50 genomes) — use scratch_dir to manage RAM
# pplacer requires ~86GB RAM for the full reference tree
# --scratch_dir writes pplacer allocations to disk, reducing RAM to ~32GB
pixi run -e env-a gtdbtk classify_wf \
    --genome_dir /path/to/genomes/ \
    --out_dir /path/to/output/ \
    --extension fa \
    --cpus 24 \
    --scratch_dir /path/to/scratch/ \
    --skip_ani_screen
```

> ⚠️ **Memory warning:** pplacer placement requires ~86GB RAM for the bacterial reference tree. Use `--scratch_dir` on systems with <128GB RAM to avoid crashes.

### 4.2 De novo mode — novel lineages

Use de novo mode when you have genomes from lineages not represented in GTDB, or when you need a publication-quality phylogenetic tree with bootstrap support.

```bash
# De novo workflow — builds tree from scratch
pixi run -e env-a gtdbtk de_novo_wf \
    --genome_dir /path/to/genomes/ \
    --out_dir /path/to/output/ \
    --extension fa \
    --cpus 24 \
    --bacteria \
    --outgroup_taxon p__Chloroflexota
```

> ⚠️ **Note:** De novo mode is computationally intensive (IQ-TREE or FastTree) and may take many hours for large datasets. Not recommended for routine classification.

---

## 5. GAB Run Example

This section documents the complete GTDB-Tk r226 run performed on 106 GAB MAGs.

### Input

| Parameter | Value |
|-----------|-------|
| Genomes | 106 MAGs from 4 GAB samples (CS1BS, CS1GB, POND, SRR) |
| File extension | `.fa` |
| Format | MetaWRAP-refined bins, renamed by sample |
| Location | `/media/bharat/volume2/MAGS_2023_Metawrap_final/MAGS_2023/5_BIN_REFINEMENT/metawrap_70_10_bins/` |
| Database | GTDB r226 |

### Command

```bash
tmux new-session -s gtdbtk_gab

cd ~/software/taxonomy_bundle

pixi run -e env-a gtdbtk classify_wf \
    --genome_dir /media/bharat/volume2/MAGS_2023_Metawrap_final/MAGS_2023/5_BIN_REFINEMENT/metawrap_70_10_bins/ \
    --out_dir /media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/ \
    --extension fa \
    --cpus 24 \
    --scratch_dir /media/bharat/volume1/gtdbtk_scratch \
    --skip_ani_screen \
    2>&1 | tee ~/software/taxonomy_bundle/gtdbtk_GAB_run.log
```

### Key output files

| File | Location | Description |
|------|----------|-------------|
| `gtdbtk.bac120.summary.tsv` | `out_dir/` | Bacterial classification (main results) |
| `gtdbtk.ar53.summary.tsv` | `out_dir/` | Archaeal classification |
| `gtdbtk.bac120.classify.tree.*.tree` | `out_dir/classify/` | Bacterial subtrees (1-8) with MAGs placed |
| `gtdbtk.ar53.classify.tree` | `out_dir/classify/` | Archaeal tree with MAGs placed |
| `gtdbtk.backbone.bac120.classify.tree` | `out_dir/classify/` | Backbone tree (all bacterial MAGs) |
| `gtdbtk.bac120.tree.mapping.tsv` | `out_dir/classify/` | Which subtree each MAG is in |
| `gtdbtk.log` | `out_dir/` | Full run log |

### Results summary

| Metric | Value |
|--------|-------|
| Total MAGs | 106 |
| Bacteria | 98 |
| Archaea | 8 |
| Total phyla | 29 (25 bacterial, 4 archaeal) |
| MAGs without species assignment | 91 / 106 (85.8%) |

---

## 5a. Post-run: Extracting Two-Column Classification Table

Extract a two-column table (genome → phylum) from the GTDB-Tk summary TSV files. This is the foundation for tree annotation.

```bash
# Quick phylum summary — bacteria
cut -f1,2 /media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/gtdbtk.bac120.summary.tsv | \
    awk -F'\t' 'NR>1 {
        split($2, a, ";");
        for(i in a) {
            if(a[i] ~ /^p__/) { print $1"\t"substr(a[i],4); break }
        }
    }' > phylum_table_bac.tsv

# Quick genus summary — bacteria  
cut -f1,2 /media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/gtdbtk.bac120.summary.tsv | \
    awk -F'\t' 'NR>1 {
        split($2, a, ";");
        for(i in a) {
            if(a[i] ~ /^g__/) { print $1"\t"substr(a[i],4); break }
        }
    }' > genus_table_bac.tsv

# Python approach — full metadata table
python3 << 'PYEOF'
import pandas as pd

for domain, f in [('bac', 'gtdbtk.bac120.summary.tsv'),
                  ('arc', 'gtdbtk.ar53.summary.tsv')]:
    df = pd.read_csv(f'/media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/{f}', sep='\t')
    df['phylum'] = df['classification'].str.extract(r'p__([^;]+)')
    df['class']  = df['classification'].str.extract(r'c__([^;]+)')
    df['order']  = df['classification'].str.extract(r'o__([^;]+)')
    df['family'] = df['classification'].str.extract(r'f__([^;]+)')
    df['genus']  = df['classification'].str.extract(r'g__([^;]+)')
    df['species'] = df['classification'].str.extract(r's__([^;]+)')
    df[['user_genome','phylum','class','order','family','genus','species']].to_csv(
        f'gtdbtk_{domain}_parsed.tsv', sep='\t', index=False)
    print(f'{domain}: {len(df)} genomes, {df["phylum"].nunique()} phyla')
PYEOF
```

---

## 5b. Post-run: Selecting Reference Genomes for Tree Visualisation

> **Note:** GTDB-Tk classifies your genomes but does NOT produce a clean, annotated tree figure. This section provides a standardised pipeline to generate publication-quality phylogenetic trees.

### Overview

The GTDB-Tk backbone tree contains ~5,400 reference genomes. To create a readable tree showing your genomes in phylogenetic context, you need to:

1. Select one representative genome per phylum from the backbone tree
2. Prune the backbone tree to keep your genomes + selected references
3. Plot using ggtree in R

### Script 1: Select reference genomes per phylum

```bash
# ~/Desktop/MAG_paper_2026/scripts/01_create_phylum_map.py
```

This script reads:
- `gtdbtk.bac120.summary.tsv` — your genome classifications
- `bac120_taxonomy_r226_reps.tsv` — GTDB reference taxonomy

And writes:
- `selected_refs.tsv` — one reference accession per phylum (**editable**)
- `phylum_map.tsv` — combined metadata for all genomes + refs

> ✅ **Key feature:** `selected_refs.tsv` can be manually edited to replace auto-selected references with more appropriate ones before running Script 2.

**Selecting better references manually:**

Open `selected_refs.tsv` and replace any accession with a more appropriate one from GTDB. For example, to replace the Pseudomonadota reference with a closer relative:

```bash
# Find well-known Pseudomonadota genomes in the backbone tree
grep "Pseudomonadota" /media/bharat/volume1/databases/gtdb_226/taxonomy/bac120_taxonomy_r226_reps.tsv | \
    grep "Pseudomonas\|Burkholderia\|Aeromonas" | head -5
```

### Script 2: Prune backbone tree

```bash
# ~/Desktop/MAG_paper_2026/scripts/02_prune_tree.py
```

Reads `selected_refs.tsv` and prunes the GTDB backbone tree using ete3.

> ⚠️ **Important:** Reference accessions must include the `RS_` or `GB_` prefix (e.g. `RS_GCF_000014805.1`) to match the backbone tree tip labels. Do NOT strip these prefixes.

### Script 3: Plot tree in R with ggtree

```bash
# ~/Desktop/MAG_paper_2026/scripts/03_plot_tree.R
```

Reads the pruned newick tree + metadata and generates:
- Tip labels coloured by sample origin
- Tip symbols coloured by phylum
- Phylum clade bars with labels
- Reference genomes shown as diamonds

```bash
cd ~/software/taxonomy_bundle && pixi run Rscript ~/Desktop/MAG_paper_2026/scripts/03_plot_tree.R
```

Output:
- `gtdbtk_GAB_ggtree_final.png` — high-resolution PNG (300 DPI)
- `gtdbtk_GAB_ggtree_final.pdf` — vector PDF for publication

### YAML configuration for flexible pipelines

For reuse across different projects, a YAML config file provides flexibility:

```yaml
# gtdbtk_tree_config.yaml
project: GAB_metagenomics

input:
  summary_bac: /media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/gtdbtk.bac120.summary.tsv
  summary_arc: /media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/gtdbtk.ar53.summary.tsv
  backbone_tree: /media/bharat/volume1/databases/gtdbtk_r226_GAB_106bins_v3/classify/gtdbtk.backbone.bac120.classify.tree
  gtdb_taxonomy: /media/bharat/volume1/databases/gtdb_226/taxonomy/bac120_taxonomy_r226_reps.tsv

output:
  selected_refs: selected_refs.tsv       # Edit this file to change references
  phylum_map: phylum_map.tsv
  pruned_tree: gtdbtk_final.nwk
  metadata: gtdbtk_final_meta.tsv
  tree_png: gtdbtk_tree.png
  tree_pdf: gtdbtk_tree.pdf

tree_settings:
  refs_per_phylum: 1          # 1 = broad overview (MAGs); 2-3 = isolate genomes
  tree_width: 22
  tree_height: 24
  dpi: 300

# Sample colours (hex)
sample_colors:
  CS1BS: "#2196F3"
  CS1GB: "#4CAF50"
  POND:  "#FF9800"
  SRR:   "#9C27B0"
  Reference: "black"
```

### Genome vs MAG trees

| Setting | MAGs | Isolate genomes |
|---------|------|-----------------|
| `refs_per_phylum` | 1 | 2-3 (or more for focal genus) |
| Reference strategy | One rep per phylum | Genus-level neighbours + outgroup |
| Tree density | Sparse — broad overview | Dense — taxonomic placement |
| Typical tips | 50-200 | 20-100 |
| Key question | What phyla are present? | Where does this genome sit in the genus? |

For isolate genome trees, add multiple references from the target genus:

```python
# In selected_refs.tsv — add multiple rows for the same phylum
# e.g. for a Pseudomonas isolate, add 3-5 Pseudomonas references:
# RS_GCF_000006765.1   Pseudomonas_aeruginosa_ref   Pseudomonadota   Pseudomonas   Reference   Reference
# RS_GCF_000014805.1   Aeromonas_ref                Pseudomonadota   Aeromonas     Reference   Reference
```

---

## 6. NCBI → GTDB Taxonomy Conversion

GTDB-Tk output uses GTDB taxonomy. Kraken2 and most public databases use NCBI taxonomy. The table below maps phyla detected in the GAB analysis.

| NCBI (Kraken2) | GTDB r226 | Notes |
|----------------|-----------|-------|
| Proteobacteria | Pseudomonadota | Renamed |
| Actinobacteria | Actinomycetota | Renamed |
| Firmicutes | Bacillota | Renamed |
| Bacteroidetes | Bacteroidota | Name retained |
| Chloroflexi | Chloroflexota | Renamed |
| Planctomycetes | Planctomycetota | Name retained |
| Verrucomicrobia | Verrucomicrobiota | Renamed |
| Acidobacteria | Acidobacteriota | Renamed |
| Gemmatimonadetes | Gemmatimonadota | Renamed |
| Euryarchaeota | Halobacteriota / Methanobacteriota / Thermoplasmatota | Split into multiple phyla |
| Crenarchaeota | Thermoproteota | Renamed |
| Ignavibacteriae | Bacteroidota_A | Reclassified |
| Deinococcus-Thermus | Deinococcota | Renamed |
| Cyanobacteria | Cyanobacteriota | Renamed |
| — | Electryoneota | GTDB-only novel phylum |
| — | Sumerlaeota | GTDB-only novel phylum |
| — | Krumholzibacteriota | GTDB-only novel phylum |
| — | Bipolaricaulota | GTDB-only novel phylum |
| — | UBP18 | GTDB-only novel phylum |

---

## 7. Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `pplacer: out of memory` | Insufficient RAM for reference tree | Add `--scratch_dir /path/to/scratch` |
| `GTDBTK_DATA_PATH not set` | Environment variable not loaded | Run from `~/software/taxonomy_bundle/` with `pixi run -e env-a` |
| `No genomes found` | Wrong extension | Check `--extension` matches your files (`.fa`, `.fasta`, `.fna`) |
| `check_install fails` | Database not fully extracted | Re-run `pixi run download-gtdbtk` |
| `Unexpected newick format` | Internal node labels in tree | Use `quoted_node_names=True` in ete3 |
| `Refs not in backbone tree` | Using bare GCF accession | Keep `RS_`/`GB_` prefix in accessions |
| `geom_cladelab` fails | ggtree version mismatch | Use `geom_cladelab` not `geom_cladelabel` (deprecated) |
| Blank ggtree output | NA in aesthetic columns | Add `na.value=` to all `scale_*` calls |

---

## 8. Quick Reference

| Task | Command |
|------|---------|
| Check GTDB-Tk version | `pixi run -e env-a gtdbtk --version` |
| Download database | `pixi run download-gtdbtk` (in tmux) |
| Check database | `pixi run -e env-a gtdbtk check_install` |
| Classify genomes | `pixi run -e env-a gtdbtk classify_wf --genome_dir ... --out_dir ... --extension fa --cpus 24` |
| Large dataset (low RAM) | Add `--scratch_dir /tmp/gtdbtk_scratch --skip_ani_screen` |
| Extract phylum table | `python3 01_create_phylum_map.py` |
| Prune backbone tree | `python3 02_prune_tree.py` |
| Plot tree | `pixi run Rscript 03_plot_tree.R` |

---

*taxonomy_bundle — GTDB-Tk v2.6.1 — https://github.com/bharat1912/taxonomy_bundle*
