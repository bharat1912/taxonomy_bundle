# bacLIFE: an automated genome mining tool for identification of lifestyle associated genes

bacLIFE is a streamlined computational workflow that annotates bacterial genomes and performs large-scale comparative genomics to predict bacterial lifestyles and to pinpoint candidate genes, denominated  **lifestyle-associated genes (LAGs)**, and biosynthetic gene clusters associated with each lifestyle detected. This whole process is divided into different modules:

- **Clustering module**
	Predicts, clusters and annotates the genes of every input genome
- **Lifestyle prediction**
	Employs a machine learning model to forecast bacterial lifestyle or other specified metadata
- **Analitical module (Shiny app)**
	Results from the previous modules are embedded in a user-friendly interface for comprehensive and interactive comparative genomics.

You can find the complete wiki here [https://github.com/Carrion-lab/bacLIFE/wiki/bacLIFE-wiki] 

![workflow](https://user-images.githubusercontent.com/69348873/231155358-7fbebb3c-f6f6-406a-989b-9d273b83aa1e.png)

# Citation

If you use bacLIFE, please cite:  https://doi.org/10.1038/s41467-024-46302-y





---

# taxonomy_bundle Integration Notes

This copy of bacLIFE is integrated into [taxonomy_bundle](https://github.com/bharat1912/taxonomy_bundle) and contains patches applied on top of upstream commit `1499393d6409fcb4cd59d0867ebd787685edc9fd`.

## ⚠️ Do NOT overwrite with a fresh clone

Running `git clone https://github.com/Carrion-lab/bacLIFE.git` into this directory will overwrite the patches and break the pipeline. See `BACLIFE_VERSION.md` for full details and safe update instructions.

## Patches applied

| File | Change |
|------|--------|
| `Snakefile` | Auto-cleans stale clustering and phylophlan outputs before reruns |
| `Snakefile` | `rename_MEGAMATRIX` writes to `mapping_file_baclife_generated.txt` — preserves user lifestyle labels |
| `src/rename_MEGAMATRIX.R` | v2 rewrite — handles unmapped genomes gracefully |
| `names_equivalence.txt` | Extended to 81 entries (30 ThermoBase genomes added) |
| `config.json` | Tuned for 32-core workstation |

## Analysis scripts added

| File | Description |
|------|-------------|
| `extract_TH_LAGs_v5.R` | Thermohalophile LAG extraction |
| `TH_LAG_summary_v5.R` | LAG summary and Rnf complex analysis |

## Setup via taxonomy_bundle
```bash
git clone https://github.com/bharat1912/taxonomy_bundle.git
cd taxonomy_bundle
pixi install
pixi run -e env-baclife baclife-setup-full
pixi run -e env-baclife baclife-help
```

## Citation

If you use bacLIFE please cite the original paper:
> Carrión et al. (2024) https://doi.org/10.1038/s41467-024-46302-y
