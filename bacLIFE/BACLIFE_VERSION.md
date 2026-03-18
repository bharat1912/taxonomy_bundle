# bacLIFE Version and Patch Record

## Upstream Source
- **Repository:** https://github.com/bharat1912/bacLIFE.git
- **Upstream commit at integration:** `1499393d6409fcb4cd59d0867ebd787685edc9fd`
- **Integration date:** March 2026
- **Original bacLIFE paper:** Carrión et al. https://doi.org/10.1038/s41467-024-46302-y

## ⚠️ WARNING: Do NOT run `git clone` or `git pull` bacLIFE into this directory

bacLIFE was originally cloned from the Carrion-lab repository. The `.git`
directory inside `bacLIFE/` has been intentionally removed so that the patched
files below can be tracked in the taxonomy_bundle repository.

**If you clone bacLIFE fresh into this directory, the following patched files
will be overwritten and the pipeline WILL break:**

| File | What was changed | Why |
|------|-----------------|-----|
| `Snakefile` | Added `rm -rf intermediate_files/clustering/` before mmseqs2 step | Prevents stale clustering outputs from previous runs causing failures |
| `Snakefile` | Added `rm -rf intermediate_files/phylophlan/output_phylophlan/` before phylophlan step | Same — prevents stale RAxML files blocking new runs |
| `Snakefile` | Changed `rename_MEGAMATRIX` output from `mapping_file.txt` to `mapping_file_baclife_generated.txt` | Prevents overwriting user-curated lifestyle labels |
| `src/rename_MEGAMATRIX.R` | Full rewrite (v2) — graceful handling of unmapped genomes | Original silently set all lifestyles to "Unknown" and broke on new genomes |
| `names_equivalence.txt` | Extended to 81 entries including 30 ThermoBase genomes | Required for correct column renaming in MEGAMATRIX |
| `config.json` | threads:32, mcl_inflation_value:3.0, linclust_identity:0.95 | Tuned for 32-core workstation |

## Analysis Scripts Added (not in upstream bacLIFE)

| File | Description |
|------|-------------|
| `extract_TH_LAGs_v5.R` | LAG extraction — reads MEGAMATRIX.txt directly with 4-part sample names |
| `TH_LAG_summary_v5.R` | LAG summary, Rnf complex analysis, publication-ready output tables |

## If You Need to Update bacLIFE

To safely incorporate upstream bacLIFE changes:
```bash
# 1. Clone upstream into a temporary directory
git clone https://github.com/Carrion-lab/bacLIFE.git /tmp/bacLIFE_upstream

# 2. Manually diff the patched files
diff /tmp/bacLIFE_upstream/Snakefile \
     ~/software/taxonomy_bundle/bacLIFE/Snakefile

diff /tmp/bacLIFE_upstream/src/rename_MEGAMATRIX.R \
     ~/software/taxonomy_bundle/bacLIFE/src/rename_MEGAMATRIX.R

# 3. Copy only non-patched files you want to update
cp /tmp/bacLIFE_upstream/src/MCL_merge.R \
   ~/software/taxonomy_bundle/bacLIFE/src/MCL_merge.R

# 4. Re-apply patches if Snakefile was updated (see patch table above)
# 5. Test with a dry run before committing
cd ~/software/taxonomy_bundle/bacLIFE
pixi run -e env-baclife snakemake --dry-run --cores 16 -s Snakefile
```

## Reproducibility

To reproduce the v5 thermohalophile analysis from scratch:
```bash
cd ~/software/taxonomy_bundle
pixi run -e env-baclife baclife-setup-full
pixi run -e env-baclife baclife-run-fresh
pixi run -e env-baclife baclife-lag-analysis
pixi run -e env-baclife baclife-lag-summary
# Results in: ~/Desktop/Halophiles_Baclife_Project/v5/
```
