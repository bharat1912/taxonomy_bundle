# How to Run: Hybrid Taxonomy & Annotation Pipeline

This guide walks you through the `Snakefile_hybrid_taxonomy.smk` pipeline — the most
comprehensive workflow in the taxonomy bundle. It takes raw sequencing reads (short,
long, or both) and produces a fully assembled, taxonomically classified, phylogenetically
placed, and annotated genome, all in a single automated run.

> 📖 **A note on this pipeline's history:** This was the first Snakefile developed in
> this bundle, initially attempted with ChatGPT and Gemini, before being rebuilt and
> completed with Claude. It reflects the iterative, real-world nature of bioinformatics
> pipeline development — and the value of persistence.

**You do not need to be a bioinformatics expert to run this pipeline.** Configure your
samples, run one command, and come back to a complete result.

---

## What Makes This Pipeline Different?

Unlike the Autocycler and Hybracter pipelines which focus purely on assembly, this
pipeline is an **end-to-end taxonomy and annotation workflow**. It goes all the way from
raw reads to a phylogenetic tree and interactive dashboard in a single run.

| Pipeline | Assembly | QC | Taxonomy | Phylogenomics | Annotation | Dashboard |
|----------|:--------:|:--:|:--------:|:-------------:|:----------:|:---------:|
| Autocycler | ✓ | ✓ | ✓ | — | ✓ | — |
| Hybracter | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| **Hybrid Taxonomy** | **✓** | **✓** | **✓** | **✓** | **—** | **✓** |

> 💡 The output `assembly.fasta` from this pipeline feeds directly into the
> Autocycler or annotation workflows for Bakta/DRAM2 annotation.

---

## Pipeline Overview

```
              ┌──────────────────────────────────────────────────────┐
              │                  THREE INPUT OPTIONS                  │
              │                                                       │
              │  Option 1: SRA short reads only (Illumina)           │
              │  sra_accessions: ["SRR8113456"]                      │
              │                                                       │
              │  Option 2: SRA hybrid (Illumina + PacBio/ONT)        │
              │  sra_hybrid_samples:                                  │
              │    short: "SRRxxxxx" + long: "SRRyyyyy"              │
              │                                                       │
              │  Option 3: Local lab reads (short only OR hybrid)    │
              │  local_long_reads_paths:                              │
              │    short_r1/r2 + long (or long: "" for short only)   │
              └──────────────────────┬───────────────────────────────┘
                                     │
                   ┌─────────────────┴─────────────────┐
                   │                                   │
                   ▼                                   ▼
    ┌──────────────────────────┐       ┌──────────────────────────┐
    │  STEP 1a: Download /     │       │  STEP 1b: Download /     │
    │  Stage Short Reads       │       │  Stage Long Reads        │
    │  Tool: Kingfisher        │       │  Tool: Kingfisher        │
    │  OR symlink local files  │       │  OR symlink local files  │
    │  Output: raw_reads/      │       │  (dummy file if          │
    │  {acc}_1.fastq.gz        │       │  short-read only)        │
    │  {acc}_2.fastq.gz        │       │  Output: raw_reads/      │
    └──────────────┬───────────┘       │  {acc}_long.fastq.gz     │
                   │                   └──────────────┬────────────┘
                   │                                  │
                   ▼                                  ▼
    ┌──────────────────────────┐       ┌──────────────────────────┐
    │  STEP 2a: Short Read QC  │       │  STEP 2b: Long Read QC   │
    │  Tool: Fastp or BBDuk    │       │  Tool: Filtlong          │
    │  Trim adapters, remove   │       │  Filter to target        │
    │  low quality bases       │       │  coverage                │
    │  Output: trimmed_reads/  │       │  Output: filtered_long_  │
    │  {acc}_1.trim.fastq.gz   │       │  reads/{acc}_long_       │
    │  {acc}_2.trim.fastq.gz   │       │  filtered.fastq.gz       │
    └──────────────┬───────────┘       └──────────────┬────────────┘
                   │                                  │
                   └─────────────────┬────────────────┘
                                     │
                                     ▼
                    ┌────────────────────────────────┐
                    │  STEP 3: Genome Assembly        │
                    │  Tool: Unicycler               │
                    │  Modes (auto-detected):        │
                    │  • Short reads only (PE or SE) │
                    │  • Hybrid (PE + long reads)    │
                    │  Output: {acc}/assembly/        │
                    │  assembly.fasta                │
                    └────────────────┬───────────────┘
                                     │
                                     ▼
                    ┌────────────────────────────────┐
                    │  STEP 4: Contig Trimming        │
                    │  Tool: Seqkit or BBDuk         │
                    │  Remove contigs < 500 bp       │
                    │  Output: contig_qc/            │
                    │  contigs_trimmed.fasta         │
                    └────────────────┬───────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
     ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐
     │  STEP 5a:        │  │  STEP 5b:    │  │  STEP 5c:        │
     │  Assembly QC     │  │  Taxonomy ID │  │  GTDB Accessions │
     │  Tool: QUAST     │  │  Tool:       │  │  Tool: GToTree   │
     │  N50, contigs,   │  │  DFAST-QC   │  │  Finds related   │
     │  genome size     │  │  → genus.txt │  │  public genomes  │
     │  Output: qc/     │  │  Output:     │  │  from GTDB       │
     │  quast/          │  │  taxonomy/   │  │  Output:         │
     │  report.html     │  │  dfast_qc/   │  │  gtotree/        │
     └──────────┬───────┘  └──────┬───────┘  └────────┬─────────┘
                │                 │                   │
                │                 ▼                   │
                │  ┌──────────────────────────┐       │
                │  │  STEP 6: Phylogenomics   │       │
                │  │  Tool: GToTree           │◄──────┘
                │  │  Places genome in GTDB   │
                │  │  phylogenetic tree using │
                │  │  genus from DFAST-QC     │
                │  │  + related accessions    │
                │  │  Output: gtotree/        │
                │  │  gtotree_output/         │
                │  └──────────────┬───────────┘
                │                 │
                └────────┬────────┘
                         │
                         ▼
          ┌──────────────────────────────────┐
          │  STEP 7: Summary & Dashboard     │
          │  Collects: genus, N50, accession │
          │  Builds interactive HTML report  │
          │  Output:                         │
          │  {acc}_summary.tsv               │
          │  reports/dashboard/dashboard.html│
          └──────────────┬───────────────────┘
                         │
          ┌──────────────┴──────────────────────────────┐
          │              FINAL OUTPUTS                   │
          │                                              │
          │  results/{ACCESSION}/                        │
          │  ├── assembly/assembly.fasta   (genome)      │
          │  ├── qc/quast/report.html      (QC stats)    │
          │  ├── taxonomy/dfast_qc/genus.txt (taxonomy)  │
          │  ├── taxonomy/gtotree/         (phylogeny)   │
          │  ├── {acc}_summary.tsv         (summary)     │
          │  └── reports/dashboard/        (HTML report) │
          └──────────────┬──────────────────────────────┘
                         │
       ┌─────────────────┴──────────────────────────┐
       │                                            │
       ▼                                            ▼
┌──────────────────────────────┐  ┌────────────────────────────────┐
│  USE: assembly.fasta         │  │  USE: taxonomy/ + gtotree/     │
│                              │  │                                │
│  • Full annotation           │  │  • Pangenome analysis          │
│    → pixi run run-autocycler │  │    (PIRATE, Panaroo)           │
│    (Bakta, BUSCO, DFAST-QC)  │  │  • Comparative genomics        │
│                              │  │    (CompareM2, OGRI)           │
│  • MAG bundle (coming soon)  │  │  • Metabolic reconstruction    │
│    MetaWRAP, nf-core/MAG     │  │    (DRAM2, bacLIFE)            │
│                              │  │  → pixi run run-pirate         │
│                              │  │     pixi run run-panaroo       │
└──────────────────────────────┘  └────────────────────────────────┘
```

---

## Tools Used

| Step | Tool | Purpose |
|------|------|---------|
| Download | Kingfisher | Fast SRA download (short + long reads) |
| Short read QC | Fastp or BBDuk | Adapter trimming, quality filtering |
| Long read QC | Filtlong | Downsample to target coverage |
| Assembly | Unicycler | Short-read or hybrid genome assembly |
| Contig trimming | Seqkit / BBDuk | Remove contigs below minimum length |
| Assembly QC | QUAST | N50, contig count, genome size statistics |
| Taxonomy ID | DFAST-QC | Rapid GTDB-based genus identification |
| Phylogenomics | GToTree | Phylogenetic placement using GTDB HMMs |
| Dashboard | Custom HTML | Interactive summary of all results |

---

## Directory Structure

```
taxonomy_bundle/
├── config/
│   └── config_taxonomy_merged.yaml    ← Edit this before running
├── local_data/                        ← Your lab reads go here (Option 3)
├── raw_data/
│   ├── raw_reads/{acc}/               ← Downloaded or staged reads
│   ├── trimmed_reads/{acc}/           ← QC-processed reads
│   └── filtered_long_reads/{acc}/     ← Filtlong-processed long reads
├── results/
│   └── {ACCESSION}/
│       ├── assembly/assembly.fasta    ← Final assembled genome
│       ├── qc/quast/                  ← Assembly statistics
│       ├── taxonomy/dfast_qc/         ← Taxonomy identification
│       ├── taxonomy/gtotree/          ← Phylogenetic placement
│       ├── contig_qc/                 ← Filtered contigs
│       ├── {acc}_summary.tsv          ← Per-sample summary
│       └── reports/dashboard/         ← Interactive HTML report
└── db_link/
    └── dfast_qc_ref → $EXTERNAL_VAULT/dfast_qc_ref
```

---

## Step-by-Step Instructions

### 1. Set up your environment

```bash
git clone git@github.com:bharat1912/taxonomy_bundle.git
cd taxonomy_bundle
cp .env.template .env
nano .env                  # Set EXTERNAL_VAULT to your database drive
pixi install               # One-time install (~20-30 min)
pixi run setup-vault       # Create database symlinks
```

### 2. Configure your samples

Edit `config/config_taxonomy_merged.yaml`. **Only one option should be active at a time** —
comment out the others with `#`.

---

#### Option 1 — Download short reads only from SRA (Illumina)

Use this for Illumina-only datasets. Unicycler will run in short-read mode.
Good for quick assemblies or when no long reads are available.

```yaml
sra_accessions: ["SRR8113456"]

# Multiple samples run one after another:
sra_accessions: ["SRR25073979", "SRR25073980"]

# Comment out other options:
#sra_hybrid_samples:
#local_long_reads_paths:
```

---

#### Option 2 — Download hybrid reads from SRA (Illumina + PacBio/ONT)

Use this when both Illumina and long-read data are available on SRA for your organism.
Unicycler will run in hybrid mode for the most complete, accurate assembly.

```yaml
sra_hybrid_samples:
  SRR5413257_HYBRID:                  # Sample name — must end in _HYBRID
    short: "SRR5413257"               # Illumina paired-end accession
    long:  "SRR5413256"               # PacBio or Nanopore accession

# Comment out other options:
#sra_accessions:
#local_long_reads_paths:
```

> 💡 Use `pixi run run-sra-search` to find matching short + long read accessions
> for your organism. Look for two entries with the same BioSample but different
> platforms (ILLUMINA and PACBIO_SMRT or OXFORD_NANOPORE).

---

#### Option 3 — Use your own laboratory reads (bypasses download)

Use this for reads generated in your own lab. Supports two sub-options:

**Sample A — Short reads only (no long reads):**
```yaml
local_long_reads_paths:
  my_raw_reads_name:                                          # Your strain ID
    short_r1: "local_data/MY_STRAIN_R1.fastq.gz"            # Illumina R1
    short_r2: "local_data/MY_STRAIN_R2.fastq.gz"            # Illumina R2
    long: ""   # Leave empty — pipeline creates a dummy file automatically

# Comment out other options:
#sra_accessions:
#sra_hybrid_samples:
```

**Sample B — Short + long reads (true hybrid):**
```yaml
local_long_reads_paths:
  my_hybrid_sample:
    short_r1: "local_data/MY_STRAIN_R1.fastq.gz"
    short_r2: "local_data/MY_STRAIN_R2.fastq.gz"
    long:     "local_data/MY_STRAIN_long.fastq.gz"   # Real long reads
```

> 💡 Copy your read files into `local_data/` before running.

---

#### Long read filtering (Filtlong)

Same calculation as the Hybracter pipeline:
```
target_bases = genome_size_mb × target_coverage × 1,000,000
```

```yaml
genome_size_mb: 1.7       # Adjust to your organism (e.g. 3.0 for most bacteria)
target_coverage: 100      # 100x recommended

filtlong:
  enabled: true
  min_length: 1000        # Discard reads shorter than 1 kb
  target_bases: null      # null = auto-calculate
  keep_percent: null      # Optional: keep best X% of reads
```

#### Trimming tool
```yaml
trimming_tool: "bbduk"    # Recommended
# trimming_tool: "seqkit" # Alternative
```

#### Unicycler assembly options

Unicycler has several tunable parameters. The defaults work well for most cases:

```yaml
unicycler_options:
  mode: "normal"          # conservative | normal | bold
                          # conservative = safer, more fragmented
                          # normal = balanced (recommended)
                          # bold = more complete but riskier
  keep_level: 3           # 0=minimal files, 3=keep everything (useful for debugging)
  skip_pilon: false       # false = run Pilon polishing (recommended)
  no_rotate: false        # false = allow chromosome rotation (recommended)
  min_contig_size: 1000   # Ignore contigs smaller than 1 kb
  depth_filter: 0.25      # Remove contigs with < 25% of median depth
```

#### GToTree phylogenomics
```yaml
gtotree:
  hmm_name: "Bacteria"    # HMM set for phylogenetic placement
                          # Options: Bacteria, Archaea, Universal_Hug_et_al
                          # Download HMMs: pixi run -e env-b gtt-hmms --get-hmms Bacteria
```

#### Resources
```yaml
threads: 16
min_contig_length: 500    # Contigs shorter than this are discarded

rule_resources:
  assemble_genome_unicycler:
    mem_mb: 60000         # RAM for Unicycler in MB (set to your available RAM)
```

---

### 3. Install required databases

```bash
# DFAST-QC reference (for taxonomy identification)
pixi run download-dfast-qc

# GToTree HMMs (for phylogenomics) — choose your domain
pixi run -e env-b gtt-hmms --get-hmms Bacteria
```

### 4. Test with a dry run

```bash
pixi run dry-hybrid-taxonomy
```

You should see all rules listed including:
```
rule download_sra_short_reads  (or provide_local_hybrid_short_reads)
rule download_sra_long_reads   (or provide_dummy_long_reads)
rule fastp_trim / bbduk_trim
rule filtlong_downsample
rule assemble_genome_unicycler
rule trim_contigs
rule quast_report
rule run_dfast_qc
rule gtotree_get_gtdb_accessions
rule run_gtotree
rule summarize_single_accession
rule build_html_dashboard
```

### 5. Run the pipeline

```bash
# Simple run
pixi run run-hybrid-taxonomy

# With explicit core count
pixi run -e env-a snakemake -s Snakefile_hybrid_taxonomy.smk \
    --configfile config/config_taxonomy_merged.yaml \
    --cores 32 --rerun-triggers mtime
```

**Always run in tmux for long jobs:**
```bash
tmux new -s taxonomy
pixi run run-hybrid-taxonomy
# Ctrl+B then D to detach safely
# tmux attach -s taxonomy to check progress
```

### 6. Check your results

```bash
# Assembly statistics
cat results/MY_ACCESSION/qc/quast/report.tsv

# Taxonomy result
cat results/MY_ACCESSION/taxonomy/dfast_qc/genus.txt

# Sample summary
cat results/MY_ACCESSION/MY_ACCESSION_summary.tsv

# Open interactive dashboard
firefox results/MY_ACCESSION/reports/dashboard/dashboard.html
```

---

## Troubleshooting

| Problem | Likely cause | Solution |
|---------|-------------|----------|
| `MissingInputException` for long reads | `long: ""` not handled | Pipeline auto-creates dummy — check `provide_dummy_long_reads` ran |
| Unicycler memory error | Insufficient RAM | Increase `mem_mb` in `rule_resources` or reduce `threads` |
| Assembly has many small contigs | Short reads only, complex genome | Consider adding long reads (Option 2 or 3B) |
| DFAST-QC returns no genus | Reference not found | Run `pixi run download-dfast-qc` |
| GToTree returns empty tree | Genus not in GTDB | Check `genus.txt` output — may need broader HMM set |
| Dashboard missing sections | Earlier rule failed | Check `.snakemake/log/` for the failed rule |
| `KeyError: accession` | Sample name format wrong | Option 2 sample names must end in `_HYBRID` |

---

## Expected Run Times (Dell Precision Tower 7810, 32 cores, 62 GB RAM)

| Step | Tool | Short only | Hybrid |
|------|------|-----------|--------|
| SRA download | Kingfisher | 5–15 min | 10–30 min |
| QC (Fastp + Filtlong) | QC tools | 2–5 min | 3–8 min |
| Assembly | Unicycler | 30–60 min | 60–120 min |
| QUAST QC | QUAST | 1–2 min | 1–2 min |
| DFAST-QC | DFAST-QC | 5–10 min | 5–10 min |
| GToTree | GToTree | 10–30 min | 10–30 min |
| Dashboard | Custom | 1–2 min | 1–2 min |
| **Total** | | **~1–2 hours** | **~2–4 hours** |

---

## Glossary for Non-Bioinformaticians

| Term | What it means |
|------|--------------|
| **Unicycler** | A genome assembler that works with short reads alone or combined with long reads |
| **Hybrid assembly** | Assembly using both long and short reads for maximum accuracy and completeness |
| **Dummy long reads** | An empty placeholder file created automatically when only short reads are provided — allows the pipeline to run without modification |
| **DFAST-QC** | Quick taxonomy identification tool — tells you what genus your assembled genome belongs to based on GTDB |
| **GToTree** | Phylogenomics tool that places your genome on a tree alongside related public genomes |
| **GTDB** | Genome Taxonomy Database — a modern standardised bacterial/archaeal taxonomy |
| **HMM set** | A collection of Hidden Markov Models representing conserved genes — used by GToTree to build phylogenetic trees |
| **Dashboard** | An interactive HTML file summarising all results — open in any web browser |
| **Filtlong** | Selects the best long reads up to a target coverage to prevent the assembler being overwhelmed |

---

*Part of the [taxonomy_bundle](https://github.com/bharat1912/taxonomy_bundle) project.*
*Please cite the original authors of each tool used in your publications.*
