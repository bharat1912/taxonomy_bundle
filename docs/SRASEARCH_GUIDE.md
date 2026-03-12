# How to Run: SRA Search & Metadata Discovery (SRAsearch Pipeline)

This guide explains how to search the NCBI Sequence Read Archive (SRA) for publicly
available sequencing data using the `Snakefile_SRAsearch.smk` pipeline.

**You do not need to be a bioinformatics expert to use this pipeline.** It automates
what would otherwise require manual searching across multiple NCBI web pages.

---

## Background: What is the SRA?

The **Sequence Read Archive (SRA)** is the world's largest publicly accessible repository
of raw sequencing data, maintained by the National Center for Biotechnology Information
(NCBI). It contains millions of sequencing datasets from researchers around the world,
covering:

- Bacterial and archaeal isolate genomes (WGS)
- Metagenome-assembled genomes (MAGs)
- Environmental samples (soil, hot springs, ocean, gut microbiome)
- Clinical samples
- RNA-seq, amplicon (16S), and many other data types

Every dataset in the SRA has a unique accession number:
- **SRR** — a single sequencing run (e.g. `SRR27003629`)
- **SRP** — a sequencing project containing multiple runs (e.g. `SRP166933`)
- **PRJNA** — a BioProject (e.g. `PRJNA525015`)

---

## Why Use This Pipeline Instead of Searching Manually?

You can search the SRA manually at https://www.ncbi.nlm.nih.gov/sra — but this has
limitations:

| Manual SRA search | This pipeline |
|------------------|--------------|
| Web interface only | Command-line, repeatable, scriptable |
| Limited metadata columns visible | Full metadata including instrument, coverage, dates |
| No bulk export of results | Saves results as `.tsv` file for sorting/filtering |
| Cannot filter by file size | Can filter by `mbases` (data size) |
| Cannot combine multiple filters | Boolean queries with AND/OR/NOT |
| Cannot resolve DOI to accessions | DOI → SRA accession conversion built in |

**The key advantage** is that results are saved as a `.tsv` file that you can open in
LibreOffice Calc or Microsoft Excel, sort by coverage, date, platform, or organism, and
select your best candidates before downloading anything.

> 💡 **Broad searches are often better than narrow ones.** Cast a wide net first
> (e.g. search for a whole family rather than a single species), then sort and filter
> the metadata spreadsheet to find the best datasets. This avoids missing good data
> due to inconsistent naming in the SRA.

---

## Three Search Modes

The pipeline supports three distinct modes — choose the one that fits your situation:

| Mode | Use when | Config key |
|------|----------|-----------|
| **MODE 1: Discovery Search** | Hunting for unknown/new genomes by keyword or organism | `search_filters:` |
| **MODE 2: Project Fetch** | You have a known project ID from a paper or colleague | `sra_project:` |
| **MODE 3: DOI Conversion** | You found a paper and want its raw data | `doi_conversion:` |

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    THREE ENTRY POINTS                            │
│                                                                  │
│  MODE 1: Discovery      MODE 2: Project       MODE 3: DOI       │
│  search_filters:        sra_project:          doi_conversion:   │
│  keyword/organism       "PRJNA525015"         "10.1038/..."     │
│  search                 known project ID      paper → data      │
└──────────────┬──────────────────┬──────────────────┬────────────┘
               │                  │                  │
               ▼                  ▼                  ▼
┌──────────────────┐  ┌───────────────────┐  ┌──────────────────┐
│  RULE:           │  │  RULE:            │  │  RULE:           │
│  sra_search      │  │  fetch_project_   │  │  doi_to_         │
│  Tool: pysradb   │  │  metadata         │  │  identifiers     │
│  search          │  │  Tool: pysradb    │  │  Tool: pysradb   │
│                  │  │  metadata         │  │  doi-to-         │
│                  │  │                   │  │  identifiers     │
└──────────┬───────┘  └─────────┬─────────┘  └────────┬─────────┘
           │                    │                      │
           └────────────────────┴──────────────────────┘
                                │
                                ▼
               ┌────────────────────────────────┐
               │  RULE: summarize_random_        │
               │  selection                      │
               │  Generates summary table of     │
               │  library selection methods      │
               │  (RANDOM vs PCR vs other)       │
               └────────────────┬───────────────┘
                                │
                                ▼
        ┌───────────────────────────────────────────┐
        │              FINAL OUTPUTS                 │
        │                                            │
        │  sra_search_output/                        │
        │  ├── search_data/                          │
        │  │   └── {query_name}.tsv    ← MODE 1 & 3 │
        │  ├── project_data/                         │
        │  │   └── {project_id}.tsv   ← MODE 2      │
        │  ├── summary_RANDOM_vs_PCR.tsv             │
        │  └── logs/                                 │
        │      └── sra_search.log                    │
        └───────────────────────┬───────────────────┘
                                │
          ┌─────────────────────┴─────────────────────┐
          │                                           │
          ▼                                           ▼
┌──────────────────────────────┐   ┌──────────────────────────────┐
│  NEXT STEP: Open in          │   │  NEXT STEP: Use accessions   │
│  LibreOffice / Excel         │   │  in other pipelines          │
│                              │   │                              │
│  Sort by: coverage, date,    │   │  • Long-read genomes →       │
│  platform, organism          │   │    Autocycler pipeline       │
│  Filter: keep WGS, remove    │   │    (Snakefile_autocycler.smk)│
│  amplicon, select best       │   │  • Hybrid genomes →          │
│  candidates                  │   │    Hybracter pipeline        │
│                              │   │  • MAGs →                    │
│  Copy SRR accessions of      │   │    MAG bundle (coming soon)  │
│  selected datasets into      │   │                              │
│  config_auto.yaml or         │   │  Paste accessions into:      │
│  config_hybracter.yaml       │   │  config_auto.yaml (sra:)     │
│                              │   │  config_hybracter.yaml       │
└──────────────────────────────┘   └──────────────────────────────┘
```

---

## Tools Used

| Tool | Purpose |
|------|---------|
| pysradb | Python library for programmatic SRA/ENA database queries |
| pandas | Data processing for summary table generation |

---

## Directory Structure

```
taxonomy_bundle/
├── config/
│   └── config_SRAsearch.yaml     ← Edit this to set your search
├── sra_search_output/            ← All results go here (auto-created)
│   ├── search_data/              ← MODE 1 and MODE 3 results
│   │   └── {query}.tsv
│   ├── project_data/             ← MODE 2 results
│   │   └── {project_id}.tsv
│   ├── summary_RANDOM_vs_PCR.tsv ← Library selection summary
│   └── logs/
│       └── sra_search.log
```

---

## Step-by-Step Instructions

### 1. Open the config file

```bash
nano ~/software/taxonomy_bundle/config/config_SRAsearch.yaml
```

Only **one mode** should be active at a time. Comment out the other two modes with `#`.

---

### 2. Choose your mode and configure

---

#### MODE 1: Discovery Search — finding genomes by keyword or organism

Use this when you want to explore what sequencing data exists for an organism, environment,
or topic. This is the most commonly used mode.

**How SRA search works:**
The SRA search uses **Boolean logic** — the same system used in PubMed or Google Scholar.
You can combine terms with `AND`, `OR`, `NOT` and use `" "` for exact phrases.

```yaml
search_filters:
  query: "Anoxybacillaceae OR Anoxybacillus"   # Your search terms
  strategy: "WGS"          # WGS = Whole Genome Sequencing (recommended for genomes)
  selection: "random"      # random = true genomic data (avoids PCR-amplified data)
  platform: "PACBIO_SMRT"  # PACBIO_SMRT | OXFORD_NANOPORE | ILLUMINA
  max: 1000                # Maximum results to return
  detailed: true           # Return all metadata columns (recommended)
  verbosity: 3             # 0=minimal, 1=default, 2=more, 3=maximum metadata
```

**Broad search vs specific search:**

> 💡 **Start broad, then filter in the spreadsheet.** A broad search with many results
> that you sort in LibreOffice is usually more productive than a narrow search that
> misses good datasets due to inconsistent naming.

```yaml
# BROAD SEARCH — cast a wide net, filter results in spreadsheet afterwards
search_filters:
  query: "Anoxybacillaceae OR Anoxybacillus"
  detailed: true
  max: 1000
  verbosity: 3

# NARROW SEARCH — specific platform + date + size filtering
search_filters:
  query: "(Anoxybacillus OR Bacteria) AND (HiFi OR CCS OR Duplex)"
  strategy: "WGS"
  selection: "random"
  platform: "PACBIO_SMRT"
  publication-date: "01-01-2023:01-02-2026"
  mbases: "1000"           # Minimum ~1 GB data (needed for assembly)
  detailed: true
  verbosity: 3

# ECOLOGICAL SEARCH — by environment rather than organism
search_filters:
  query: '("metagenome-assembled genomes" OR MAGs) AND ("hot spring" OR "volcanic") AND ("Iceland" OR "Kamchatka")'
  strategy: "WGS"
  selection: "random"
  max: 100
  detailed: true
  verbosity: 3
```

**Tips for broadening or narrowing results:**

| To get MORE results (↑) | To get FEWER, more specific results (↓) |
|------------------------|----------------------------------------|
| Use general terms: "bacteria", "hot springs" | Use Boolean: "(Thermococcus AND PACBIO_SMRT)" |
| Leave platform, layout, organism blank | Specify exact platform and organism |
| Remove `strategy` and `selection` filters | Add `strategy: WGS` and `selection: random` |
| Widen date range: "01-01-2010:01-01-2026" | Restrict to recent dates only |
| Remove `mbases` filter | Set `mbases: "2000"` (≥2GB for assembly) |
| Use OR between related terms | Use AND between required terms |

**Key platform values:**
```
PACBIO_SMRT      → PacBio CLR and HiFi reads (best for isolate genome assembly)
OXFORD_NANOPORE  → Oxford Nanopore reads
ILLUMINA         → Illumina short reads (paired-end)
```

**Key strategy values:**
```
WGS        → Whole Genome Sequencing (isolate genomes, MAGs)
AMPLICON   → 16S/ITS amplicon sequencing (taxonomy only, not for assembly)
RNA-Seq    → Transcriptomics
```

---

#### MODE 2: Targeted Project Fetch — getting all data from a known project

Use this when you already have a project ID from a paper, collaborator, or previous
search. This retrieves all metadata for every run in that project.

```yaml
# Using a BioProject accession (PRJNA) — most common in publications
sra_project: "PRJNA525015"
metadata_options:
  detailed: true      # Full metadata for all runs
  assay: true         # Include experimental design details

# Using an SRP project accession
sra_project: "SRP166933"
metadata_options:
  detailed: true
  assay: true
  desc: true          # Include project description
  expand: true        # Expand all attributes
```

> 💡 **Finding project IDs from publications:** Most papers that deposit sequencing data
> include a statement like *"Raw sequencing data are available at NCBI SRA under BioProject
> accession PRJNA525015"* in the Data Availability section. Copy that accession directly
> into `sra_project:`.

---

#### MODE 3: DOI Conversion — finding data from a paper's DOI

Use this when you have found a paper and want to retrieve its associated SRA data without
manually searching. Paste the paper's DOI and the pipeline will find all linked accessions.

```yaml
doi_conversion:
  doi: "10.1038/s41586-020-2286-9"    # Paste the paper's DOI here
  output: "paper_identifiers.tsv"     # Output filename
```

> 💡 The DOI is found in the paper URL or citation. For example:
> `https://doi.org/10.1038/s41586-020-2286-9` → DOI is `10.1038/s41586-020-2286-9`

---

### 3. Run the pipeline

```bash
# Dry run first — check config is valid
pixi run dry-sra-search

# Run the search
pixi run run-sra-search
```

SRA searches are fast (seconds to minutes) so tmux is not required.

---

### 4. Open and sort your results

Results are saved as `.tsv` files in `sra_search_output/`. Open in LibreOffice Calc or
Microsoft Excel for easy sorting and filtering:

```bash
# Open in LibreOffice
libreoffice --calc sra_search_output/search_data/*.tsv

# Or view in terminal
column -t -s $'\t' sra_search_output/search_data/*.tsv | less -S
```

**Recommended columns to sort/filter by:**

| Column | What to look for |
|--------|-----------------|
| `experiment_library_strategy` | Keep `WGS`, remove `AMPLICON`, `RNA-Seq` |
| `experiment_platform` | Filter by `PACBIO_SMRT` or `OXFORD_NANOPORE` for assembly |
| `run_total_bases` | Larger = more coverage. Need ≥1GB for assembly |
| `run_total_spots` | Number of reads |
| `experiment_library_selection` | `random` is best for genome assembly |
| `run_published` | Publication date — prefer recent data |
| `organism_name` | Verify the organism matches what you expect |
| `sample_geo_loc_name` | Geographic origin of the sample |

**Workflow after sorting:**
1. Open `.tsv` in LibreOffice/Excel
2. Filter `experiment_library_strategy` = `WGS`
3. Filter platform to your preferred technology
4. Sort by `run_total_bases` descending (highest coverage first)
5. Copy the `run_accession` (SRR numbers) of your selected datasets
6. Paste into `config_auto.yaml` (for long-read assembly) or `config_hybracter.yaml`
   (for hybrid assembly)

---

### 5. Use accessions in other pipelines

Once you have selected your SRR accessions from the spreadsheet:

**For long-read genome assembly (Autocycler):**
```yaml
# config/config_auto.yaml
sra:
  accession: "SRR27003629"
  genus_name: "Anoxybacillus"
  tech_tag: "pacbio_clr"
  genome_size: "3000000"
```

**For hybrid assembly (Hybracter):**
```yaml
# config/config_hybracter.yaml
hybracter_sra_samples:
  MY_SAMPLE:
    short: "SRR5413257"   # Illumina accession
    long:  "SRR5413256"   # Long-read accession
```

**For MAG assembly (coming soon — MAG bundle):**
```yaml
# MAG bundle config (in preparation)
# MetaWRAP / nf-core MAG pipeline
```

---

## Troubleshooting

| Problem | Likely cause | Solution |
|---------|-------------|----------|
| Empty results file | Search terms too specific | Broaden query, remove platform/strategy filters |
| Too many results (>10,000) | Query too broad | Add `strategy: WGS`, restrict platform or date |
| `pysradb` connection error | Network issue or NCBI rate limit | Wait 5 minutes and retry |
| DOI conversion returns nothing | DOI not linked to SRA data | Search manually on NCBI using paper title |
| `.tsv` file has no useful columns | `verbosity` too low | Set `verbosity: 3` and `detailed: true` |
| Results include amplicon/16S data | No strategy filter | Add `strategy: "WGS"` to config |

---

## Understanding the Output: Long Reads for Genomes vs MAGs

The SRA contains two fundamentally different types of long-read data — knowing the
difference helps you filter results correctly:

| Data type | What it is | Use for | Key identifier |
|-----------|-----------|---------|---------------|
| **Isolate WGS** | Sequencing of a single cultured organism | Genome assembly (Autocycler, Hybracter) | `source: genomic`, organism has a species name |
| **Metagenomic WGS** | Sequencing of an entire community (soil, gut, water) | MAG assembly (MetaWRAP, nf-core/MAG) | `source: metagenomic`, organism = "metagenome" |

> 💡 For isolate genome assembly, filter for `source: genomic`.
> For MAG recovery, filter for `source: metagenomic`.
> Both require `strategy: WGS` and sufficient data size (`mbases` ≥ 1000).

---

## Quick Reference: All Search Parameters

```yaml
search_filters:
  query: ""              # Search terms (Boolean AND/OR/NOT supported)
  max: 1000              # Maximum results (default: 20)
  publication-date: ""   # "DD-MM-YYYY:DD-MM-YYYY"
  strategy: ""           # WGS | AMPLICON | RNA-Seq | ...
  source: ""             # genomic | metagenomic | transcriptomic | ...
  selection: ""          # random | PCR | random PCR | size fractionation | ...
  platform: ""           # PACBIO_SMRT | OXFORD_NANOPORE | ILLUMINA | ...
  layout: ""             # SINGLE | PAIRED
  organism: ""           # Scientific name e.g. "Bacillus"
  verbosity: 3           # 0=minimal → 3=maximum metadata
  mbases: ""             # Minimum data size in MB (1000 = 1GB)
  detailed: true         # Return all metadata columns
  accession: ""          # Search by specific accession number(s)
  db: ""                 # sra | ena | geo
  geo_query: ""          # GEO database free-text search
```

---

*Part of the [taxonomy_bundle](https://github.com/bharat1912/taxonomy_bundle) project.*
*Please cite the original authors of each tool used in your publications.*
