# How to Run: Long-Read Genome Assembly (Autocycler Pipeline)

This guide walks you through assembling a complete microbial genome from long-read sequencing data (PacBio CLR or Oxford Nanopore) using the `Snakefile_autocycler.smk` pipeline.

**You do not need to be a bioinformatics expert to run this pipeline.** Once configured, a single command handles everything from downloading your data through to an annotated genome.

---

## Pipeline Overview

The diagram below shows the full journey from raw reads to an annotated genome. Each box is a step, and the arrows show how data flows between steps.

```
                        ┌─────────────────────────────────────┐
                        │           INPUT SOURCES              │
                        │                                      │
                        │  SRA Accession  OR  Local .fastq.gz  │
                        │  (e.g. SRR27003629)  (input_reads/) │
                        └──────────────┬──────────────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │   STEP 1: Download / Stage   │
                        │   Tool: Kingfisher / local   │
                        │   Output: input_reads/       │
                        │   {ID}_{GENUS}_{TECH}.fastq.gz│
                        └──────────────┬──────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │   STEP 2: Deduplication      │
                        │   Tool: SeqKit               │
                        │   Removes duplicate reads    │
                        │   Output: dedup_done.flag    │
                        └──────────────┬──────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │   STEP 3: Quality Filter     │
                        │   Tool: Filtlong             │
                        │   Keeps best reads by        │
                        │   length & quality           │
                        │   Output: filtered.fastq.gz  │
                        └──────────────┬──────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │   STEP 4: Subsample Reads    │
                        │   Tool: Autocycler           │
                        │   Creates N independent      │
                        │   subsets (default: 4)       │
                        │   Output: subsampled_reads/  │
                        │   sample_1.fastq ... sample_N│
                        └──────────────┬──────────────┘
                                       │
                          ┌────────────┴────────────┐
                          │                         │
                          ▼                         ▼
           ┌──────────────────────┐  ┌──────────────────────┐
           │  STEP 5a: Assemble   │  │  STEP 5b: Plasmid    │
           │  Tools (per subset): │  │  Detection           │
           │  • Flye              │  │  Tool: Plassembler   │
           │  • Canu              │  │  Output:             │
           │  • Miniasm           │  │  plasmid contigs     │
           │  • Raven             │  │                      │
           │  Output:             │  └──────────┬───────────┘
           │  assembly_input/     │             │
           └──────────┬───────────┘             │
                      │                         │
                      └────────────┬────────────┘
                                   │
                                   ▼
                        ┌─────────────────────────┐
                        │   STEP 6: Verify &       │
                        │   Weight Assemblies      │
                        │   Checks assembly sizes  │
                        │   assigns confidence     │
                        │   weights to each        │
                        │   Output: weights file   │
                        └──────────────┬───────────┘
                                       │
                                       ▼
                        ┌─────────────────────────┐
                        │   STEP 7: Cluster Graph  │
                        │   Tool: Autocycler       │
                        │   Groups similar contigs │
                        │   across all assemblies  │
                        │   Output: cluster_graph/ │
                        └──────────────┬───────────┘
                                       │
                                       ▼
                        ┌─────────────────────────┐
                        │   STEP 8: Trim & Resolve │
                        │   Tool: Autocycler       │
                        │   Finds consensus between│
                        │   assemblies, removes    │
                        │   overlapping ends       │
                        │   Output: resolved/      │
                        └──────────────┬───────────┘
                                       │
                                       ▼
                        ┌─────────────────────────┐
                        │   STEP 9: Final Assembly │
                        │   Tool: Autocycler       │
                        │   Combines all resolved  │
                        │   contigs into final     │
                        │   genome                 │
                        │   Output:                │
                        │   results/{ID}/          │
                        │   assembly.fasta         │
                        └──────────────┬───────────┘
                                       │
                          ┌────────────┼────────────┐
                          │            │            │
                          ▼            ▼            ▼
           ┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
           │  STEP 10a:       │ │  STEP 10b:   │ │  STEP 10c:       │
           │  Taxonomy ID     │ │  Assembly QC │ │  Annotation      │
           │  Tool: DFAST-QC  │ │  Tool: QUAST │ │  Tool: Bakta     │
           │  → GTDB genus    │ │  → N50, size │ │  → genes, CDS,   │
           │  detection       │ │  contiguity  │ │  rRNA, tRNA      │
           └───────┬──────────┘ └──────┬───────┘ └───────┬──────────┘
                   │                   │                  │
                   ▼                   │                  │
           ┌──────────────────┐        │                  │
           │  STEP 11:        │        │                  │
           │  BUSCO Lineage   │        │                  │
           │  Detection       │        │                  │
           │  Tool: BUSCO     │        │                  │
           │  → completeness  │        │                  │
           │  score           │        │                  │
           └───────┬──────────┘        │                  │
                   │                   │                  │
                   └───────────────────┴──────────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────────┐
                        │         FINAL OUTPUTS            │
                        │                                  │
                        │  results/{SAMPLE_ID}/            │
                        │  ├── assembly.fasta  (genome)    │
                        │  ├── bakta/          (annotation)│
                        │  ├── busco/          (quality)   │
                        │  └── quast/          (stats)     │
                        └──────────────┬──────────────────┘
                                       │
               ┌───────────────────────┴───────────────────────┐
               │                                               │
               ▼                                               ▼
┌──────────────────────────────────┐   ┌────────────────────────────────────┐
│  USE: assembly.fasta             │   │  USE: bakta/ annotation files      │
│                                  │   │                                    │
│  • GTDB-Tk taxonomy              │   │  • Pangenome analysis              │
│    (Who is this organism?)       │   │    (PIRATE, Panaroo)               │
│                                  │   │                                    │
│  • Comparative genomics          │   │  • Functional analysis             │
│    (CompareM2, OGRI)             │   │    (eggNOG-mapper, antiSMASH)      │
│                                  │   │                                    │
│  • Phylogenomics                 │   │  • Metabolic reconstruction        │
│    (GToTree, IQ-TREE)            │   │    (DRAM2, bacLIFE)                │
│                                  │   │                                    │
│  → Use: run-hybrid-taxonomy      │   │  → Use: run-pirate                 │
│         Snakefile_hybrid_        │   │         run-panaroo                │
│         taxonomy.smk             │   │         run-cm2                    │
└──────────────────────────────────┘   └────────────────────────────────────┘
```

---

## Tools Used

| Step | Tool | Purpose |
|------|------|---------|
| Download | Kingfisher | Fast SRA download |
| Deduplication | SeqKit | Remove duplicate reads |
| Quality filter | Filtlong | Keep best long reads |
| Subsampling | Autocycler | Create independent read subsets |
| Assembly | Flye, Canu, Miniasm, Raven | Assemble each subset independently |
| Plasmid detection | Plassembler | Recover plasmid sequences |
| Consensus | Autocycler | Cluster, trim and combine assemblies |
| Taxonomy ID | DFAST-QC | Quick GTDB-based genus identification |
| Completeness | BUSCO | Gene set completeness scoring |
| QC stats | QUAST | Assembly statistics (N50, contigs etc.) |
| Annotation | Bakta | Full genome annotation (genes, rRNA, tRNA) |

---

## Why Run 4 Assemblies?

Long reads (PacBio CLR and Oxford Nanopore) are powerful but noisy. Running a single assembly risks locking in errors. Autocycler solves this by:

1. **Subsampling** your reads into 4 independent random subsets
2. **Assembling** each subset separately with multiple assemblers
3. **Comparing** all assemblies and finding where they agree
4. **Building a consensus** — only keeping sequences supported by multiple independent assemblies

Think of it like asking four colleagues to independently read the same blurry document and then comparing their transcriptions. Where they all agree, you can be confident. Where they disagree, you know to look more carefully.

---

## Directory Structure

```
taxonomy_bundle/
├── input_reads/                  ← Your raw reads go here (or downloaded from SRA)
│   └── {ID}_{GENUS}_{TECH}.fastq.gz
├── config/
│   ├── config_auto.yaml          ← Main config: samples, genome size, tools
│   ├── config_busco.yaml         ← BUSCO settings
│   └── config_busco.ini          ← Advanced BUSCO overrides (optional)
├── results/
│   └── {SAMPLE_ID}/
│       ├── assembly.fasta        ← Final assembled genome
│       ├── bakta/                ← Annotation files (.gff, .gbff, .faa)
│       ├── busco/                ← BUSCO completeness report
│       └── quast/                ← Assembly statistics
├── subsampled_reads/             ← Temporary: read subsets (auto-created)
├── assembly_input/               ← Temporary: per-assembler outputs (auto-created)
└── db_link/
    ├── bakta    → $EXTERNAL_VAULT/bakta
    ├── busco    → $EXTERNAL_VAULT/busco
    └── dfast_qc → $EXTERNAL_VAULT/dfast_qc_ref
```

---

## Step-by-Step Instructions

### 1. Set up your environment

If you haven't already done so on this machine:
```bash
# Clone the repository
git clone git@github.com:bharat1912/taxonomy_bundle.git
cd taxonomy_bundle

# Configure your vault path
cp .env.template .env
nano .env   # Set EXTERNAL_VAULT to your database drive

# Install all environments (one time only, ~20-30 min)
pixi install

# Set up database symlinks
pixi run setup-vault
```

### 2. Configure your samples

Edit `config/config_auto.yaml`. There are **two master switches** you must set correctly
before running — get these wrong and the pipeline will either download when you don't want
it to, or look for local files that aren't there.

---

#### Option A — Download raw long reads from SRA (public data)

Use this when you want to assemble genomes from publicly available sequencing data on NCBI.

> 💡 **Not sure which SRA accessions to use?** Run the SRA search pipeline first:
> `pixi run run-sra-search` (configure `config/config_SRAsearch.yaml` with your organism/keyword).
> This returns a ranked list of accessions with metadata that you can paste directly below.
> See `ADDITIONAL_INFORMATION/SRASEARCH_GUIDE.md` for full details.

**Step 1 — Set your SRA accession and organism details:**
```yaml
sra:
  accession: "SRR12989396"                        # Your SRA accession number
  genus_name: "Thermaerobacillus_caldiproteolyticus"  # Genus name (used for file naming,
                                                  # use underscores not spaces)
  tech_tag: "pacbio_clr"                          # Sequencing technology — choose one:
                                                  # pacbio_clr | pacbio_hifi | ont_r9 | ont_r10
  genome_size: "3100000"                          # Approximate genome size in base pairs
                                                  # Use digits only — NOT "3.1m"
```

**Step 2 — Set the master switches for SRA mode:**
```yaml
local_reads:
  enabled: false      # ← MUST be false for SRA downloads

skip_sra_download: false   # ← MUST be false to trigger the download
read_type: "pacbio_clr"    # Must match tech_tag above
```

---

#### Option B — Use your own laboratory's long reads

Use this when you have sequenced your own isolates in the lab (PacBio CLR, PacBio HiFi,
or Oxford Nanopore) and want to assemble them locally without downloading anything.

> 💡 Copy your `.fastq.gz` read file(s) into the `input_reads/` folder before running.
> File naming convention: `{STRAIN_ID}_{GENUS}_{TECH_TAG}.fastq.gz`
> Example: `LAB001_Anoxybacillus_pacbio_clr.fastq.gz`

**Step 1 — Define your local sample:**
```yaml
local_reads:
  enabled: true       # ← MUST be true for local reads
  samples:
    LAB001:                                               # Your strain/isolate ID
      reads: ["input_reads/LAB001_Anoxybacillus_PacBio.fastq.gz"]  # Path to your reads
      genus_name: "Anoxybacillus"                        # Expected genus name
      tech_tag: "pacbio_clr"                             # Your sequencing platform
      genome_size: "2900000"                             # Approximate genome size in bp
```

**Step 2 — Set the master switches for local mode:**
```yaml
local_reads:
  enabled: true       # ← MUST be true

skip_sra_download: true    # ← MUST be true (no download needed)
read_type: "pacbio_clr"    # Must match your tech_tag above
```

---

#### Selecting assemblers — toggle on/off by commenting/uncommenting

The pipeline supports **12 assemblers**. You do not need to run all of them — **3–4 is
recommended** for a good consensus. Comment out (`#`) any assembler you want to skip.

Two assembler selection modes are available:
- `permissive` — runs all listed assemblers regardless of read type (default)
- `semi-permissive` — only runs assemblers compatible with your detected read type

```yaml
mode:
  assembler_selection: "permissive"   # options: permissive | semi-permissive

assemblers:
  - flye          # PacBio CLR, ONT — fast, reliable, recommended always
  - canu          # PacBio CLR/HiFi, ONT — slower but very accurate
  - raven         # PacBio CLR, ONT — fast alternative to Flye
  - miniasm       # PacBio CLR, ONT — very fast, lower accuracy
  - plassembler   # All types — plasmid recovery (recommend keeping on)
  - metamdbg      # PacBio CLR/HiFi, ONT
  - necat         # PacBio CLR only
  - nextdenovo    # PacBio CLR/HiFi
  - redbean       # PacBio CLR, ONT (wtdbg2)
  - myloasm       # ONT only (experimental)
  - hifiasm       # PacBio HiFi only
  - lja           # PacBio HiFi only — run via: pixi run -e env-lja
# - shasta        # ONT only — not part of autocycler helper, manual use only
```

**Assembler compatibility by read type:**

| Assembler | PacBio CLR | PacBio HiFi | ONT r9 | ONT r10 |
|-----------|:----------:|:-----------:|:------:|:-------:|
| Flye | ✓ | — | ✓ | ✓ |
| Canu | ✓ | ✓ | ✓ | ✓ |
| Raven | ✓ | — | ✓ | ✓ |
| Miniasm | ✓ | — | ✓ | ✓ |
| Plassembler | ✓ | ✓ | ✓ | ✓ |
| MetaMDBG | ✓ | ✓ | ✓ | ✓ |
| NECAT | ✓ | — | — | — |
| NextDenovo | ✓ | ✓ | — | — |
| Redbean (wtdbg2) | ✓ | — | ✓ | ✓ |
| Myloasm | — | — | ✓ | ✓ |
| Hifiasm | — | ✓ | — | — |
| LJA | — | ✓ | — | — |

---

#### Processing parameters

```yaml
parameters:
  subsample_count: 4    # Independent read subsets (4 recommended, minimum 3)
  threads: 8            # Threads per assembler job
                        # Total cores = threads × subsample_count
                        # e.g. 8 × 4 = 32 cores on Tower 7810

# Clustering quality thresholds
# Lower values = more permissive (use for difficult/noisy data)
# Higher values = more stringent (use for Gold Standard lab samples)
clustering:
  min_assembly_count: 3   # Times a contig must be independently assembled to pass
  min_cluster_size: 2     # Minimum assemblies required to form a cluster
  max_error_rate: 0.05    # Maximum allowed divergence during clustering

# Assembler weights (influence final consensus)
weights:
  plassembler_cluster_weight: 3   # Extra weight for circular plasmid contigs
  canu_consensus_weight: 2        # Extra weight for Canu contigs
  flye_consensus_weight: 2        # Extra weight for Flye contigs
```

### 3. Install required databases

The pipeline needs Bakta and BUSCO databases. If not already installed:

```bash
# Bakta annotation database (~62 GB) — run in tmux
tmux new -s bakta
pixi run download-bakta
# Ctrl+B then D to detach safely

# BUSCO lineages (auto-selected, ~0.5 GB per lineage)
pixi run download-busco-prok

# DFAST-QC reference (for genus detection)
pixi run download-dfast-qc
```

### 4. Test with a dry run

Always do a dry run first — it checks your config is valid and shows you what will run, without actually running anything:

```bash
pixi run dry-autocycler
```

You should see a list of steps like:
```
rule download_sra_or_local
rule dedup_reads
rule filtlong_filter
rule subsample_reads
rule run_assemblers
...
```

If you see errors here, check your `config_auto.yaml` for typos in sample names or paths.

### 5. Run the pipeline

```bash
# Simple run (recommended for first time)
pixi run run-autocycler

# Or with more control over cores
pixi run -e env-a snakemake -s Snakefile_autocycler.smk \
    --configfile config/config_auto.yaml \
    --cores 32 --rerun-triggers mtime
```

**For long jobs, always run inside tmux** so it keeps running if your terminal closes:
```bash
tmux new -s assembly
pixi run run-autocycler
# Ctrl+B then D to safely detach
# tmux attach -s assembly to check progress later
```

### 6. Check your results

When complete, your results will be in `results/{SAMPLE_ID}/`:

```bash
# Check assembly statistics
cat results/MY_ISOLATE/quast/report.txt

# Check BUSCO completeness
cat results/MY_ISOLATE/busco/short_summary*.txt

# View annotation summary
cat results/MY_ISOLATE/bakta/*.txt
```

A good result typically shows:
- BUSCO completeness: **>95%**
- Number of contigs: **1–5** (ideally 1 closed chromosome)
- N50: **close to or equal to genome size**

---

## Troubleshooting

| Problem | Likely cause | Solution |
|---------|-------------|----------|
| `MissingInputException` | Read file not found | Check path and filename in config_auto.yaml |
| BUSCO completeness <80% | Poor assembly or wrong lineage | Check DFAST-QC genus output, re-run with correct lineage |
| Pipeline stops at Canu | Insufficient memory | Reduce `threads_per_task` or set `mem: 60` in config |
| `KeyError: 'busco'` | Config missing busco section | Ensure config_busco.yaml is present and correct |
| Bakta fails | Database not found | Run `pixi run download-bakta` first |
| Only 1 assembler succeeded | Assembler crashed | Check logs in `.snakemake/log/` — pipeline continues with available assemblies |

---

## Expected Run Times (Dell Precision Tower 7810, 32 cores, 62 GB RAM)

| Step | Tool | ~Time |
|------|------|-------|
| SRA download | Kingfisher | 2–10 min |
| Filtlong + subsample | Filtlong | 2–5 min |
| Assembly × 4 subsets | Flye | ~20 min total |
| Assembly × 4 subsets | Canu | ~2 hours total |
| Autocycler consensus | Autocycler | 10–20 min |
| DFAST-QC | DFAST-QC | 5–10 min |
| BUSCO | BUSCO | 10–30 min |
| Bakta annotation | Bakta | 10–20 min |
| **Total** | | **~3–5 hours** |

---

## Glossary for Non-Bioinformaticians

| Term | What it means |
|------|--------------|
| **Contig** | A continuous stretch of assembled DNA sequence |
| **N50** | Half your genome is in contigs this size or larger — bigger is better |
| **BUSCO** | Checks how complete your genome is by looking for expected genes |
| **Subsampling** | Taking a random portion of your reads to create independent datasets |
| **Consensus** | The sequence agreed upon by multiple independent assemblies |
| **Annotation** | Identifying and labelling genes, rRNA, tRNA in your assembly |
| **SRA** | NCBI Sequence Read Archive — public database of raw sequencing data |
| **GTDB** | Genome Taxonomy Database — a modern standardised bacterial taxonomy |

---

*Part of the [taxonomy_bundle](https://github.com/bharat1912/taxonomy_bundle) project.*
*Please cite the original authors of each tool used in your publications.*
