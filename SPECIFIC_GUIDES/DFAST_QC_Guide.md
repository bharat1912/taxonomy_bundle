# DFAST_QC Guide: Taxonomy Check for Isolates and MAGs

## Overview

DFAST_QC performs rapid taxonomy identification and genome completeness checks for
prokaryotic genomes. It uses MASH for rapid sketching, followed by skani for precise
ANI (Average Nucleotide Identity) calculation against reference databases.

**Version in use:** DFAST_QC 1.0.7  
**Environment:** `env-checkm2`  
**Reference data version:** 2025-04-30 (full)

---

## Key Design Decision: Use GTDB, Not the Default NCBI Reference Set

DFAST_QC ships with two reference databases:

| Database | Genomes | Coverage | Use case |
|----------|---------|----------|----------|
| NCBI type strain ref (`ref_genomes_sketch.msh`) | ~70 type strains | Well-characterised species only | Standard isolates with known close relatives |
| GTDB representative genomes (`gtdb_genomes_sketch.msh`) | ~320,000 genomes | Broad prokaryotic diversity | Novel isolates, environmental MAGs, underrepresented taxa |

**Always use `--enable_gtdb`.**

The default NCBI reference set covers only ~70 type strain genomes. For most research
use cases — including environmental isolates, MAGs, and novel species — this will return
`no_hit` even for well-characterised organisms. The GTDB database (129 GB, stored at
`$EXTERNAL_VAULT/dfast_qc_ref/gtdb_genomes_reps/`) covers the full breadth of known
prokaryotic diversity and should always be enabled.

Example: `Hyphomicrobium sp. NDB2Meth4` returns `no_hit` from the NCBI reference set
but returns a **conclusive 100% ANI match** against GTDB (`s__Hyphomicrobium_A sp900117445`).

---

## CheckM Disabled: Known Bug

The `--disable_cc` flag must always be used. DFAST_QC internally calls CheckM v1
(not CheckM2) for completeness checking. CheckM v1 requires `pkg_resources` which
is not available in Python 3.12+ environments:

```
ModuleNotFoundError: No module named 'pkg_resources'
```

**Workaround:** Disable CheckM within DFAST_QC (`--disable_cc`) and run CheckM2
separately if completeness assessment is needed.

---

## CLI Reference

### Standard run (isolate genome)

```bash
pixi run -e env-checkm2 dfast_qc \
  --enable_gtdb \
  --disable_cc \
  -r ~/software/taxonomy_bundle/db_link/dfast_qc_ref \
  -i /path/to/genome.fna \
  -o /path/to/output_dir \
  -n 16
```

### Key flags

| Flag | Description |
|------|-------------|
| `--enable_gtdb` | Search against GTDB representative genomes (REQUIRED) |
| `--disable_cc` | Disable CheckM completeness check (REQUIRED — pkg_resources bug) |
| `-r` | Path to DQC reference directory (`db_link/dfast_qc_ref`) |
| `-i` | Input FASTA file (raw or gzipped) |
| `-o` | Output directory |
| `-n` | Number of threads (use 16) |
| `--force` | Overwrite existing output directory |
| `--disable_auto_download` | Prevent downloading missing reference genomes from NCBI |

### Show available taxa for completeness check

```bash
pixi run -e env-checkm2 dfast_qc --show_taxon
```

---

## Output Files

| File | Contents |
|------|----------|
| `dqc_result.json` | Final summary — taxonomy, ANI, completeness |
| `tc_result.tsv` | NCBI taxonomy check result |
| `result_gtdb.tsv` | GTDB taxonomy result (most useful) |
| `skani_result_gtdb.tsv` | Raw skani ANI results against GTDB hits |
| `target_genomes_gtdb.txt` | List of top 10 GTDB reference genomes selected by MASH |
| `mash_result_gtdb.tab` | Raw MASH distances against GTDB sketch |

---

## Interpreting GTDB Results

```
accession         gtdb_species                  ani    af_ref  af_query  status
GCF_900117445.1   s__Hyphomicrobium_A sp900117445  100.0  100.0   100.0   conclusive
```

| Field | Meaning |
|-------|---------|
| `gtdb_species` | GTDB species name (may differ from NCBI — `_A` suffixes denote split genera) |
| `ani` | ANI % against closest GTDB reference |
| `af_ref` | Alignment fraction of reference covered |
| `af_query` | Alignment fraction of query covered |
| `ani_circumscription_radius` | Species boundary threshold (typically 95%) |
| `status: conclusive` | ANI > circumscription radius — confident species assignment |
| `status: no_hit` | No reference exceeds threshold — novel species or underrepresented taxon |

**GTDB vs NCBI naming:** GTDB reclassifies genera based on phylogeny. A genus suffix
like `_A` (e.g., `Hyphomicrobium_A`) means GTDB has split the original NCBI genus into
multiple monophyletic lineages. The `_A` clade is the one most closely related to the
original type species.

---

## Suitable vs Unsuitable Input

| Genome type | DFAST_QC suitable? | Notes |
|-------------|-------------------|-------|
| Cultured isolate, known genus | Yes | Use `--enable_gtdb` |
| Cultured isolate, novel species | Yes | Will return `no_hit` but GTDB gives closest relative |
| MAG from well-sampled environment (soil, gut) | Partially | May get hits if related to GTDB reps |
| MAG from underrepresented environment (e.g., POND) | No | Use MiGA + GTDB-Tk instead |

---

## Environment Variable Fix Needed

`$DFAST_QC_REF_DIR` is currently not set in the pixi environment. Until fixed,
use the explicit path:

```bash
-r ~/software/taxonomy_bundle/db_link/dfast_qc_ref
```

To fix — add to pixi.toml under the `env-checkm2` activation section:

```toml
[feature.checkm2.activation.env]
DFAST_QC_REF_DIR = "$PIXI_PROJECT_ROOT/db_link/dfast_qc_ref"
```

---

## Reference Data Location

```
$EXTERNAL_VAULT/dfast_qc_ref/
├── ref_genomes_sketch.msh       # NCBI type strain sketch (~70 genomes) — rarely useful
├── gtdb_genomes_sketch.msh      # GTDB sketch (~320k genomes) — primary reference
├── gtdb_genomes_reps/           # 129 GB — GTDB representative genome sequences
├── checkm_data/                 # 1.4 GB — CheckM marker sets (for completeness)
├── genomes/                     # 67 MB — cached reference genomes (downloaded on demand)
└── prokaryote_ANI_species_specific_threshold.txt  # Per-species ANI thresholds
```

Symlinked at: `~/software/taxonomy_bundle/db_link/dfast_qc_ref`

---

## Notes on Reference Genome Downloads

DFAST_QC downloads missing reference genomes from NCBI on first use. These are cached
in `dfast_qc_ref/genomes/`. You will see 503 errors on first download attempts — these
are retried automatically and succeed on retry. This is normal behaviour when NCBI FTP
is under load.

To avoid downloads entirely (offline use):

```bash
--disable_auto_download
```

Note this may reduce the number of ANI comparisons if reference genomes are not cached.
