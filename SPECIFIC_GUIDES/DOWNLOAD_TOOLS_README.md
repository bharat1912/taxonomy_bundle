# Genome & Sequence Download Tools
## taxonomy_bundle — pixi environment guide

This guide covers all genome and sequence download tools available in the `taxonomy_bundle` pixi environments. These tools allow you to search, browse, and download genomes and raw sequencing reads from NCBI, ENA, and other public databases.

---

## Which Environment?

| Tool | pixi environment | Primary use |
|---|---|---|
| `datasets` / `dataformat` | `env-baclife` or `env-a` | Download genomes from NCBI by accession |
| `kingfisher` | `env-a` | Download reads/genomes from SRA, ENA, AWS |
| `sra-tools` (`prefetch`, `fasterq-dump`) | `env-a` | Download and convert SRA reads |
| `entrez-direct` (`esearch`, `efetch`, `elink`) | `env-a` | Query and retrieve NCBI records programmatically |
| `aspera` (`ascp`) | `env-a` | High-speed download from NCBI/ENA via IBM Aspera |
| `bit` | `env-a` | Quick accession-to-genome download helper |

---

## 1. NCBI Datasets CLI (`datasets` / `dataformat`)

The modern NCBI command-line tool for downloading genome assemblies, gene sequences, and metadata.

### Basic genome download by accession
```bash
pixi run -e env-baclife datasets download genome accession GCF_000009045.1 \
  --include genome \
  --no-progressbar \
  --filename my_genome.zip

unzip my_genome.zip -d my_genome_dir
```

### Download multiple accessions from a file
```bash
# Create accession list (one per line)
cat > accessions.txt << 'EOF'
GCF_000009045.1
GCA_000195755.1
GCF_000012345.1
EOF

pixi run -e env-baclife datasets download genome accession \
  --inputfile accessions.txt \
  --include genome \
  --no-progressbar \
  --filename batch.zip
```

> **Tip:** For large batches (>15 accessions), split into batches of ~10 to avoid timeout errors.

### Search for genomes by organism name
```bash
pixi run -e env-baclife datasets summary genome taxon "Halothermothrix orenii" \
  --as-json-lines | \
  pixi run -e env-baclife jq -r '[.accession, .assembly_info.assembly_level, .assembly_stats.contig_n50, .organism.infraspecific_names.strain] | @tsv'
```

### Check assembly details for a specific accession
```bash
pixi run -e env-baclife datasets summary genome accession GCF_000009045.1 \
  --as-json-lines | \
  pixi run -e env-baclife jq -r '[.accession, .organism.organism_name, .organism.infraspecific_names.strain, .assembly_info.assembly_level] | @tsv'
```

### What to include in downloads
```bash
# Genome sequence only (default for bacLIFE)
--include genome

# Genome + annotation (GFF, proteins)
--include genome,gff3,protein

# All available files
--include genome,gff3,rna,cds,protein,seq-report,gbff
```

### Update the datasets client
```bash
# Check current version
pixi run -e env-baclife datasets --version

# Update via pixi
pixi update -e env-baclife ncbi-datasets-cli
```

---

## 2. Kingfisher

A fast, flexible tool for downloading reads and assemblies from SRA, ENA, AWS, and GCP. Particularly good at finding the fastest available download source automatically.

### Download reads by SRA run accession
```bash
pixi run -e env-a kingfisher get -r SRR12345678 -m prefetch
```

### Download with automatic source selection (fastest available)
```bash
pixi run -e env-a kingfisher get -r SRR12345678 -m aws-http ena-ascp ena-ftp prefetch
```

### Download multiple accessions
```bash
pixi run -e env-a kingfisher get \
  -r SRR12345678 SRR12345679 SRR12345680 \
  -m aws-http ena-ftp \
  --output-directory ~/downloads/reads/
```

### Download genome assemblies (not reads)
```bash
pixi run -e env-a kingfisher get -r GCF_000009045.1 -m ncbi-genome
```

### Check available download methods
```bash
pixi run -e env-a kingfisher --list-methods
```

> **Note:** For genome FASTA files specifically, `datasets` (tool #1) is more reliable. Kingfisher excels at downloading raw sequencing reads.

---

## 3. SRA-tools (`prefetch` + `fasterq-dump`)

The standard NCBI toolkit for downloading and converting SRA archives.

### Download an SRA run
```bash
# Download the .sra archive
pixi run -e env-a prefetch SRR12345678 --output-directory ~/sra_cache/

# Convert to FASTQ
pixi run -e env-a fasterq-dump SRR12345678 \
  --outdir ~/fastq_output/ \
  --threads 8 \
  --split-files      # paired-end: creates _1.fastq and _2.fastq
```

### Download + convert in one step
```bash
pixi run -e env-a bash -c "prefetch SRR12345678 && fasterq-dump SRR12345678 --split-files -e 8"
```

### Compress output immediately
```bash
pixi run -e env-a fasterq-dump SRR12345678 --split-files -e 8 | gzip > reads.fastq.gz
```

> **Tip:** Always run `prefetch` first before `fasterq-dump`. Prefetch caches the .sra file which speeds up repeated conversions and allows resuming interrupted downloads.

---

## 4. Entrez Direct (`esearch`, `efetch`, `elink`)

NCBI's Unix command-line tools for searching and retrieving records from all NCBI databases (GenBank, PubMed, Taxonomy, BioSample, SRA, etc.).

### Search for genomes and retrieve accessions
```bash
# Find all complete genomes for a species
pixi run -e env-a esearch -db assembly -query "Halothermothrix orenii[orgn] AND complete genome[filter]" | \
  pixi run -e env-a efetch -format docsum | \
  pixi run -e env-a xtract -pattern DocumentSummary -element AssemblyAccession,AssemblyStatus,SpeciesName
```

### Fetch a genome sequence by accession
```bash
pixi run -e env-a efetch -db nuccore -id CP000100.1 -format fasta > genome.fna
```

### Fetch a protein sequence
```bash
pixi run -e env-a efetch -db protein -id WP_012345678.1 -format fasta > protein.faa
```

### Search SRA for runs associated with a project
```bash
pixi run -e env-a esearch -db sra -query "PRJNA123456[bioproject]" | \
  pixi run -e env-a efetch -format runinfo | \
  cut -d',' -f1 | tail -n +2    # Extract run accessions
```

### Get taxonomy information
```bash
pixi run -e env-a esearch -db taxonomy -query "Thermohalophile[lineage]" | \
  pixi run -e env-a efetch -format xml | \
  pixi run -e env-a xtract -pattern Taxon -element TaxId,ScientificName,Rank
```

> **Note:** Entrez Direct requires an internet connection and respects NCBI's rate limits (3 requests/sec without API key, 10/sec with one). Set your API key:
> ```bash
> export NCBI_API_KEY="your_key_here"
> ```

---

## 5. Aspera (`ascp`)

IBM Aspera high-speed file transfer client. Much faster than HTTP/FTP for large files when bandwidth is available.

### Download from NCBI via Aspera
```bash
# General syntax
pixi run -e env-a ascp -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh \
  -k 1 -T -l 300m \
  anonftp@ftp.ncbi.nlm.nih.gov:/genomes/all/GCF/000/009/045/GCF_000009045.1_ASM904v1/GCF_000009045.1_ASM904v1_genomic.fna.gz \
  ./
```

### Download from ENA via Aspera
```bash
pixi run -e env-a ascp -QT -l 300m -P33001 \
  -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh \
  era-fasp@fasp.sra.ebi.ac.uk:/vol1/fastq/SRR123/SRR12345678/SRR12345678_1.fastq.gz \
  ./
```

> **Tip:** Aspera is most useful for very large files (>1 GB). For typical bacterial genomes (~5 MB), `datasets` or `kingfisher` are simpler. Kingfisher can invoke Aspera automatically with `-m ena-ascp`.

---

## 6. BIT (Bioinformatics Tools)

A collection of convenience scripts. The genome download helper fetches assemblies from NCBI with minimal syntax.

### Download a genome by accession
```bash
pixi run -e env-a bit-dl-ncbi-assemblies -w GCF_000009045.1 -f fasta
```

### Download multiple genomes from a list
```bash
pixi run -e env-a bit-dl-ncbi-assemblies -w accessions.txt -f fasta
```

---

## Practical Workflow: Building a Genome Dataset

This is the workflow used for the bacLIFE 51-genome dataset:

```bash
# Step 1 — Search NCBI for candidate genomes
pixi run -e env-baclife datasets summary genome taxon "Halanaerobium" \
  --as-json-lines | \
  pixi run -e env-baclife jq -r '[.accession, .organism.organism_name, .assembly_info.assembly_level, .assembly_stats.contig_n50] | @tsv' | \
  sort -t$'\t' -k4 -rn | head -10     # Sort by N50, pick best assembly

# Step 2 — Download in small batches
pixi run -e env-baclife datasets download genome accession \
  GCF_000001.1 GCF_000002.1 GCF_000003.1 \
  --include genome --no-progressbar --filename batch1.zip

# Step 3 — Unzip and rename
unzip -q batch1.zip -d batch1_dir
# Rename: GCF_000001.1_ASM1v1_genomic.fna → Organism_species.fna

# Step 4 — Copy to vault (external drive)
cp batch1_dir/ncbi_dataset/data/GCF_*/GCF_*_genomic.fna \
   /media/bharat/volume1/databases/ncbi_genomes/Organism_species.fna

# Step 5 — Create 4-part symlinks for bacLIFE
ln -sfn /media/bharat/volume1/databases/ncbi_genomes/Organism_species.fna \
   ~/software/taxonomy_bundle/bacLIFE/data/Organism_species_STRAIN_O.fna
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Error: Internal error (invalid zip archive)` | Network timeout on large batch | Split into batches of ≤10 accessions |
| `Error: There are no genome assemblies that match your query` | Accession withdrawn/suppressed | Search by organism name to find replacement |
| `New version of client available` | datasets CLI outdated | `pixi update -e env-baclife ncbi-datasets-cli` |
| Aspera key not found | Key path wrong | Check `~/.aspera/connect/etc/` or reinstall Aspera |
| `fasterq-dump` fails | .sra file not cached | Run `prefetch` first, then `fasterq-dump` |

---

## See Also

- [NCBI Datasets documentation](https://www.ncbi.nlm.nih.gov/datasets/docs/)
- [Kingfisher GitHub](https://github.com/wwood/kingfisher-download)
- [SRA-tools documentation](https://github.com/ncbi/sra-tools/wiki)
- [Entrez Direct documentation](https://www.ncbi.nlm.nih.gov/books/NBK179288/)
- `PIXI_GUIDE.md` — bacLIFE-specific setup and troubleshooting
