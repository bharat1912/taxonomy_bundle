# DRAM2 Metabolic Annotation Guide

## Overview

DRAM2 (Distilled and Refined Annotation of Metabolism 2) is a Nextflow-based pipeline for metabolic annotation of metagenome-assembled genomes (MAGs) and isolate genomes. It searches multiple metabolic databases and produces a distilled summary of metabolic capabilities including carbon cycling, nitrogen cycling, sulfur cycling, CAZymes, and energy metabolism.

**In the taxonomy_bundle workflow:**
```
MetaWRAP (bin refinement)
    ↓
Refined MAGs (metawrap_70_10_bins/)
    ↓
DRAM2 ← metabolic annotation (this guide)
    ↓
metabolism_summary.xlsx + product.html
```

---

## Workflow Diagram

```
Input FASTA (MAG or isolate genome)
    ↓
CALL_GENES (Prodigal)       QUAST (assembly stats)
    ↓
MMSEQS_INDEX (protein index)
    ↓
┌─────────────────────────────────────────────────────────┐
│ DATABASE SEARCHES (parallel)                            │
│  HMM searches:   kofam, dbcan, camper, canthyd,        │
│                  sulfur, fegenie, metals, vog           │
│  MMseqs2:        merops, pfam, viral, camper, canthyd   │
│  tRNA/rRNA:      tRNA_SCAN, rRNA_SCAN                   │
└─────────────────────────────────────────────────────────┘
    ↓
COMBINE_ANNOTATIONS (raw-annotations.tsv)
    ↓
SUMMARIZE (metabolism_summary.xlsx, traits.xlsx)
    ↓
VISUALIZE (product.html — interactive heatmap)
```

---

## Prerequisites

- taxonomy_bundle pixi environment (`env-nf`)
- Apptainer installed
- DRAM2 databases downloaded to vault

### Required Databases

| Database | Path | Size | Purpose |
|----------|------|------|---------|
| kofam | `$DRAM_DB/kofam/` | ~5GB | KEGG pathway annotation |
| dbcan | `$DRAM_DB/dbcan/` | ~1GB | CAZymes (carbohydrate enzymes) |
| camper | `$DRAM_DB/camper/` | ~500MB | Carbon metabolism |
| canthyd | `$DRAM_DB/canthyd/` | ~200MB | Hydrocarbon degradation |
| sulfur | `$DRAM_DB/sulfur/` | ~100MB | Sulfur cycling |
| fegenie | `$DRAM_DB/fegenie/` | ~100MB | Iron cycling |
| metals | `$DRAM_DB/metals/` | ~200MB | Metal resistance/cycling |
| methyl | `$DRAM_DB/methyl/` | ~300MB | Methylotrophy |
| merops | `$DRAM_DB/merops/` | ~2GB | Peptidases/proteases |
| pfam | `$DRAM_DB/pfam/` | ~3GB | Protein families |
| viral | `$DRAM_DB/viral/` | ~2GB | Viral proteins |
| vogdb | `$DRAM_DB/vogdb/` | ~5GB | Virus orthologous groups |
| db_descriptions | `$DRAM_DB/db_descriptions/` | ~1GB | Annotation descriptions |

> **Note:** KEGG (`kegg_db`) and UniRef (`uniref_db`) are NOT included — KEGG requires a paid licence, UniRef causes excessively long run times (22+ hours). All biologically meaningful metabolic functions are covered by the databases above.

---

## Configuration

### Step 1 — Prepare input directory

DRAM2 requires a directory containing genome FASTA files. Supported extensions: `.fa`, `.fasta`, `.fna`

```bash
# Create input directory
mkdir -p ~/software/taxonomy_bundle/dram2_input/

# Copy a single MAG for testing
cp /media/bharat/volume1/metawrap_results/refined_bins/metawrap_70_10_bins/bin.21.fa \
   ~/software/taxonomy_bundle/dram2_input/bin21.fasta

# Or copy all refined bins
for f in /media/bharat/volume1/metawrap_results/refined_bins/metawrap_70_10_bins/*.fa; do
    base=$(basename $f .fa)
    cp $f ~/software/taxonomy_bundle/dram2_input/${base}.fasta
done
```

> **Important:** Rename `.fa` files to `.fasta` — DRAM2 directory scanning works most reliably with `.fasta` extension.

### Step 2 — Restore pipeline configs

DRAM2 Nextflow requires config files in `conf/`:

```bash
mkdir -p ~/software/taxonomy_bundle/conf/
cp ~/software/taxonomy_bundle/_archive/misc/conf/constants.config ~/software/taxonomy_bundle/conf/
cp ~/software/taxonomy_bundle/_archive/misc/conf/modules.config ~/software/taxonomy_bundle/conf/
cp ~/software/taxonomy_bundle/_archive/misc/conf/base.config ~/software/taxonomy_bundle/conf/
```

---

## Running DRAM2

### Standard Run (all available databases, no KEGG/UniRef)

Always run inside tmux to prevent disconnection:

```bash
tmux new -s dram2_run

cd ~/software/taxonomy_bundle

pixi run -e env-nf nextflow run WrightonLabCSU/DRAM \
  -revision dev \
  -profile apptainer,full_mode \
  --anno_dbs "kofam,dbcan,camper,fegenie,methyl,cant_hyd,sulfur,merops,metals,vog,viral" \
  --input_fasta ~/software/taxonomy_bundle/dram2_input \
  --outdir /media/bharat/volume1/databases/dram2_results \
  --kofam_db /media/bharat/volume1/databases/dram_db/databases/kofam/ \
  --kofam_list /media/bharat/volume1/databases/dram_db/databases/kofam/kofam_ko_list.tsv \
  --dbcan_db /media/bharat/volume1/databases/dram_db/databases/dbcan/ \
  --dbcan_fam_activities /media/bharat/volume1/databases/dram_db/databases/dbcan/dbcan.fam-activities.tsv \
  --pfam_mmseq_db /media/bharat/volume1/databases/dram_db/databases/pfam/mmseqs/ \
  --merops_db /media/bharat/volume1/databases/dram_db/databases/merops/ \
  --viral_db /media/bharat/volume1/databases/dram_db/databases/viral/ \
  --vog_db /media/bharat/volume1/databases/dram_db/databases/vogdb/ \
  --vog_list /media/bharat/volume1/databases/dram_db/databases/vogdb/vog_annotations_latest.tsv.gz \
  --camper_hmm_db /media/bharat/volume1/databases/dram_db/databases/camper/hmm/ \
  --camper_hmm_list /media/bharat/volume1/databases/dram_db/databases/camper/hmm/camper_hmm_scores.tsv \
  --camper_mmseqs_db /media/bharat/volume1/databases/dram_db/databases/camper/mmseqs/ \
  --camper_mmseqs_list /media/bharat/volume1/databases/dram_db/databases/camper/mmseqs/camper_scores.tsv \
  --canthyd_hmm_db /media/bharat/volume1/databases/dram_db/databases/canthyd/hmm/ \
  --cant_hyd_hmm_list /media/bharat/volume1/databases/dram_db/databases/canthyd/hmm/cant_hyd_HMM_scores.tsv \
  --canthyd_mmseqs_db /media/bharat/volume1/databases/dram_db/databases/canthyd/mmseqs/ \
  --canthyd_mmseqs_list /media/bharat/volume1/databases/dram_db/databases/canthyd/mmseqs/cant_hyd_BLAST_scores.tsv \
  --fegenie_db /media/bharat/volume1/databases/dram_db/databases/fegenie/ \
  --fegenie_list /media/bharat/volume1/databases/dram_db/databases/fegenie/fegenie_iron_cut_offs.txt \
  --sulfur_db /media/bharat/volume1/databases/dram_db/databases/sulfur/ \
  --methyl_db /media/bharat/volume1/databases/dram_db/databases/methyl/ \
  --metals_db /media/bharat/volume1/databases/dram_db/databases/metals/ \
  --sql_descriptions_db /media/bharat/volume1/databases/dram_db/databases/db_descriptions/description_db.sqlite \
  2>&1 | tee ~/software/taxonomy_bundle/dram2_run.log

# Detach: Ctrl+B then D
# Reattach: tmux attach -t dram2_run
```

### Key Parameters Explained

| Parameter | Value | Why |
|-----------|-------|-----|
| `-profile apptainer,full_mode` | both required | `apptainer` = container engine; `full_mode` = sets `annotate=true` + `summarize=true` |
| `--anno_dbs` | comma list | explicitly sets which databases to use — overrides all `use_*` flags; excludes kegg and uniref |
| `-revision dev` | dev branch | most stable tested version |

> **Critical:** Without `--anno_dbs`, DRAM2 defaults `use_kegg=false` but `full_mode` combined with database paths can trigger KEGG validation errors. Always specify `--anno_dbs` explicitly.

---

## Expected Run Times

| Input | Databases | Expected Time |
|-------|-----------|---------------|
| 1 bin (~3Mb) | 11 databases (no kegg/uniref) | 25–35 minutes |
| 10 bins | 11 databases | 2–4 hours |
| 32 bins (all POND MAGs) | 11 databases | 6–12 hours |

Run times on Tower 7810 (64GB RAM, multi-core).

---

## Output Files

```
dram2_results/
├── ANNOTATE/
│   ├── PRODIGAL/          ← called genes (.faa protein files)
│   ├── MMSEQS2/           ← MMseqs2 search results
│   ├── HMM_SEARCH/        ← HMM search results per database
│   ├── QUAST/             ← assembly statistics
│   ├── RENAMED_GFFS/      ← gene annotation files
│   └── raw-annotations.tsv ← combined raw annotations
├── SUMMARIZE/
│   ├── metabolism_summary.xlsx  ← main metabolic distillation ★
│   ├── genome_stats.tsv         ← assembly stats per genome
│   ├── summarized_genomes.tsv   ← per-genome summary table
│   └── traits.xlsx              ← high-level metabolic traits ★
├── VISUALIZE/
│   ├── product.html             ← interactive metabolic heatmap ★
│   └── product.tsv              ← heatmap data as table
├── multiqc/
│   └── multiqc_report.html      ← run QC report
└── pipeline_info/
    ├── execution_report.html
    ├── execution_trace.txt
    └── execution_timeline.html
```

★ = primary outputs for biological interpretation

---

## Interpreting Results

### product.html (Interactive Heatmap)

Open in any web browser:
```bash
xdg-open /media/bharat/volume1/databases/dram2_results/VISUALIZE/product.html
```

**Colour coding:**
- **Teal/Green** = pathway/function IS present in the genome
- **Grey** = pathway/function is absent

**Column categories (left to right):**
- **Module** — core carbon metabolism (TCA, glycolysis, pentose phosphate)
- **I–V** — electron transport chains and respiratory complexes
- **Photo** — photosynthesis (expect absent in most heterotrophs)
- **Nitrogen** — nitrogen cycling (ammonia oxidation, nitrate reduction, N-fixation)
- **Sulfur** — sulfur cycling (sulfate reduction, thiosulfate oxidation)
- **Other** — TMAO reductase, arsenate reduction, mercury reduction
- **C1 metabolism** — methane/methylamine cycling
- **CAZy** — carbohydrate-active enzymes (cellulose, chitin, starch etc.)
- **SCFA/alcohol** — short-chain fatty acid and alcohol conversions

### metabolism_summary.xlsx

Detailed spreadsheet with one row per gene/annotation. Key columns:
- `gene_id` — gene identifier
- `ko_id` — KEGG Orthology number (from kofam)
- `kegg_hit` — KEGG pathway annotation
- `dbcan_hit` — CAZyme family
- `camper_hit` — carbon metabolism annotation
- `sulfur_hit` — sulfur cycling annotation
- `fegenie_hit` — iron cycling annotation

### traits.xlsx

High-level summary table — one row per genome, columns are metabolic traits (aerobic/anaerobic, sulfate reducer, methanogen etc.)

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `KEGG database file not found` | `full_mode` triggers kegg check | Always use `--anno_dbs` to explicitly exclude kegg |
| `Argument of file() cannot be null` | database path set to null but still called | Use `--anno_dbs` to exclude unwanted databases instead of setting paths to null |
| Only MULTIQC runs, nothing else | Missing `--annotate` flag or `full_mode` not set | Use `-profile apptainer,full_mode` |
| UNIREF runs for 20+ hours | UniRef is 100GB+ | Exclude with `--anno_dbs` (do not include `uniref`) |
| `conf/constants.config not found` | Config files removed during git cleanup | Restore from `_archive/misc/conf/` |
| `nextflow: command not found` | Not in pixi env | Use `pixi run -e env-nf nextflow ...` |

---

## Running All 32 POND MAGs

Once the single-bin test is confirmed working, run all refined bins together:

```bash
# Stage all bins
mkdir -p ~/software/taxonomy_bundle/dram2_input_all/
for f in /media/bharat/volume1/metawrap_results/refined_bins/metawrap_70_10_bins/*.fa; do
    base=$(basename $f .fa)
    cp $f ~/software/taxonomy_bundle/dram2_input_all/${base}.fasta
done

# Verify
ls ~/software/taxonomy_bundle/dram2_input_all/ | wc -l  # should be 32
```

Then run with `--input_fasta ~/software/taxonomy_bundle/dram2_input_all` — the `product.html` heatmap will show all 32 bins as rows, enabling direct metabolic comparison across the POND community.

---

## Integration with CompareM2

DRAM2 and CompareM2 are complementary — use both and cross-reference by bin name:

```
CompareM2 report.html          DRAM2 product.html
──────────────────────         ──────────────────
bin.21 = Gammaproteobacteria   bin.21 = aerobic heterotroph
bin.21 = 80% complete          bin.21 = TCA + sulfur metabolism
bin.21 = low contamination     bin.21 = 14 CAZyme families
```

The bin name is the common key linking taxonomy (CompareM2) to function (DRAM2).
