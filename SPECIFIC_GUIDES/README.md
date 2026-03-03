# Specific Guides — Taxonomy Bundle

This directory contains step-by-step guides for each of the four Snakemake pipelines
included in the taxonomy bundle. Each guide covers the pipeline overview, configuration,
input options, tools used, troubleshooting, and expected run times.

---

## Pipeline Guides

| Guide | Pipeline | Snakefile | Config | Best for |
|-------|----------|-----------|--------|----------|
| [Autocycler Guide](AUTOCYCLER_GUIDE.md) | Long-read genome assembly | `Snakefile_autocycler.smk` | `config_auto.yaml` | PacBio CLR, PacBio HiFi, ONT reads |
| [Hybracter Guide](HYBRACTER_GUIDE.md) | Hybrid genome assembly | `Snakefile_hybracter.smk` | `config_hybracter.yaml` | Illumina + PacBio/ONT reads |
| [Hybrid Taxonomy Guide](HYBRID_TAXONOMY_GUIDE.md) | Full taxonomy & phylogenomics | `Snakefile_hybrid_taxonomy.smk` | `config_taxonomy_merged.yaml` | Short reads, hybrid, or local lab reads |
| [SRAsearch Guide](SRASEARCH_GUIDE.md) | SRA metadata search & discovery | `Snakefile_SRAsearch.smk` | `config_SRAsearch.yaml` | Finding public genomes before downloading |

---

## Recommended Workflow Order

For a new organism or project, the recommended order is:
```
1. SRASEARCH       → Find relevant public datasets on NCBI SRA
        ↓
2. AUTOCYCLER      → Assemble long-read genomes (PacBio/ONT)
   or HYBRACTER    → Assemble hybrid genomes (Illumina + PacBio/ONT)
   or HYBRID TAX   → Assemble + taxonomy + phylogenomics in one run
        ↓
3. Results feed into downstream pipelines:
   assembly.fasta  → pixi run run-hybrid-taxonomy  (taxonomy & phylogenomics)
   bakta/          → pixi run run-pirate            (pangenomics)
   assembly.fasta  → pixi run cm2-run              (comparative genomics)
```

---

## Additional Documentation

| Document | Contents |
|----------|----------|
| [Installation Guide](INSTALLATION_GUIDE.md) | Full setup instructions for new users |
| [Database Guide](DATABASE_GUIDE.md) | Database installation, sizes, and maintenance |
| [Usage Guide](USAGE_GUIDE.md) | All pixi tasks, environments, and single-tool commands |
| [Setup Script](setup_new_computer.sh) | Interactive setup script for new machines |
| [Test Script](test_taxonomy_bundle_setup.sh) | Automated installation verification |

---

## Coming Soon

- 🚧 **MAG Bundle** — MetaWRAP + nf-core/MAG for metagenome-assembled genomes
- 🚧 **Metabolic Bundle** — DRAM2 + bacLIFE for metabolic reconstruction
- 🚧 **Hybracter long-read only mode** — long-read assembly via `hybracter long`

---

*Part of the [taxonomy_bundle](https://github.com/bharat1912/taxonomy_bundle) project.*
*Please cite the original authors of each tool used in your publications.*
