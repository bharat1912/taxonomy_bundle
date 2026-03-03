# How to Run: Hybrid Genome Assembly (Hybracter Pipeline)

This guide walks you through assembling a complete microbial genome using **both long reads
(PacBio or Nanopore) and short reads (Illumina)** via the `Snakefile_hybracter.smk` pipeline.

**You do not need to be a bioinformatics expert to run this pipeline.** Once configured, a
single command handles everything from downloading your reads through to an annotated,
phylogenetically placed genome.

---

## Why Hybrid Assembly?

Long reads (PacBio, Nanopore) give you the **big picture** — they span repetitive regions
and can close circular chromosomes. But they are noisy. Short reads (Illumina) are highly
accurate but too short to span repeats alone.

Hybrid assembly combines the best of both:

| Read type | Strength | Weakness |
|-----------|----------|---------|
| Long reads (PacBio/ONT) | Spans repeats, closes chromosomes | Higher error rate |
| Short reads (Illumina) | Very high accuracy | Too short for complex regions |
| **Hybrid (both)** | **Complete + accurate genome** | **Needs both datasets** |

> 💡 If you only have long reads, use the **Autocycler pipeline** instead.
> See `SPECIFIC_GUIDES/AUTOCYCLER_GUIDE.md`.

---

## Pipeline Overview

```
                    ┌──────────────────────────────────────────────┐
                    │               INPUT SOURCES                   │
                    │                                               │
                    │   Option A: SRA accessions (auto-download)   │
                    │   short: SRRxxxxx (Illumina paired reads)    │
                    │   long:  SRRyyyyy (PacBio or Nanopore reads) │
                    │                                               │
                    │   Option B: Local lab files                  │
                    │   short_r1: local_data/strain_R1.fastq.gz   │
                    │   short_r2: local_data/strain_R2.fastq.gz   │
                    │   long:     local_data/strain_long.fastq.gz │
                    └───────────────┬──────────────────────────────┘
                                    │
                    ┌───────────────┴──────────────┐
                    │                              │
                    ▼                              ▼
     ┌──────────────────────────┐   ┌──────────────────────────┐
     │  STEP 1a: Download /     │   │  STEP 1b: Download /     │
     │  Stage Long Reads        │   │  Stage Short Reads       │
     │  Tool: Kingfisher        │   │  Tool: Kingfisher        │
     │  Output: raw_data/       │   │  Output: raw_data/       │
     │  *_long.fastq.gz         │   │  *_short_R1/R2.fastq.gz  │
     └──────────────┬───────────┘   └──────────────┬───────────┘
                    │                              │
                    ▼                              ▼
     ┌──────────────────────────┐   ┌──────────────────────────┐
     │  STEP 2a: Long Read QC   │   │  STEP 2b: Short Read QC  │
     │  Tool: Filtlong          │   │  Tool: Fastp or BBDuk    │
     │  Keeps best reads up to  │   │  Trims adapters, removes │
     │  target coverage         │   │  low quality bases       │
     │  Output: filtered long   │   │  Output: trimmed R1/R2   │
     └──────────────┬───────────┘   └──────────────┬───────────┘
                    │                              │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   STEP 3: Hybrid Assembly    │
                    │   Tool: Hybracter            │
                    │   Uses long reads for        │
                    │   structure + short reads    │
                    │   for accuracy correction    │
                    │   Output: raw_data/          │
                    │   hybracter_reads/           │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   STEP 4: Contig Trimming    │
                    │   Tool: Seqkit               │
                    │   Removes short/poor contigs │
                    │   (min length: 500 bp)       │
                    │   Output: trimmed contigs    │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   STEP 5: Assembly QC        │
                    │   Tool: QUAST                │
                    │   Checks N50, contig count,  │
                    │   total genome size          │
                    │   Output: results/quast/     │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
     ┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
     │  STEP 6a:        │ │  STEP 6b:    │ │  STEP 6c:        │
     │  Taxonomy ID     │ │  Phylogenomics│ │  GTDB Accessions│
     │  Tool: DFAST-QC  │ │  Tool:       │ │  Tool: GToTree   │
     │  → Genus name    │ │  GToTree     │ │  → finds related │
     │  → GTDB lineage  │ │  → placement │ │  public genomes  │
     └───────┬──────────┘ │  in GTDB tree│ └──────┬───────────┘
             │            └──────┬───────┘        │
             └──────────────┬────┘                │
                            └──────────┬──────────┘
                                       │
                                       ▼
                    ┌──────────────────────────────┐
                    │   STEP 7: Summary &          │
                    │   Dashboard                  │
                    │   Interactive HTML report    │
                    │   combining all results      │
                    │   Output: results/dashboard/ │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────┴──────────────────────────┐
                    │           FINAL OUTPUTS                  │
                    │                                          │
                    │  results/{SAMPLE_ID}/                    │
                    │  ├── assembly.fasta     (genome)         │
                    │  ├── quast/             (QC stats)       │
                    │  ├── dfast_qc/          (taxonomy ID)    │
                    │  ├── gtotree/           (phylogenomics)  │
                    │  └── dashboard.html     (summary report) │
                    └──────────────┬──────────────────────────┘
                                   │
          ┌────────────────────────┴────────────────────────┐
          │                                                  │
          ▼                                                  ▼
┌─────────────────────────────────┐   ┌──────────────────────────────────┐
│  USE: assembly.fasta            │   │  USE: dfast_qc/ + gtotree/       │
│                                 │   │                                  │
│  • Full taxonomy pipeline       │   │  • Pangenome analysis            │
│    (GTDB-Tk, Bakta annotation)  │   │    (PIRATE, Panaroo)             │
│  → pixi run run-hybrid-taxonomy │   │  • Functional annotation         │
│                                 │   │    (eggNOG-mapper, antiSMASH)    │
│  • Comparative genomics         │   │  • Metabolic reconstruction      │
│    (CompareM2, OGRI)            │   │    (DRAM2, bacLIFE)              │
│  • Phylogenomics                │   │  → pixi run run-pirate           │
│    (GToTree, IQ-TREE)           │   │     pixi run run-panaroo         │
└─────────────────────────────────┘   └──────────────────────────────────┘
```

---

## Tools Used

| Step | Tool | Purpose |
|------|------|---------|
| Download | Kingfisher | Fast SRA download for both read types |
| Long read QC | Filtlong | Keep best long reads up to target coverage |
| Short read QC | Fastp or BBDuk | Trim adapters, remove low-quality bases |
| Assembly | Hybracter | Hybrid assembly using long + short reads |
| Contig trimming | Seqkit | Remove contigs below minimum length |
| Assembly QC | QUAST | N50, contig count, genome size statistics |
| Taxonomy ID | DFAST-QC | Rapid genus identification via GTDB |
| Phylogenomics | GToTree | Place genome in GTDB phylogenetic tree |
| Dashboard | Custom HTML | Interactive summary of all results |

---

## Directory Structure

```
taxonomy_bundle/
├── config/
│   └── config_hybracter.yaml     ← Edit this before running
├── raw_data/
│   └── hybracter_reads/          ← Downloaded/staged reads (auto-created)
│       ├── {ID}_long.fastq.gz
│       ├── {ID}_short_R1.fastq.gz
│       └── {ID}_short_R2.fastq.gz
├── local_data/                   ← Put your own lab reads here (Option B)
├── results/
│   └── {SAMPLE_ID}/
│       ├── assembly.fasta        ← Final assembled genome
│       ├── quast/                ← Assembly statistics
│       ├── dfast_qc/             ← Taxonomy identification
│       ├── gtotree/              ← Phylogenetic placement
│       └── dashboard.html        ← Interactive summary report
└── db_link/
    ├── plassembler → $EXTERNAL_VAULT/plassembler
    └── dfast_qc   → $EXTERNAL_VAULT/dfast_qc_ref
```

---

## Step-by-Step Instructions

### 1. Set up your environment

If setting up on a new machine for the first time:
```bash
git clone git@github.com:bharat1912/taxonomy_bundle.git
cd taxonomy_bundle
cp .env.template .env
nano .env                  # Set EXTERNAL_VAULT to your database drive
pixi install               # One-time install (~20-30 min)
pixi run setup-vault       # Create database symlinks
```

### 2. Configure your samples

Edit `config/config_hybracter.yaml`. You must choose **Option A or Option B** — not both.

---

#### Option A — Download hybrid reads from SRA (public data)

Use this when both your long and short reads are available on NCBI SRA.

> 💡 **Finding the right SRA accessions:** A single organism often has separate SRA entries
> for its Illumina and long-read data. Search NCBI SRA for your organism and look for two
> accessions — one with `ILLUMINA` platform (short reads) and one with `PACBIO_SMRT` or
> `OXFORD_NANOPORE` (long reads).
> You can also use `pixi run run-sra-search` to find them automatically.

```yaml
hybracter_sra_samples:
  MY_SAMPLE_HYBRID:                     # Your chosen sample name (no spaces)
    short: "SRR5413257"                 # Illumina paired-end accession
    long:  "SRR5413256"                 # PacBio or Nanopore accession
```

**Master switches for SRA mode — both must be set:**
```yaml
# Leave local samples commented out
#hybracter_local_samples:
#  ...
```

---

#### Option B — Use your own laboratory's reads

Use this when you have sequenced your own isolates and have both Illumina and long-read
data. Copy all files into the `local_data/` folder before running.

> 💡 You need **three files** per sample:
> - Illumina R1 (forward reads): `*_R1.fastq.gz`
> - Illumina R2 (reverse reads): `*_R2.fastq.gz`
> - Long reads (PacBio or Nanopore): `*_long.fastq.gz`

```yaml
hybracter_local_samples:
  MY_LAB_STRAIN:                                          # Your strain/isolate ID
    short_r1: "local_data/MY_STRAIN_R1.fastq.gz"         # Illumina forward reads
    short_r2: "local_data/MY_STRAIN_R2.fastq.gz"         # Illumina reverse reads
    long:     "local_data/MY_STRAIN_long.fastq.gz"       # Long reads

# Comment out or remove the SRA section:
#hybracter_sra_samples:
#  ...
```

---

#### Long read filtering (Filtlong)

Filtlong reduces long-read coverage to a sensible target before assembly. This prevents
excessive coverage from overwhelming the assembler and speeds up the run.

The pipeline automatically calculates how much data to keep:
```
target_bases = genome_size_mb × target_coverage × 1,000,000
```

**Example — Helicobacter pylori (1.7 Mb genome, 100x target):**
```
1.7 × 100 × 1,000,000 = 170,000,000 bases retained
```

Configure for your organism:
```yaml
genome_size_mb: 1.7       # Change to match your organism's genome size
target_coverage: 100      # 100x is recommended for most organisms

filtlong:
  enabled: true
  min_length: 1000        # Discard reads shorter than 1 kb
  target_bases: null      # null = auto-calculate from above values
  keep_percent: null      # Optional: keep best X% of reads (e.g. 90)
```

#### Short read trimming tool

Choose between two trimming tools for your Illumina reads:
```yaml
trimming_tool: "bbduk"    # Recommended — fast and accurate
# trimming_tool: "seqkit" # Alternative — uncomment to use instead
```

#### General options
```yaml
threads: 16               # CPU threads to use
min_contig_length: 500    # Discard contigs shorter than 500 bp
```

### 3. Install required databases

```bash
# DFAST-QC reference (for taxonomy identification)
pixi run download-dfast-qc

# Plassembler database (for plasmid detection)
pixi run download-plassembler
```

### 4. Test with a dry run

```bash
pixi run dry-hybracter
```

You should see a list of steps including:
```
rule download_sra_long_reads
rule download_sra_short_reads
rule filtlong_long_reads
rule fastp_trim
rule hybracter_assemble
rule quast_qc
rule run_dfast_qc
...
```

### 5. Run the pipeline

```bash
# Simple run
pixi run run-hybracter

# Or with explicit core count
pixi run -e env-a snakemake -s Snakefile_hybracter.smk \
    --configfile config/config_hybracter.yaml \
    --cores 32 --rerun-triggers mtime
```

**Always run long jobs inside tmux:**
```bash
tmux new -s hybracter
pixi run run-hybracter
# Ctrl+B then D to safely detach
# tmux attach -s hybracter to check progress
```

### 6. Check your results

```bash
# Assembly statistics
cat results/MY_SAMPLE/quast/report.txt

# Taxonomy identification
cat results/MY_SAMPLE/dfast_qc/*.json

# Open interactive dashboard
firefox results/MY_SAMPLE/dashboard.html
```

---

## Troubleshooting

| Problem | Likely cause | Solution |
|---------|-------------|----------|
| `MissingInputException` for short reads | Wrong SRA accession or file path | Verify accession has Illumina data on NCBI |
| Hybracter fails with memory error | Insufficient RAM | Reduce `threads` in config or close other applications |
| Very few contigs but low completeness | Long read coverage too low | Reduce `target_coverage` to 50 or set `keep_percent: 90` |
| DFAST-QC returns no genus | Reference database not found | Run `pixi run download-dfast-qc` |
| GToTree returns empty tree | No related GTDB genomes found | Check genus name from DFAST-QC output |
| Dashboard not rendering | Missing results from earlier step | Check `.snakemake/log/` for failed rules |

---

## Expected Run Times (Dell Precision Tower 7810, 32 cores, 62 GB RAM)

| Step | Tool | ~Time |
|------|------|-------|
| SRA download (long + short) | Kingfisher | 5–20 min |
| Filtlong + Fastp/BBDuk | QC tools | 2–5 min |
| Hybrid assembly | Hybracter | 30–90 min |
| QUAST QC | QUAST | 2–5 min |
| DFAST-QC taxonomy | DFAST-QC | 5–10 min |
| GToTree phylogenomics | GToTree | 10–30 min |
| Dashboard generation | Custom | 1–2 min |
| **Total** | | **~1–3 hours** |

---

## Glossary for Non-Bioinformaticians

| Term | What it means |
|------|--------------|
| **Hybrid assembly** | Assembly using both long and short reads together |
| **Paired-end reads** | Illumina short reads sequenced from both ends of a DNA fragment |
| **Coverage** | How many times each base in the genome is covered by reads — 100x means each position is read ~100 times |
| **Filtlong** | Tool that selects the longest, best-quality long reads up to a target amount |
| **BBDuk/Fastp** | Tools that clean up Illumina reads by removing adapters and low-quality bases |
| **Hybracter** | An automated pipeline that combines long and short reads into a polished genome |
| **DFAST-QC** | Quick taxonomy check — tells you what genus your genome belongs to |
| **GToTree** | Places your genome on a phylogenetic tree alongside related public genomes |
| **Dashboard** | An interactive HTML file summarising all results — open in any web browser |

---

*Part of the [taxonomy_bundle](https://github.com/bharat1912/taxonomy_bundle) project.*
*Please cite the original authors of each tool used in your publications.*
