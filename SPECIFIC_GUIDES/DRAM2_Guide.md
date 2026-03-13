# DRAM2 Guide: Metabolic Annotation via Nextflow

## Overview

**DRAM2** (Distilled and Refined Annotation of Metabolism v2) annotates prokaryotic
genomes and MAGs against multiple functional databases to produce metabolic profiles,
pathway completeness estimates, and interactive summary visualisations.

**Environment:** `env-nf` (Nextflow + Apptainer + OpenJDK 17)  
**Pipeline:** `WrightonLabCSU/DRAM` (branch: `dev`, version: 2.0.0-beta26)  
**Database:** ~546 GB at `$EXTERNAL_VAULT/dram_db/`  
**RAM requirement:** ~64 GB (without KEGG/UniRef) | ~220 GB (with UniRef)

**Position in taxonomy_bundle workflow:**
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

## Understanding the conf/ Directory

This is the most commonly misunderstood aspect of DRAM2 for new users.

### What the conf/ files are

When you run `pixi run -e env-nf setup-dram-pipeline`, Nextflow downloads the full
DRAM2 pipeline including a `conf/` directory to:

```
~/.nextflow/assets/WrightonLabCSU/DRAM/
├── nextflow.config          ← main pipeline config
├── conf/
│   ├── base.config          ← CPU/memory resource requirements per process
│   ├── constants.config     ← pipeline-wide constants (container versions, paths)
│   ├── modules.config       ← per-module publish directory and mode settings
│   ├── slurm.config         ← HPC/SLURM cluster settings (not used on Tower 7810)
│   ├── test.config          ← minimal test run configuration
│   └── test_skips.config    ← test run with skipped steps
├── main.nf                  ← main Nextflow workflow
├── modules/                 ← individual process definitions
└── subworkflows/            ← reusable workflow components
```

### Critical point: You do NOT create or edit the pipeline conf files

The pipeline conf files are **part of the DRAM2 pipeline source code** downloaded
automatically by Nextflow. They define internal resource allocation and are maintained
by the WrightonLab team. Do not edit them.

### The custom no_kegg.config — vital for running without KEGG

KEGG is a **paid subscription database**. Without explicitly disabling it, DRAM2 will
attempt to run KEGG annotation and crash. The `no_kegg.config` is a **custom config
file you created** in `~/software/taxonomy_bundle/conf/` to suppress KEGG and UniRef:

```
~/software/taxonomy_bundle/conf/
└── no_kegg.config    ← YOUR custom file — not part of DRAM2 pipeline
```

Contents of `no_kegg.config`:

```groovy
params {
    use_kegg  = false
    kegg_db   = null
    uniref_db = null
}
```

This file is passed to Nextflow at runtime with `-c`:

```bash
pixi run -e env-nf nextflow run WrightonLabCSU/DRAM \
  -revision dev \
  -profile apptainer,full_mode \
  -c ~/software/taxonomy_bundle/conf/no_kegg.config \
  ...
```

**Do not delete this file.** Without it, DRAM2 will attempt KEGG annotation and fail.
If it is ever lost, recreate it:

```bash
mkdir -p ~/software/taxonomy_bundle/conf/
cat > ~/software/taxonomy_bundle/conf/no_kegg.config << 'EOF'
params {
    use_kegg  = false
    kegg_db   = null
    uniref_db = null
}
EOF
```

### The only file you edit: nextflow.config (in your project root)

Download the template once:

```bash
cd ~/software/taxonomy_bundle
pixi run -e env-nf dram-get-config
# Downloads to: ~/software/taxonomy_bundle/nextflow.config
```

Key settings to verify:

```groovy
params {
    max_cpus   = 32        // set to your machine's CPU count
    max_memory = '64.GB'   // 64GB sufficient for no-uniref runs
    max_time   = '240.h'
}

apptainer {
    enabled    = true
    autoMounts = true
}
```

**Location matters:** Always run DRAM2 from your project root — Nextflow reads
`nextflow.config` from the launch directory:

```bash
cd ~/software/taxonomy_bundle
pixi run -e env-nf dram-run
```

---

## Step-by-Step Setup

### When to pull pipeline updates

**Do NOT blindly pull before every run** — while the guide previously recommended this,
`v2.0.0-beta26` introduced a breaking bug in `dram-viz 0.2.5` that causes `PRODUCT_HEATMAP`
to hang indefinitely. Pulling updates will **overwrite the patch** applied in the
troubleshooting section below.

**Safe to pull when:**
- You check the changelog first: https://github.com/WrightonLabCSU/DRAM/blob/dev/CHANGELOG.md
- The `dram-viz` container hash in `product_heatmap.nf` has changed to a new fixed version
- You are prepared to re-apply the `product_heatmap.nf` patch afterwards

**Check if upstream has fixed the bug before pulling:**
```bash
curl -s https://raw.githubusercontent.com/WrightonLabCSU/DRAM/dev/modules/local/product/product_heatmap.nf | grep container
```

If the container hash is still `461ef0d1ed919a7e`, the bug is not fixed — do not pull.
If the hash has changed, check the dram-viz changelog before deciding to update.

**After any pull, always re-apply the patch:**
```bash
cat > ~/.nextflow/assets/WrightonLabCSU/DRAM/modules/local/product/product_heatmap.nf << 'EOF'
process PRODUCT_HEATMAP {
    label 'process_small'
    errorStrategy 'finish'

    conda "${moduleDir}/environment.yml"
    container "community.wave.seqera.io/library/python_dram-viz:16eae7534cb2ead2"

    input:
    path( ch_final_annots, stageAs: "raw-annotations.tsv")
    val(fasta_column)
    path(rules_tsv)
    val(rules_system)

    output:
    path( "product.html" ), emit: product_html

    script:
    """
    dram_viz --annotations ${ch_final_annots} --groupby-column ${fasta_column}
    """
}
EOF
```

---

### Step 1 — Pull/update the pipeline (with caution)

```bash
pixi run -e env-nf setup-dram-pipeline
# Runs: nextflow pull WrightonLabCSU/DRAM -r dev
# Installs/updates to: ~/.nextflow/assets/WrightonLabCSU/DRAM/
```

**⚠️ Do NOT pull blindly before every run.** See the "When to pull pipeline updates"
section above. Pulling will overwrite the `product_heatmap.nf` patch and re-introduce
the `dram-viz 0.2.5` hang bug. Always re-apply the patch after any pull.

If you see this warning during a run:
```
NOTE: Your local project version looks outdated - a different revision is available
in the remote repository [f03804bca4]
```

This is informational only — your run will proceed with the current version. Check
the changelog before deciding to pull.

### Step 2 — Download nextflow.config template

```bash
cd ~/software/taxonomy_bundle
pixi run -e env-nf dram-get-config
```

### Step 3 — Prepare input directory

DRAM2 scans a directory for genome files. **Extension must be `.fasta`.**

```bash
mkdir -p ~/software/taxonomy_bundle/input_genomes/

# Single genome — rename .fna to .fasta
cp /path/to/genome.fna \
   ~/software/taxonomy_bundle/input_genomes/genome_name.fasta

# Batch rename all MAGs from .fa to .fasta
for f in /path/to/bins/*.fa; do
    base=$(basename "$f" .fa)
    cp "$f" ~/software/taxonomy_bundle/input_genomes/"${base}.fasta"
done

# Verify
ls ~/software/taxonomy_bundle/input_genomes/
```

---

## Running DRAM2

### Pre-flight checklist (before every run)

```bash
# 1. Pull latest pipeline — takes less than 1 minute, always do this first
pixi run -e env-nf setup-dram-pipeline

# 2. Confirm input files have .fasta extension
ls ~/software/taxonomy_bundle/input_genomes/

# 3. Check disk space — need ~5 GB free per genome for outputs
df -h /media/bharat/volume1/

# 4. Start tmux session to prevent disconnection
tmux new -s dram2_run
```

### Important: Always use --anno_dbs

Without `--anno_dbs`, DRAM2 may attempt KEGG annotation (paid licence) or UniRef
(22+ hours, 477 GB). Always specify databases explicitly.

**Include:** `kofam,dbcan,camper,fegenie,methyl,cant_hyd,sulfur,merops,metals,vog,viral`  
**Exclude:** `kegg` (paid licence), `uniref` (22+ hours)

### Standard run (recommended — no KEGG/UniRef)

Always run inside tmux to prevent disconnection:

```bash
tmux new -s dram2_run

cd ~/software/taxonomy_bundle

pixi run -e env-nf nextflow run WrightonLabCSU/DRAM \
  -revision dev \
  -profile apptainer,full_mode \
  --anno_dbs "kofam,dbcan,camper,fegenie,methyl,cant_hyd,sulfur,merops,metals,vog,viral" \
  --input_fasta ~/software/taxonomy_bundle/input_genomes \
  --outdir /media/bharat/volume1/databases/dram_results_$(date +%Y%m%d) \
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

# Detach from tmux: Ctrl+B then D
# Reattach:         tmux attach -t dram2_run
```

### Resume interrupted run

```bash
cd ~/software/taxonomy_bundle
pixi run -e env-nf nextflow run WrightonLabCSU/DRAM \
  -revision dev \
  -profile apptainer,full_mode \
  -resume \
  --anno_dbs "kofam,dbcan,camper,fegenie,methyl,cant_hyd,sulfur,merops,metals,vog,viral" \
  --input_fasta ~/software/taxonomy_bundle/input_genomes \
  --outdir /media/bharat/volume1/databases/dram_results_YYYYMMDD \
  [... same --*_db flags as above ...]
```

### Key parameters explained

| Parameter | Value | Why |
|-----------|-------|-----|
| `-profile apptainer,full_mode` | both required | `apptainer` = container engine; `full_mode` = annotate+summarize+visualize |
| `--anno_dbs` | comma-separated list | explicitly sets which databases to use — always specify |
| `-revision dev` | dev branch | stable tested version |
| `--annotate` | flag | required if not using `full_mode` |

---

## Database Structure Reference

```
$EXTERNAL_VAULT/dram_db/
└── databases/                      ← actual annotation databases
    ├── uniref/        477 GB        ← EXCLUDED (22+ hours run time)
    ├── db_descriptions/ 36 GB      ← functional descriptions lookup
    ├── kofam/         14 GB         ← KEGG orthology HMMs
    ├── pfam/           8.8 GB       ← protein families
    ├── vogdb/          4.5 GB       ← viral orthologous groups
    ├── merops/         3.6 GB       ← peptidases
    ├── viral/          1.6 GB       ← RefSeq viral
    ├── camper/         864 MB       ← carbon/energy metabolism
    ├── canthyd/        877 MB       ← hydrocarbon degradation
    ├── dbcan/          202 MB       ← CAZymes
    ├── fegenie/        6.6 MB       ← iron cycling
    ├── sulfur/         1.7 MB       ← sulfur cycling
    └── metals/         58 MB        ← metal resistance
```

---

## Expected Run Times (Tower 7810)

| Input | Databases | Expected time |
|-------|-----------|---------------|
| 1 genome (~3 MB) | 11 databases (no kegg/uniref) | 25–35 min |
| 10 MAGs | 11 databases | 2–4 hours |
| 32 MAGs (all POND bins) | 11 databases | 6–12 hours |

---

## Output Structure

```
dram_results_YYYYMMDD/
├── ANNOTATE/
│   ├── PRODIGAL/               ← called genes (.faa protein files)
│   ├── MMSEQS2/                ← MMseqs2 search results
│   ├── HMM_SEARCH/             ← HMM results per database
│   ├── QUAST/                  ← assembly statistics
│   ├── RENAMED_GFFS/           ← gene annotation files
│   └── raw-annotations.tsv    ← combined raw annotations
├── SUMMARIZE/
│   ├── metabolism_summary.xlsx ← main metabolic distillation ★
│   ├── genome_stats.tsv        ← assembly stats per genome
│   ├── summarized_genomes.tsv  ← per-genome summary table
│   └── traits.xlsx             ← high-level metabolic traits ★
├── VISUALIZE/
│   ├── product.html            ← interactive metabolic heatmap ★
│   └── product.tsv             ← heatmap data as table
├── multiqc/
│   └── multiqc_report.html     ← run QC report
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
xdg-open /media/bharat/volume1/databases/dram_results_*/VISUALIZE/product.html
```

**Colour coding:** Teal/Green = pathway present | Grey = absent

| Category | What it shows |
|----------|---------------|
| Module | Core carbon metabolism (TCA, glycolysis, pentose phosphate) |
| I–V | Electron transport chains and respiratory complexes |
| Nitrogen | N-fixation, nitrate reduction, ammonia oxidation |
| Sulfur | Sulfate reduction, thiosulfate oxidation |
| C1 metabolism | Methane/methylamine cycling — key for methylotrophs |
| CAZy | Carbohydrate-active enzymes (cellulose, chitin, starch) |
| SCFA/alcohol | Short-chain fatty acid and alcohol conversions |

### metabolism_summary.xlsx

Detailed per-gene annotation. Key columns: `gene_id`, `ko_id`, `kegg_hit`,
`dbcan_hit`, `camper_hit`, `sulfur_hit`, `fegenie_hit`.

### traits.xlsx

One row per genome. Columns are high-level metabolic traits (aerobic/anaerobic,
sulfate reducer, methanogen, methylotroph etc.).

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `KEGG database file not found` | `full_mode` triggers KEGG check | Always use `--anno_dbs` to explicitly exclude kegg |
| `Argument of file() cannot be null` | Database path null but still called | Use `--anno_dbs` to exclude unwanted databases |
| Only MULTIQC runs, nothing else | Missing `--annotate` or `full_mode` | Use `-profile apptainer,full_mode` |
| UniRef runs for 20+ hours | UniRef is 477 GB | Exclude from `--anno_dbs` |
| `conf/constants.config not found` | Config files missing | Restore from `_archive/misc/conf/` |
| `nextflow: command not found` | Not in pixi env | Use `pixi run -e env-nf nextflow ...` |
| `WARN: invalid input values: --database_dir` | Warning only, not an error | Pipeline resolves paths internally — safe to ignore |
| NOTE: local project version outdated | Newer pipeline commit available | Run `setup-dram-pipeline` to update, or ignore |
| Input file extension error | `.fna` or `.fa` used | Rename all inputs to `.fasta` |
| `PRODUCT_HEATMAP` hangs indefinitely | Bug in `dram-viz 0.2.5` — see fix below | Apply `product_heatmap.nf` patch (Section below) |
| `WARN: invalid input values: --groupby_column` | Stale parameter renamed in beta26 | Remove `groupby_column` from local `nextflow.config` |
| `WARN: invalid input values: --rules_tsv` | Parameter renamed in beta26 | Rename to `trait_rules_tsv` in local `nextflow.config` |
| `PRODUCT_HEATMAP ABORTED` with exit code 130 | Run was interrupted (Ctrl+C/SIGINT) | Resume with `-resume` — annotation steps will be cached |
| No `VISUALIZE/` directory in outdir | `PRODUCT_HEATMAP` never completed | Check work dir `.command.sh` and `.exitcode`; see fix below |

---

### Known Bug Fix: PRODUCT_HEATMAP hangs indefinitely (v2.0.0-beta26)

**Affected version:** `v2.0.0-beta26` (commit `f03804bca4`) with `dram-viz 0.2.5`

**Root cause:** The `dram-viz 0.2.5` `make_product.py` script creates a `Dashboard()` object
but never calls `.save()` on it when run in non-dashboard (static HTML) mode. This causes
`dram_viz` to run indefinitely without producing any output. This is a bug in the upstream
`dram-viz` package.

**Symptoms:**
- `PRODUCT_HEATMAP` shows `[0%] 0 of 1` and never progresses
- Process runs for hours without completing
- `.command.log` and `.command.err` are empty in the work directory
- `.command.sh` shows `dram_viz` being called but no output files are produced
- `ps aux | grep dram_viz` shows the process consuming CPU but never finishing

**Fix — patch `product_heatmap.nf` to use the old working container:**

```bash
# Step 1 — restore the original file from git (in case of any prior edits)
git -C ~/.nextflow/assets/WrightonLabCSU/DRAM checkout \
  modules/local/product/product_heatmap.nf

# Step 2 — overwrite with the patched version using dram-viz 0.1.8
cat > ~/.nextflow/assets/WrightonLabCSU/DRAM/modules/local/product/product_heatmap.nf << 'EOF'
process PRODUCT_HEATMAP {
    label 'process_small'
    errorStrategy 'finish'

    conda "${moduleDir}/environment.yml"
    container "community.wave.seqera.io/library/python_dram-viz:16eae7534cb2ead2"

    input:
    path( ch_final_annots, stageAs: "raw-annotations.tsv")
    val(fasta_column)
    path(rules_tsv)
    val(rules_system)

    output:
    path( "product.html" ), emit: product_html

    script:
    """
    dram_viz --annotations ${ch_final_annots} --groupby-column ${fasta_column}
    """
}
EOF

# Step 3 — verify the patch
grep -A10 'dram_viz' ~/.nextflow/assets/WrightonLabCSU/DRAM/modules/local/product/product_heatmap.nf
```

Expected output after patch:
```
    dram_viz --annotations ${ch_final_annots} --groupby-column ${fasta_column}
```

**Step 4 — delete the stale work directory and resume:**

```bash
# Find the PRODUCT_HEATMAP work dir from your last failed run
pixi run -e env-nf nextflow log <last-run-name> -f process,workdir | grep PRODUCT

# Delete it (forces Nextflow to re-run with the patched module)
rm -rf <work_dir_path>

# Resume — all annotation steps will be cached, only PRODUCT_HEATMAP re-runs
cd ~/software/taxonomy_bundle
pixi run -e env-nf nextflow run WrightonLabCSU/DRAM \
  -revision dev -profile apptainer,full_mode -resume \
  --anno_dbs kofam,dbcan,camper,fegenie,methyl,cant_hyd,sulfur,merops,metals,vog,viral \
  --input_fasta ~/software/taxonomy_bundle/input_genomes \
  --outdir /media/bharat/volume1/databases/dram_results_YYYYMMDD \
  [... same --*_db flags ...]
```

**⚠️ Important:** This patch will be **overwritten** if you run `nextflow pull WrightonLabCSU/DRAM`
or `pixi run -e env-nf setup-dram-pipeline`. Re-apply the patch after any pipeline update until
the upstream bug is fixed in a future `dram-viz` release.

**Bug reports filed:**
- dram-viz repo: https://github.com/WrightonLabCSU/dram-viz/issues/32
- DRAM main repo: https://github.com/WrightonLabCSU/DRAM/issues/493

Monitor these issues to know when the upstream fix has been released and it is safe to update `dram-viz` without needing the patch.

---

### Known Bug Fix: Stale parameters in nextflow.config (v2.0.0-beta26)

**Affected version:** Users who ran DRAM2 before `v2.0.0-beta26` and have a local
`~/software/taxonomy_bundle/nextflow.config` that was generated from an older template.

**Root cause:** Two parameters were renamed in `v2.0.0-beta26` (commit `91edea7e`):

| Old parameter | New parameter | Notes |
|---------------|---------------|-------|
| `groupby_column` | *(removed)* | Now hardcoded internally as `params.CONSTANTS.FASTA_COLUMN` |
| `rules_tsv` | `trait_rules_tsv` | Renamed to avoid conflict with new `viz_rules_tsv` |

**Symptoms:**
```
WARN: The following invalid input values have been detected:
* --groupby_column: input_fasta
* --rules_tsv: /home/bharat/.nextflow/assets/WrightonLabCSU/DRAM/bin/assets/traits_rules.tsv
```

**Fix:**

```bash
# Check if stale parameters exist in your local config
grep -n "groupby_column\|rules_tsv\|trait_rules_tsv" ~/software/taxonomy_bundle/nextflow.config

# Remove groupby_column line
sed -i 's/groupby_column = .*/\/\/ groupby_column removed - now hardcoded in pipeline/' \
  ~/software/taxonomy_bundle/nextflow.config

# Rename rules_tsv to trait_rules_tsv (only if not already renamed)
# Check first: grep "rules_tsv" ~/software/taxonomy_bundle/nextflow.config
# If it shows plain 'rules_tsv =' (not 'trait_rules_tsv'), run:
sed -i 's/^\s*rules_tsv = /    trait_rules_tsv = /' \
  ~/software/taxonomy_bundle/nextflow.config

# Verify — should show trait_rules_tsv, not rules_tsv or groupby_column
grep -n "rules_tsv\|groupby_column" ~/software/taxonomy_bundle/nextflow.config
```

---

## Running All 32 POND MAGs

Once the single-genome test is confirmed working:

```bash
mkdir -p ~/software/taxonomy_bundle/input_genomes_pond/

for f in /path/to/metawrap_70_10_bins/*.fa; do
    base=$(basename "$f" .fa)
    cp "$f" ~/software/taxonomy_bundle/input_genomes_pond/"${base}.fasta"
done

ls ~/software/taxonomy_bundle/input_genomes_pond/ | wc -l  # should be 32
```

Then run with `--input_fasta ~/software/taxonomy_bundle/input_genomes_pond`. The
`product.html` heatmap will show all 32 MAGs as rows for direct metabolic comparison
across the POND community.

---

## Pixi Tasks Reference

```bash
# Pull/update pipeline from GitHub
pixi run -e env-nf setup-dram-pipeline

# Download nextflow.config template to project root
pixi run -e env-nf dram-get-config

# Verify pipeline + database access
pixi run -e env-nf dram-verify

# Run annotation on input_genomes/ (simple — may need explicit db flags if KEGG errors)
pixi run -e env-nf dram-run

# View all DRAM2 options
pixi run -e env-nf dram-help
```
