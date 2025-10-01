# wgetGenBankWGS

_wgetGenBankWGS_ is a command line program written in [Bash](https://www.gnu.org/software/bash/) to download genome assembly files from the GenBank or RefSeq repositories.
The files to dowload are selected from the [GenBank](https://ftp.ncbi.nlm.nih.gov/genomes/ASSEMBLY_REPORTS/assembly_summary_genbank.txt) or [RefSeq](https://ftp.ncbi.nlm.nih.gov/genomes/ASSEMBLY_REPORTS/assembly_summary_refseq.txt) genome assembly reports using [extended regular expressions](https://www.gnu.org/software/grep/manual/grep.html#Regular-Expressions) as implemented by [_grep_](https://www.gnu.org/software/grep/) (with option -E).
Every download is performed by the standard tool [_wget_](https://www.gnu.org/software/wget/).


## Installation and execution

Clone this repository with the following command line:

```bash
git clone https://gitlab.pasteur.fr/GIPhy/wgetGenBankWGS.git
```

Give the execute permission to the file `wgetGenBankWGS.sh`:

```bash
chmod +x wgetGenBankWGS.sh
```

Run _wgetGenBankWGS_ with the following command line model:

```bash
./wgetGenBankWGS.sh [options]
```

## Usage

Run _wgetGenBankWGS_ without option to read the following documentation:

```
 wgetGenBankWGS v.0.9.231202ac                                     Copyright (C) 2019-2023  Institut Pasteur

 Downloading sequence files corresponding to selected entries from genome assembly report files (option -d):
   GenBank:  ftp.ncbi.nlm.nih.gov/genomes/ASSEMBLY_REPORTS/assembly_summary_genbank.txt
   RefSeq:   ftp.ncbi.nlm.nih.gov/genomes/ASSEMBLY_REPORTS/assembly_summary_refseq.txt

 Selected entries (options -e and -v) can be restricted to a specific phylum using option -p:
   -p A      archaea
   -p B      bacteria
   -p F      fungi
   -p I      invertebrate
   -p M      mammalia
   -p N      non-mammalia vertebrate
   -p P      plant
   -p V      virus
   -p Z      protozoa

 Output files 'Species.isolate--accn--GC' can be written with the following content (and extension):
   -f 1      genomic sequence(s) in FASTA format (.fasta)
   -f 2      genomic sequence(s) in GenBank format (.gbk)
   -f 3      annotations in GFF3 format (.gff)
   -f 4      codon CDS in FASTA format (.fasta)
   -f 5      amino acid CDS in FASTA format (.fasta)
   -f 6      RNA sequences in FASTA format (.fasta)

 USAGE:  
    wgetGenBankWGS.sh  -e <pattern>  [-v <pattern>]  [-d <repository>]  [-p <phylum>]  [-T]
                      [-o <outdir>]  [-f <integer>]  [-n]  [-z]  [-t <nthreads>]
  where:
    -e <pattern>  extended regexp selection pattern (mandatory) 
    -v <pattern>  extended regexp exclusion pattern (default: none)
    -d <string>   either 'genbank' or 'refseq' (default: genbank)
    -p <char>     specific phylum (see above; default: not set)
    -T            only bacteria type strains (default: not set)
    -n            no download, i.e. to only print the number of selected files (default: not set)
    -f <integer>  file type identifier (see above; default: 1)
    -z            no unzip, i.e. downloaded files are compressed (default: not set)
    -o <outdir>   output directory (default: .)
    -t <nthreads> number of threads (default: 1)

 EXAMPLES:
  + getting the total number of available fungi genomes inside RefSeq:
     wgetGenBankWGS.sh -e "/" -d refseq -p F -n

  + getting the total number of available complete Salmonella genomes inside RefSeq:
     wgetGenBankWGS.sh -e "Salmonella.*Complete Genome" -p B -d refseq -n

  + getting the total number of genomes inside GenBank deposited in 1996:
     wgetGenBankWGS.sh -e "1996/[01-12]+/[01-31]+" -n
 
  + getting the total number of available SARS-CoV-2 genomes (taxid=2697049) inside GenBank:
     wgetGenBankWGS.sh -e $'\t'2697049$'\t' -n
 
  + downloading the full RefSeq assembly report:
      wgetGenBankWGS.sh -e "/" -d refseq -n
 
  + downloading the GenBank files with the assembly accessions GCF_900002335, GCF_000002415 and GCF_000002765:
     wgetGenBankWGS.sh -e "GCF_900002335|GCF_000002415|GCF_000002765" -d refseq -f 2

  + downloading in the directory Dermatophilaceae every available genome sequence from this family using 30 threads:
     wgetGenBankWGS.sh -e "Austwickia|Dermatophilus|Kineosphaera|Mobilicoccus|Piscicoccus|Tonsilliphilus" -o Dermatophilaceae -t 30

  + downloading all Nostoc genome sequences from the RefSeq that are not derived from metagenome:
     wgetGenBankWGS.sh -e "Nostoc " -v "metagenome" -d refseq

  + downloading the non-Listeria proteomes with the wgs_master starting with "PPP":
     wgetGenBankWGS.sh -e $'\t'"PPP.00000000" -v "Listeria" -f 5

  + downloading the genome annotation of every Klebsiella type strain in compressed gff3 format using 30 threads
     wgetGenBankWGS.sh -e "Klebsiella" -T -f 3 -z -t 30
```


## Notes

* The output file names are created with the organism name, followed by the intraspecific and isolate names (if any), and ending with the WGS master (is any) and the assembly accession. File extension depends on the file type specified using option -f.

* Flag "--T--" is added in the output file name when the corresponding assembly correspond to a type material. Flag "--t--" is added for putative type material that does not meet the full required criteria. Flag "--w--" is added as warning when some assembly anomalies are specified in the report file (for more details, see [https://www.ncbi.nlm.nih.gov/assembly/help/anomnotrefseq/](https://www.ncbi.nlm.nih.gov/assembly/help/anomnotrefseq/)).

* After each usage, a file `summary.txt` containing the selected raw(s) of the GenBank or RefSeq tab-separated assembly report is written. If the option -n is not set, this file is completed by the name(s) of the written files (first column 'file').

* Very fast running times are expected when running _wgetGenBankWGS_ on multiple threads. As a rule of thumb, using twice the maximum number of available threads generally leads to good performances with bacterial genomes (depending on the bandwidth).


