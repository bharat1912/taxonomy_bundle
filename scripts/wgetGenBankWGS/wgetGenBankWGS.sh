#!/bin/bash

#############################################################################################################
#                                                                                                           #
# wgetGenBankWGS: downloading WGS genome assembly files from NCBI                                           #
#                                                                                                           #
  COPYRIGHT="Copyright (C) 2019-2025 Institut Pasteur"                                                      #
#                                                                                                           #
# This program  is free software:  you can  redistribute it  and/or modify it  under the terms  of the GNU  #
# General Public License as published by the Free Software Foundation, either version 3 of the License, or  #
# (at your option) any later version.                                                                       #
#                                                                                                           #
# This program is distributed in the hope that it will be useful,  but WITHOUT ANY WARRANTY;  without even  #
# the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public  #
# License for more details.                                                                                 #
#                                                                                                           #
# You should have received a copy of the  GNU General Public License along with this program.  If not, see  #
# <http://www.gnu.org/licenses/>.                                                                           #
#                                                                                                           #
# Contact:                                                                                                  #
#  Alexis Criscuolo                                                            alexis.criscuolo@pasteur.fr  #
#  Genome Informatics & Phylogenetics (GIPhy)                                             giphy.pasteur.fr  #
#  Centre de Ressources Biologiques de l'Institut Pasteur (CRBIP)                         crbip.pasteur.fr  #
#  Institut Pasteur, Paris, FRANCE                                                     research.pasteur.fr  #
#                                                                                                           #
#            4888888883                                                                                     #
#         48800007   4003 1                                                                                 #
#      4880000007   400001 83        101  100    01   4000009  888888888 101 888888888 08    80 888888888   #
#     4000000008    8000001 83       181  10101  01  601     1    181    181    181    08    80    181      #
#    40000000008    8000001 803      181  10 101 01    60003      181    181    181    08    80    181      #
#   100888880008    800007 60003     181  10  10101  4     109    181    181    181    68    87    181      #
#   81     68888    80887 600008     101  10    001   0000007     101    101    101     600009     101      #
#   808883     1    887  6000008                                                                            #
#   8000000003         480000008                                                                            #
#   600000000083    888000000007     10000000     40      4000009  888888888 10000000  08    80  1000000    #
#    60000000008    80000000007      180    39   4000    601     1    181    10        08    80  10    39   #
#     6000000008    8000000007       18000007   47  00     60003      181    1000000   08    80  1000007    #
#      680000008    800000087        180       40000000  4     109    181    10        68    87  10   06    #
#        6888008    8000887          100      47      00  0000007     101    10000000   600009   10    00   #
#            688    8887                                                                                    #
#                                                                                                           #
#############################################################################################################

#############################################################################################################
#                                                                                                           #
# ============                                                                                              #
# = VERSIONS =                                                                                              #
# ============                                                                                              #
#                                                                                                           #
  VERSION=0.93-250324ac                                                                                     #
# + simplified output file name for some type strains                                                       #
#                                                                                                           #
# VERSION=0.92-240423ac                                                                                     #
# + fixed bug in type strain selection                                                                      #
# + updated trap                                                                                            #
#                                                                                                           #
# VERSION=0.91.240111ac                                                                                     #
# + fixed bug in trap function                                                                              #
#                                                                                                           #
# VERSION=0.9.231202ac                                                                                      #
# + new option -T for bacteria type strains                                                                 #
# + no '=' character in output file names                                                                   #
#                                                                                                           #
# VERSION=0.8.230612ac                                                                                      #
# + takes into account the empty fields recently replaced with "na"                                         #
#                                                                                                           #
# VERSION=0.7.211026ac                                                                                      #
# + takes into account the new protocol https in field ftp_path of the genome assembly report files         #
#                                                                                                           #
# VERSION=0.6.211018ac                                                                                      #
# + takes into account the last field 'asm_not_live_date' in genome assembly report files                   #
# + adding option -p to select a specific phylum                                                            #
#                                                                                                           #
# VERSION=0.5.201018ac                                                                                      #
# + adding flag -T- or -t- in file name for type material                                                   #
# + adding flag -w- in file name for genomes excluded from RefSeq                                           #
#                                                                                                           #
# VERSION=0.4.200504ac                                                                                      #
# + discarding option -t (type strain info)                                                                 #
# + option -t for multithread (instead of -c)                                                               #
# + adding single quote (') in the list of special characters                                               #
# + deals with wgs_master starting with 6 alphabetic characters                                             #
# + new option -f to download different file types                                                          #
# + new option -z to keep compressed format                                                                 #
#                                                                                                           #
# VERSION=0.3.190613ac                                                                                      #
# + no test between ftp and http protocols; use directly http                                               #
# + fixed bug when the specified pattern has no match                                                       #
#                                                                                                           #
# VERSION=0.2.190228ac                                                                                      #
# + option -d for downloading from either genbank or refseq                                                 #
# + option -t to get the type strain name(s) for each selected species                                      #
#                                                                                                           #
# VERSION=0.1.190124ac                                                                                      #
#                                                                                                           #
#############################################################################################################

#############################################################################################################
#                                                                                                           #
# ============                                                                                              #
# = DOC      =                                                                                              #
# ============                                                                                              #
#                                                                                                           #
if [ "$1" = "-?" ] || [ "$1" = "-h" ] || [ $# -le 1 ]                                                       #
then                                                                                                        #
  cat <<EOF

 wgetGenBankWGS v.$VERSION                                    $COPYRIGHT

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

EOF
  exit 1 ;                                                                                                  # 
fi                                                                                                          # 
#                                                                                                           #
#############################################################################################################

#############################################################################################################
#                                                                                                           #
# ===============                                                                                           #
# = CONSTANTS   =                                                                                           #
# ===============                                                                                           #
#                                                                                                           #
# = PROTOCOL; since Sep. 2021, the default protocol is "https" ===========================================  #
#                                                                                                           #
  PROTOCOL="https:";                                                                                        
#                                                                                                           #
# = WGETOPT are the basic wget options ===================================================================  #
#                                                                                                           #
  WGETOPT="--no-check-certificate --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -q";     
#                                                                                                           #
# = WAITIME when every threads are running (in seconds) ==================================================  #
#                                                                                                           #
  WAITIME=0.5;
#                                                                                                           #
#############################################################################################################

#############################################################################################################
#                                                                                                           #
# ===============                                                                                           #
# = BINARIES    =                                                                                           #
# ===============                                                                                           #
#                                                                                                           #
  if [ ! $(command -v wget) ]; then echo "wget not found"   >&2 ; exit 1 ; fi
#                                                                                                           #
#############################################################################################################

#############################################################################################################
#                                                                                                           #
# ===============                                                                                           #
# = FUNCTIONS   =                                                                                           #
# ===============                                                                                           #
#                                                                                                           #
# = gettime() arguments: =================================================================================  #
#    1. START: the starting time in seconds                                                                 #
#   returns the elapsed time since $START                                                                   #
gettime() {
  t=$(( $SECONDS - $1 )); sec=$(( $t % 60 )); min=$(( $t / 60 ));
  if [ $sec -lt 10 ]; then sec="0$sec"; fi
  if [ $min -lt 10 ]; then min="0$min"; fi
  echo "[$min:$sec]" ;
}
#                                                                                                           #
# = randomfile() arguments: ==============================================================================  #
#    1. PREFIX: prefix file name                                                                            #
#   returns a random file name from a given PREFIX file name                                                #
#                                                                                                           #
randomfile() {
  rdmf=$1.$RANDOM; while [ -e $rdmf ]; do rdmf=$1.$RANDOM ; done
  echo $rdmf ;
}
#                                                                                                           #
# = dwnl() arguments: ====================================================================================  #
#    1. URL: URL of the file to download                                                                    #
#    2. OUTFILE: output file name                                                                           #
#   downloads the file from URL and writes it into OUTFILE                                                  #
#                                                                                                           #
dwnl() {
  tmp=$(randomfile $2);
  wget $WGETOPT --spider $1 || return 1 ;
  while [ 1 ]
  do
    wget $WGETOPT -O $tmp $1 ;
    if [ $? == 0 ]; then mv $tmp $2 ; break; fi
    sleep 1 ;
  done
  return 0 ;
}
#                                                                                                           #
# = dwnlgz() arguments: ==================================================================================  #
#    1. URL: URL of the gz file to download                                                                 #
#    2. OUTFILE: output file name                                                                           #
#   downloads the file from URL and unzip it into OUTFILE                                                   #
#                                                                                                           #
dwnlgz() {
  tmp=$(randomfile $2);
  wget $WGETOPT --spider $1 || return 1 ;
  while [ 1 ]
  do
    wget $WGETOPT -O $tmp $1 ;
    if [ $? == 0 ]; then gunzip -c $tmp > $2 ; rm $tmp ; break; fi
    sleep 1 ;
  done
  return 0 ;
}
#                                                                                                           #
#############################################################################################################


#############################################################################################################
####                                                                                                     ####
#### INITIALIZING PARAMETERS AND READING OPTIONS                                                         ####
####                                                                                                     ####
#############################################################################################################
INCLUDE_PATTERN="";
EXCLUDE_PATTERN="^#";
REPOSITORY="genbank";
OUTDIR=".";
NTHREADS=1;
DWNL=true;
FTYPE=1;
PHYLUM="all";
TYPESTRAIN=false;
UNZIP=true;
while getopts :e:v:o:t:d:f:p:Tnz option
do
  case $option in
    e) INCLUDE_PATTERN="$OPTARG"                         ;;
    v) EXCLUDE_PATTERN="$OPTARG"                         ;;
    d) REPOSITORY="$OPTARG"                              ;;
    p) PHYLUM="$OPTARG"                                  ;;
    T) TYPESTRAIN=true                                   ;;
    o) OUTDIR="$OPTARG"                                  ;;
    t) NTHREADS=$OPTARG                                  ;;
    f) FTYPE=$OPTARG                                     ;;
    n) DWNL=false                                        ;;
    z) UNZIP=false                                       ;;
    :) echo "option $OPTARG : missing argument" ; exit 1 ;;
   \?) echo "$OPTARG : option invalide" ;         exit 1 ;;
  esac
done
if [ -z "$INCLUDE_PATTERN" ]; then echo "no specified pattern (option -e)" ;                                                                  exit 1 ; fi
if [ $NTHREADS -lt 1 ];       then echo "incorrect number of threads (option -t): $THREADS" ;                                                 exit 1 ; fi
if [ "$REPOSITORY" != "genbank" ] && [ "$REPOSITORY" != "refseq" ]; then "incorrect repository name (options -d): $REPOSITORY" ;              exit 1 ; fi
INEXT="_genomic.fna.gz"; OUTEXT=".fasta";
if $DWNL
then
  if   [ "$FTYPE" == "1" ]; then echo "file type: genomic sequence(s) in FASTA format" ;   FTYPE=1; INEXT="_genomic.fna.gz";          OUTEXT=".fasta";
  elif [ "$FTYPE" == "2" ]; then echo "file type: genomic sequence(s) in GenBank format" ; FTYPE=2; INEXT="_genomic.gbff.gz";         OUTEXT=".gbk";
  elif [ "$FTYPE" == "3" ]; then echo "file type: annotations in GFF3 format" ;            FTYPE=3; INEXT="_genomic.gff.gz";          OUTEXT=".gff";
  elif [ "$FTYPE" == "4" ]; then echo "file type: codon CDS in FASTA format" ;             FTYPE=4; INEXT="_cds_from_genomic.fna.gz"; OUTEXT=".fasta";
  elif [ "$FTYPE" == "5" ]; then echo "file type: amino acid CDS in FASTA format" ;        FTYPE=5; INEXT="_protein.faa.gz";          OUTEXT=".fasta";
  elif [ "$FTYPE" == "6" ]; then echo "file type: RNA sequences in FASTA format" ;         FTYPE=6; INEXT="_rna_from_genomic.fna.gz"; OUTEXT=".fasta";
  else echo "incorrect file type (option -f): $FTYPE" ;                                                                                       exit 1 ;
  fi
fi
if [ "$PHYLUM" != "all" ]
then
  if   [ "$PHYLUM" == "A" ]; then PHYLUM="archaea";
  elif [ "$PHYLUM" == "B" ]; then PHYLUM="bacteria";
  elif [ "$PHYLUM" == "F" ]; then PHYLUM="fungi";
  elif [ "$PHYLUM" == "I" ]; then PHYLUM="invertebrate";
  elif [ "$PHYLUM" == "M" ]; then PHYLUM="vertebrate_mammalian";
  elif [ "$PHYLUM" == "N" ]; then PHYLUM="vertebrate_other";
  elif [ "$PHYLUM" == "P" ]; then PHYLUM="plant";
  elif [ "$PHYLUM" == "V" ]; then PHYLUM="viral";
  elif [ "$PHYLUM" == "Z" ]; then PHYLUM="protozoa";
  else echo "incorrect phylum (option -p): $PHYLUM" ;                                                                                         exit 1 ;
  fi
fi
OUTDIR=$(dirname $OUTDIR/.);
if [ ! -e $OUTDIR ];          then echo "creating output directory: $OUTDIR" ; mkdir $OUTDIR ; fi

finalize() {
  echo "interrupting ..." ;
  wait ;
  if [ \"$OUTDIR\" != \".\" ]
  then rm -rf $OUTDIR ;
  else rm -f  summary.txt.[0123456789]* ;
  fi
}
trap 'finalize ; exit 1' SIGTERM SIGINT SIGQUIT SIGHUP TERM INT QUIT HUP ;


#############################################################################################################
####                                                                                                     ####
#### DOWNLOADING GENOME ASSEMBLY REPORT FILE                                                             ####
####                                                                                                     ####
#############################################################################################################
if [ "$PHYLUM" == "all" ]
then
  echo -n "downloading $REPOSITORY assembly report ... " ;
  ASSEMBLY_REPORT=ftp.ncbi.nlm.nih.gov/genomes/ASSEMBLY_REPORTS/assembly_summary_$REPOSITORY.txt;
else
  echo -n "downloading $REPOSITORY ($PHYLUM) assembly report ... " ;
  ASSEMBLY_REPORT=ftp.ncbi.nlm.nih.gov/genomes/$REPOSITORY/$PHYLUM/assembly_summary.txt;
fi  
SUMMARY=$OUTDIR/summary.txt;
dwnl $PROTOCOL"//"$ASSEMBLY_REPORT $SUMMARY ;
echo "[ok]" ;


#############################################################################################################
####                                                                                                     ####
#### SELECTING WGS ENTRIES                                                                               ####
####                                                                                                     ####
#############################################################################################################
echo "selection criterion: $INCLUDE_PATTERN" ;
if [ "$EXCLUDE_PATTERN" != "^#" ]; then echo "exclusion criterion: $EXCLUDE_PATTERN" ; fi
tmp=$(randomfile $SUMMARY);
mv $SUMMARY $tmp ;
{ sed -n '2p' $tmp ;
  sed '1,2d' $tmp | grep -E "$INCLUDE_PATTERN" | grep -v -E "$EXCLUDE_PATTERN" | grep -F "ftp.ncbi.nlm.nih.gov" ;
} > $SUMMARY ;
if $TYPESTRAIN
then
  mv $SUMMARY $tmp ;
  { sed -n '1p' $tmp ;
    sed '1d' $tmp | grep -E "assembly from type material|assembly designated as neotype" ;
  } > $SUMMARY ;
fi
rm $tmp ;
n=$(grep -v -c "^#" $SUMMARY);
echo "$REPOSITORY: $n entries" ;
if [ $n -eq 0 ]; then exit 0 ; fi


if ! $DWNL ; then echo "see details in the report file: $SUMMARY" ; exit 0 ;  fi


#############################################################################################################
####                                                                                                     ####
#### DOWNLOADING WGS NUCLEOTIDE SEQUENCES                                                                ####
####                                                                                                     ####
#############################################################################################################
FULLSUMMARY=$(randomfile $SUMMARY);
head -1 $SUMMARY | sed 's/^# /# file\t/' > $FULLSUMMARY ;
tr '\t' '|' < $SUMMARY > $tmp ; mv $tmp $SUMMARY ;  ## to deal with empty entries, not well managed using IFS=$'\t'
START=$SECONDS;
i=-1;
#230612               assembly_accession _ _ wgs_master _ _ _ organism_name infraspecific_name isolate _ _ _ _ _ _ _ _ _ ftp_path excluded_from_refseq relation_to_type_material _
while IFS="|" read -r assembly_accession _ _ wgs_master _ _ _ organism_name infraspecific_name isolate _ _ _ _ _ _ _ _ _ ftp_path excluded_from_refseq relation_to_type_material _
do
  let i++; if [ $i -lt 1 ]; then continue; fi

  NAME=$(echo "$organism_name" | tr ",/\?%*:|'\"<>()[]#;" '_' |                                              ### replacing special char. by '_'
           sed -e 's/ bv\./ bv/;s/ genomosp\./ genomosp/;s/ sp\./ sp/;s/ str\./ str/;s/ subsp\./ subsp/');
  PNAME="$NAME";

  STRAIN=$(echo "$infraspecific_name" | grep -v "^na$" | sed 's/type strain: //g;s/strain=//g' | tr ",/\?%*:|'\"<>()[]#;" '_'); ### replacing special char. by '_'
  [ -n "$STRAIN" ]  && [ $(echo "$NAME" | grep -c -F "$STRAIN") -eq 0 ]  && NAME="$NAME.$STRAIN";

  ISOLATE=$(echo "$isolate" | grep -v "^na$" | tr ",/\?%*:|'\"<>()[]#;" '_');                                ### replacing special char. by '_'
  [ -n "$ISOLATE" ] && [ $(echo "$ISOLATE" | grep -c "$STRAIN") -ne 0 ]  && NAME="$PNAME";
  [ -n "$ISOLATE" ] && [ $(echo "$NAME" | grep -c -F "$ISOLATE") -eq 0 ] && NAME="$NAME.$ISOLATE";

  TYPE_MATERIAL="$(grep -v "^na$" <<<"$relation_to_type_material")";
  [ "$TYPE_MATERIAL" == "assembly from type material" ]                  && NAME="$NAME""--T";
  [ "$TYPE_MATERIAL" == "assembly from synonym type material" ]          && NAME="$NAME""--t";
  [ "$TYPE_MATERIAL" == "assembly designated as neotype" ]               && NAME="$NAME""--T";

  NOT_REFSEQ="$(grep -v "^na$" <<<"$excluded_from_refseq")";
  [ "$NOT_REFSEQ" == "untrustworthy as type" ]                           && NAME="$NAME""--t";
  [ -n "$NOT_REFSEQ" ] && [ "$NOT_REFSEQ" != "untrustworthy as type" ]   && NAME="$NAME""--w";

  WGS_ACCN="$(grep -v "^na$" <<<"$wgs_master")";
  [ -n "$WGS_ACCN" ]                                                     && NAME="$NAME""--""$WGS_ACCN";

  ASS_ACCN="$(grep -v "^na$" <<<"$assembly_accession")";
  [ -n "$ASS_ACCN" ]                                                     && NAME="$NAME""--""$ASS_ACCN";
  
  GZFILE=$(basename $ftp_path)$INEXT;
  URL=$(echo $ftp_path | sed "s/ftp:/$PROTOCOL/")"/$GZFILE";

  >&2 echo -e "$(gettime $START) [$i/$n] $organism_name | $infraspecific_name | $ISOLATE | $ASS_ACCN | $WGS_ACCN | \e[31m$NOT_REFSEQ\e[0m \e[34m$TYPE_MATERIAL\e[0m | $ftp_path" ;

  OUTFILE=$(echo "$NAME" | tr ' ' '.' | sed 's/\.\.*/\./g' | sed 's/\.=\./\.\./g')$OUTEXT;       ### replacing blank spaces by '.', and successive dots by only one

  if $UNZIP
  then
    dwnlgz $URL $OUTDIR/$OUTFILE &
    echo -e "$OUTFILE\t$(sed -n $(( $i + 1 ))p $SUMMARY)" ;
  else
    dwnl $URL $OUTDIR/$OUTFILE.gz &
    echo -e "$OUTFILE.gz\t$(sed -n $(( $i + 1 ))p $SUMMARY)" ;
  fi
    
  while [ $(jobs -r | wc -l) -gt $NTHREADS ]; do sleep $WAITIME ; done

done  <  $SUMMARY  |  tr '|' '\t'  >>  $FULLSUMMARY ;


wait ;


#############################################################################################################
####                                                                                                     ####
#### CHECKING EXISTING FILES                                                                             ####
####                                                                                                     ####
#############################################################################################################
awk -v d=$OUTDIR 'BEGIN  {FS=OFS="\t"}
                  (NR==1){print;next}
                         {l=$0;
                          if(getline < (d"/"$1) <= 0){$1="na";l=$0}
                          print l}' $FULLSUMMARY > $SUMMARY ;
rm $FULLSUMMARY ;
n=$(grep -Pc "^na\t" $SUMMARY);
if [ $n -ne 0 ]; then echo "WARNING: $n files are not available with the specified file type (-f $FTYPE)" ; fi
echo "see details in the report file: $SUMMARY" ;


exit ;
