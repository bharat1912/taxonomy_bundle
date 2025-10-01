#!/bin/bash

##############################################################################################################
#                                                                                                            #
#  OGRI_B: Overall Genome Relatedness Indices using BLAST                                                    #
#                                                                                                            #
   COPYRIGHT="Copyright (C) 2022-2023 Institut Pasteur"                                                      #
#                                                                                                            #
#  This program  is free software:  you can  redistribute it  and/or modify it  under the terms  of the GNU  #
#  General Public License as published by the Free Software Foundation, either version 3 of the License, or  #
#  (at your option) any later version.                                                                       #
#                                                                                                            #
#  This program is distributed in the hope that it will be useful,  but WITHOUT ANY WARRANTY;  without even  #
#  the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public  #
#  License for more details.                                                                                 #
#                                                                                                            #
#  You should have received a copy of the  GNU General Public License along with this program.  If not, see  #
#  <http://www.gnu.org/licenses/>.                                                                           #
#                                                                                                            #
#  Contact:                                                                                                  #
#   Alexis Criscuolo                                                            alexis.criscuolo@pasteur.fr  #
#   Genome Informatics & Phylogenetics (GIPhy)                                             giphy.pasteur.fr  #
#   Centre de Ressources Biologiques de l'Institut Pasteur (CRBIP)             research.pasteur.fr/en/b/VTq  #
#   Institut Pasteur, Paris, FRANCE                                                     research.pasteur.fr  #
#                                                                                                            #
##############################################################################################################

##############################################################################################################
#                                                                                                            #
# ============                                                                                               #
# = VERSIONS =                                                                                               #
# ============                                                                                               #
#                                                                                                            #
  VERSION=1.2.231215ac                                                                                       #
# + every original FASTA file is first copied before processing it (to avoid conflicts when run in parallel) #
# + better harnessing of the multiple threads when preprocessing input sequences                             #
# + catch error messages when a blast+ tool crashes                                                          #
# + updating finalizers                                                                                      #
#                                                                                                            #
# VERSION=1.1.230216ac                                                                                       #
# + updating finalizers for BLAST+ version >= 2.13.0                                                         #
#                                                                                                            #
# VERSION=1.0.220222ac                                                                                       #
#                                                                                                            #
##############################################################################################################
  
##############################################################################################################
#                                                                                                            #
#  ================                                                                                          #
#  = INSTALLATION =                                                                                          #
#  ================                                                                                          #
#                                                                                                            #
#  Just give the execute permission to the script wgetENAHTS.sh with the following command line:             #
#                                                                                                            #
#   chmod +x OGRI_B.sh                                                                                       #
#                                                                                                            #
##############################################################################################################

##############################################################################################################
#                                                                                                            #
# ==============================                                                                             #
# = STATIC FILES AND CONSTANTS =                                                                             #
# ==============================                                                                             #
#                                                                                                            #
# -- PWD: directory containing the current script ---------------------------------------------------------  #
#                                                                                                            #
  PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)";
#                                                                                                            # 
# -- constants --------------------------------------------------------------------------------------------  #
#                                                                                                            #
  NA="._N.o.N._.A.p.P.l.I.c.A.b.L.e_.";
#                                                                                                            #
# -- MINLEGT: expected minimum input sequence length to compute OGRI computing ----------------------------  #
#                                                                                                            #
  MINLGT=1000;
#                                                                                                            #
##############################################################################################################

##############################################################################################################
#                                                                                                            #
#  ================                                                                                          #
#  = FUNCTIONS    =                                                                                          #
#  ================                                                                                          #
#                                                                                                            #
# = echoxit() ============================================================================================   #
#   prints in stderr the specified error message $1 and next exit 1                                          #
#                                                                                                            #
echoxit() {
  echo "$1" >&2 ; exit 1 ;
}    
#                                                                                                            #
# = randfile =============================================================================================   #
#   creates and returns a random file name that does not exist from the specified basename $1                #
#                                                                                                            #
randfile() {
  local rdf="$(mktemp $1.XXXXXXXXX)";
  echo $rdf ;
}
#                                                                                                            #
# = mandoc() =============================================================================================   #
#   prints the doc                                                                                           #
#                                                                                                            #
mandoc() {
  echo -e "\n\033[1m OGRI_B v$VERSION                       $COPYRIGHT\033[0m";
  cat <<EOF

 USAGE:  OGRI.sh  [OPTIONS]  <fasta1>  <fasta2>  [<fasta3> ...]

 OPTIONS:
  -x          only OGRIs based on genome fragments (ANI, cDNA, oANI)
  -y          only OGRIs based on CDS (POCP, gANI, AF, AAI, ProCov, rAAI)
  -z          only OGRIs based on reciprocal searches (oANI, gANI, AF, ProCov, rAAI)
  -b <int>    number of bootstrap replicates for confidence intervals (default: 200)
  -r          tab-delimited raw output (default: detailed output)
  -t <int>    number of threads (default: 3)
  -h          prints this help and exits

EOF
}
#                                                                                                            #
##############################################################################################################

##############################################################################################################
#                                                                                                            #
# ================                                                                                           #
# = REQUIREMENTS =                                                                                           #
# ================                                                                                           #
#                                                                                                            #
# - SUMMARY -                                                                                                #
#   gawk/5.0.1 prodigal/2.6.3.pp1 blast+/2.14.1
#                                                                                                            #
# -- gawk -------------------------------------------------------------------------------------------------  #
#                                                                                                            #
  GAWK_BIN=gawk;
  [ ! $(command -v $GAWK_BIN) ] && echoxit "no $GAWK_BIN detected" ;
  GAWK_STATIC_OPTIONS="";     
  GAWK="$GAWK_BIN $GAWK_STATIC_OPTIONS";
  TAWK="$GAWK -F\\t";
#                                                                                                            #
# -- Prodigal ---------------------------------------------------------------------------------------------  #
#                                                                                                            #
  PRODIGAL_BIN=prodigal;
  [ ! $(command -v $PRODIGAL_BIN) ] && echoxit "no $PRODIGAL_BIN detected" ;
  PRODIGAL_STATIC_OPTIONS="-o /dev/null -q";     
  PRODIGAL="$PRODIGAL_BIN $PRODIGAL_STATIC_OPTIONS";
#                                                                                                            #
# -- NCBI BLAST+ (version >= 2.13.0) ----------------------------------------------------------------------  #
#
# -- makeblastdb                                                                                             #
#                                                                                                            #
  MKBDB_BIN=makeblastdb;
  [ ! $(command -v $MKBDB_BIN) ] && echoxit "no $MKBDB_BIN detected" ;
  version="$($MKBDB_BIN -version | $GAWK '(NR==2){print$3}' | $GAWK -F"." '($1>=2&&$2>=12)')";
  [ -z "$version" ] && echoxit "incorrect version: $MKBDB_BIN" ;
  MKBDB_STATIC_OPTIONS="-input_type fasta";     
  MKBDB="$MKBDB_BIN $MKBDB_STATIC_OPTIONS";
  MKBNDB="$MKBDB -dbtype nucl";
  NEXT="ndb nhr nin njs not nsq ntf nto"; # blastdb file extensions
  MKBPDB="$MKBDB -dbtype prot";
  PEXT="pdb phr pin pjs pot psq ptf pto"; # blastdb file extensions
#                                                                                                            #
# -- BLAST                                                                                                   #
#                                                                                                            #
  BLAST_STATIC_OPTIONS="-evalue 1e-5 -soft_masking false -max_target_seqs 1 -subject_besthit -max_hsps 1";
#                                                                                                            #
# -- blastn                                                                                                  #
#                                                                                                            #
  BLASTN_BIN=blastn;
  [ ! $(command -v $BLASTN_BIN) ] && echoxit "no $BLASTN_BIN detected" ;
  version="$($BLASTN_BIN -version | $GAWK '(NR==2){print$3}' | $GAWK -F"." '($1>=2&&$2>=12)')";
  [ -z "$version" ] && echoxit "incorrect version: $BLASTN_BIN" ;
  BLASTN_STATIC_OPTIONS="-task blastn -perc_identity 30 -dust no";
  BLASTN="$BLASTN_BIN $BLAST_STATIC_OPTIONS $BLASTN_STATIC_OPTIONS";
#                                                                                                            #
# -- blastp                                                                                                  #
#                                                                                                            #
  BLASTP_BIN=blastp;
  [ ! $(command -v $BLASTP_BIN) ] && echoxit "no $BLASTP_BIN detected" ;
  version="$($BLASTP_BIN -version | $GAWK '(NR==2){print$3}' | $GAWK -F"." '($1>=2&&$2>=12)')";
  [ -z "$version" ] && echoxit "incorrect version: $BLASTP_BIN" ;
  BLASTP_STATIC_OPTIONS="-seg no";     
  BLASTP="$BLASTP_BIN $BLAST_STATIC_OPTIONS $BLASTP_STATIC_OPTIONS";
#                                                                                                            #
# -- tblastn                                                                                                 #
#                                                                                                            #
  TBLASTN_BIN=tblastn;
  [ ! $(command -v $TBLASTN_BIN) ] && echoxit "no $TBLASTN_BIN detected" ;
  version="$($TBLASTN_BIN -version | $GAWK '(NR==2){print$3}' | $GAWK -F"." '($1>=2&&$2>=12)')";
  [ -z "$version" ] && echoxit "incorrect version: $TBLASTN_BIN" ;
  TBLASTN_STATIC_OPTIONS="-seg no";     
  TBLASTN="$TBLASTN_BIN $BLAST_STATIC_OPTIONS $TBLASTN_STATIC_OPTIONS";
#                                                                                                            #
##############################################################################################################

##############################################################################################################
####                                                                                                      ####
#### INITIALIZING PARAMETERS AND READING OPTIONS                                                          ####
####                                                                                                      ####
##############################################################################################################

if [ $# -lt 1 ]; then mandoc ; exit 1 ; fi

export BLAST_USAGE_REPORT=false;
export LC_ALL=C ;

BREP=200;        # -b
NTHREADS=3;      # -t
ORAW=false;      # -r
ALL_OGRIS=true;
ONLY_FRAG=false; # -x
ONLY_CDS=false;  # -y
ONLY_RBH=false;  # -z

while getopts t:b:rxyzh option
do
  case $option in
  b)  BREP=$OPTARG                                                     ;;
  t)  NTHREADS=$OPTARG                                                 ;;
  r)  ORAW=true                                                        ;;
  x)  ALL_OGRIS=false; ONLY_FRAG=true;  ONLY_CDS=false; ONLY_RBH=false ;;
  y)  ALL_OGRIS=false; ONLY_FRAG=false; ONLY_CDS=true;  ONLY_RBH=false ;;
  z)  ALL_OGRIS=false; ONLY_FRAG=false; ONLY_CDS=false; ONLY_RBH=true  ;;
  h)  mandoc ;                                                 exit 0  ;;
  :)  mandoc ;                                                 exit 1  ;;
  \?) mandoc ;                                                 exit 1  ;;
  esac
done

shift "$(( $OPTIND - 1 ))"

FASTA1=$1 ;
[ ! -e $FASTA1 ] && echoxit "file not found: $FASTA1" ;
[   -d $FASTA1 ] && echoxit "not a file: $FASTA1" ;
[ ! -s $FASTA1 ] && echoxit "empty file: $FASTA1" ;
[ ! -r $FASTA1 ] && echoxit "no read permission: $FASTA1" ;

N=$(ls $@ | wc -l);

shift 1 ;

[ $NTHREADS -lt 1 ] && NTHREADS=1;
if [ $NTHREADS -gt 1 ]
then
  BLASTN="$BLASTN   -num_threads $NTHREADS -mt_mode 1";
  BLASTP="$BLASTP   -num_threads $NTHREADS -mt_mode 1";
  TBLASTN="$TBLASTN -num_threads $NTHREADS -mt_mode 1";
fi

##############################################################################################################
####                                                                                                      ####
#### PROCESSING FASTA1                                                                                    ####  
####                                                                                                      ####
##############################################################################################################

ITER=1;                                                                                                                                               echo -n "[$ITER/$N]    [0%]" >&2 ;

SCFD1=$(randfile $FASTA1.scfd);                                                                                                                       echo -n "-" >&2 ;
FRAG1=$(randfile $FASTA1.frag);                                                                                                                       echo -n "-" >&2 ;
CDSN1=$(randfile $FASTA1.cdsn);                                                                                                                       echo -n "-" >&2 ;
CDSA1=$(randfile $FASTA1.cdsa);                                                                                                                       echo -n "-" >&2 ;
OUT1=$(randfile $FASTA1.out);                                                                                                                         echo -n "-" >&2 ;
TMP1=$(randfile $FASTA1.tmp);                                                                                                                         echo -n "-" >&2 ;
FERR=$(randfile $FASTA1.err);                                                                                                                         echo -n "-" >&2 ;

## copying FASTA1 ############################################################################################
cp $FASTA1 $SCFD1 ;

## defining traps ############################################################################################
finalizer() {                                                                                                                                         echo -n " ." >&2 ;
  rm -f $OUT1 $TMP1 $FERR  $SCFD1    $FRAG1    $CDSN1    $CDSA1    ;                                                                                  echo -n "." >&2 ;
  for e in $NEXT; do rm -f $SCFD1.$e $FRAG1.$e $CDSN1.$e           ; done                                                                             ; echo -n "." >&2 ;
  for e in $PEXT; do rm -f                               $CDSA1.$e ; done                                                                             ; echo -n " exiting" >&2 ;
}
trap 'finalizer;exit 1'  SIGTERM SIGINT SIGQUIT SIGHUP TERM INT QUIT HUP ;                                                                            echo -n "--" >&2 ;

## genome length #############################################################################################
lgt1=$(grep -v "^>" $SCFD1 | tr -cd 'acgtACGT' | wc -c);                                                                                              echo -n "-+" >&2 ;
[ $lgt1 -lt $MINLGT ] && echoxit "GENO1 too short ($lgt1 bps): $FASTA1" ;

## predicting CDS ############################################################################################
$ALL_OGRIS || $ONLY_CDS || $ONLY_RBH & $PRODIGAL -i $SCFD1 -d $CDSN1 &>/dev/null &
                                                                                                                                                      echo -n "----------+" >&2 ;
## formatting input sequences ################################################################################
$MKBNDB -in $SCFD1 &>/dev/null &
                                                                                                                                                      echo -n "----------+" >&2 ;
## cutting sequences into consecutive 1020 bp-long fragments #################################################
if $ALL_OGRIS || $ONLY_FRAG || $ONLY_RBH
then
  $GAWK '/^>/{print"";next}{printf$0}END{print""}' $SCFD1 |
    tr '[a-z]' '[A-Z]' |
      tr -c 'ACGT' '\n' |
        fold -w 1020 | 
          $GAWK 'BEGIN{x=1000000}(length()>920){print">"(++x);print}' > $FRAG1 ;
  nfra1=$(grep -c "^>" $FRAG1);                                           ### nfra1: no. fragments from FASTA1

  ## formatting 1020 bp-long fragments #######################################################################
  $MKBNDB -in $FRAG1 &>/dev/null &
fi
                                                                                                                                                      echo -n "----------" >&2 ;
wait &>/dev/null ; # waiting for PRODIGAL (if any) and at most 2 MKBNDB
                                                                                                                                                      echo -n "+" >&2 ;
## processing CDS ############################################################################################
if $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH 
then
  $GAWK '/^>/{print"";next}{printf$0}END{print""}' $CDSN1 |
    tr '[a-z]' '[A-Z]' |
      grep -v -E "R|Y|S|W|K|M|B|D|H|V|N|X|-" |
          $GAWK 'BEGIN{x=1000000}(length()%3==0 && length()>=99){print">"(++x);print$0}' > $TMP1 ;
  mv $TMP1 $CDSN1 ; touch $TMP1 ;                                                                                                                     echo -n "---" >&2 ;

  ## formatting nucleotide CDS sequences #####################################################################
  $MKBNDB -in $CDSN1 &>/dev/null & 
                                                                                                                                                      echo -n "---" >&2 ;
  grep -v "^>" $CDSN1 |
    sed -n -e 's/\(...\)/\1 /gp' |
      sed 's/GC. /A/g;
           s/AG[AG] /R/g;
           s/CG. /R/g;
           s/AA[CT] /N/g;
           s/GA[CT] /D/g;
           s/TG[CT] /C/g;
           s/CA[AG] /Q/g;
           s/GA[AG] /E/g;
           s/GG. /G/g;
           s/CA[CT] /H/g;
           s/AT[ACT] /I/g;
           s/CT. /L/g;
           s/TT[AG] /L/g;
           s/AA[AG] /K/g;
           s/ATG /M/g;
           s/TT[CT] /F/g;
           s/CC. /P/g;
           s/TC. /S/g;
           s/AG[CT] /S/g;
           s/AC. /T/g;
           s/TGG /W/g;
           s/TA[CT] /Y/g;
           s/GT. /V/g;
           s/TA[AG] /*/g;
           s/TGA /*/g;
           s/... /X/g' | tr -d 'X*' | $GAWK 'BEGIN{x=1000000}{print">"(++x);print$0}' > $TMP1 ;
  mv $TMP1 $CDSA1 ; touch $TMP1 ;                                                                                                                     echo -n "---" >&2 ;

  ncds1=$(grep -c "^>" $CDSA1);                                       ### ncds1: no. predicted CDS from FASTA1

  ## formatting amino acid CDS sequences #####################################################################
  $MKBPDB -in $CDSA1 &>/dev/null &
                                                                                                                                                      else echo -n "---------" >&2 ;
fi
                                                                                                                                                      echo -n "-" >&2 ;
wait &>/dev/null ; # waiting for 1 MKBNDB and 1 MKBPDB (if any)
                                                                                                                                                      echo "[100%]" >&2 ;

##############################################################################################################
####                                                                                                      ####
#### COMPUTING OGRIs AGAINST EVERY SPECIFIED FILES                                                        ####  
####                                                                                                      ####
##############################################################################################################
if $ORAW
then
  echo -n -e "#GENO1\tGENO2\tlgt1\tlgt2" ;
  $ALL_OGRIS || $ONLY_FRAG              && echo -n -e "\tnFRA1\tnFRA2\tnFRA12\tnFRA21\tcDNA12\tcDNA21\tANI12 [CI_ANI12]\tANI21 [CI_ANI21]\tANI [CI_ANI]" ;
  $ALL_OGRIS || $ONLY_FRAG || $ONLY_RBH && echo -n -e "\tnfRBH\toANI [CI_oANI]" ;
  $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\tnCDS1\tnCDS2" ;
  $ALL_OGRIS || $ONLY_CDS               && echo -n -e "\tnCDS12\tnCDS21\tPOCP" ;
  $ALL_OGRIS || $ONLY_CDS               && echo -n -e "\tcCDS12\tcCDS21\tcANI12 [CI_cANI12]\tcANI21 [CI_cANI21]\tcANI [CI_cANI]" ;
  $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\tngRBH\tgANI12 [CI_gANI12]\tgANI21 [CI_gANI21]\tgANI [CI_gANI]" ;
  $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\tAF12 [CI_AF12]\tAF21 [CI_AF21]\tAF [AF_CI]" ;
  $ALL_OGRIS || $ONLY_CDS               && echo -n -e "\tmCDS12\tmCDS21\tAAI12 [CI_AAI12]\tAAI21 [CI_AAI21]\tAAI [CI_AAI]" ;
  $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\tnaRBH\tProCov\trAAI [CI_rAAI]" ;
  echo ;
fi

for FASTA2 in $(ls $@)
do
  if [ ! -e $FASTA2 ];           then echo "file not found: $FASTA2"     >&2 ; continue; fi 
  if [   -d $FASTA2 ];           then echo "not a file: $FASTA2"         >&2 ; continue; fi 
  if [ ! -s $FASTA2 ];           then echo "empty file: $FASTA2"         >&2 ; continue; fi 
  if [ ! -r $FASTA2 ];           then echo "no read permission: $FASTA2" >&2 ; continue; fi
  if [ "$FASTA2" == "$FASTA1" ]; then echo "same as query: $FASTA2"      >&2 ; continue; fi

  let ITER++;                                                                                                                                         echo -n "[$ITER/$N] " >&2 ;
  
  SCFD2=$(randfile $FASTA2.scfd);                                                                                                                     [ $ITER -lt 10 ]   && echo -n " " >&2 ;
  FRAG2=$(randfile $FASTA2.frag);                                                                                                                     [ $ITER -lt 100 ]  && echo -n " " >&2 ;
  CDSN2=$(randfile $FASTA2.cdsn);                                                                                                                     [ $ITER -lt 1000 ] && echo -n " " >&2 ;
  CDSA2=$(randfile $FASTA2.cdsa);                                                                                                                     echo -n "[0%]-" >&2 ;
  OUT2=$(randfile $FASTA2.out);
  TMP2=$(randfile $FASTA2.tmp);

  ## copying FASTA1 ##########################################################################################
  cp $FASTA2 $SCFD2 ;

  ## defining traps ##########################################################################################
  finalizer() {                                                                                                                                       echo -n " ." >&2 ;
    rm -f $OUT1 $TMP1 $OUT2 $TMP2 $FERR $SCFD1    $FRAG1    $CDSN1    $CDSA1    $SCFD2    $FRAG2    $CDSN2    $CDSA2    ;                             echo -n "." >&2 ;
    for e in $NEXT; do rm -f            $SCFD1.$e $FRAG1.$e $CDSN1.$e           $SCFD2.$e $FRAG2.$e $CDSN2.$e           ; done                        ; echo -n "." >&2 ;
    for e in $PEXT; do rm -f                                          $CDSA1.$e                               $CDSA2.$e ; done                        ; echo -n " exiting" >&2 ;  
  }
  trap 'finalizer;exit 1'  SIGTERM SIGINT SIGQUIT SIGHUP TERM INT QUIT HUP ;
  
  ############################################################################################################
  ####                                                                                                    ####
  #### PROCESSING FASTA2                                                                                  ####
  ####                                                                                                    ####
  ############################################################################################################

  ## genome length ###########################################################################################
  lgt2=$(grep -v "^>" $SCFD2 | tr -cd 'acgtACGT' | wc -c);                                                                                            echo -n "--" >&2 ;
  if [ $lgt2 -lt $MINLGT ]; then echo "GENO2 too short ($lgt2 bps): $FASTA2" >&2 ; continue; fi 

  ## predicting CDS ##########################################################################################
  $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH && nice $PRODIGAL -i $SCFD2 -d $CDSN2 &>/dev/null &
                                                                                                                                                      echo -n "--" >&2 ;
  ## formatting input sequences ##############################################################################
  $MKBNDB -in $SCFD2 &>/dev/null ;
                                                                                                                                                      echo -n "--" >&2 ;
  ## cutting sequences into consecutive 1020 bp-long fragments ###############################################
  if $ALL_OGRIS || $ONLY_FRAG || $ONLY_RBH
  then
    $GAWK '/^>/{print"";next}{printf$0}END{print""}' $SCFD2 |
      tr '[a-z]' '[A-Z]' |
        tr -c 'ACGT' '\n' |
        fold -w 1020 |  
          $GAWK 'BEGIN{x=2000000}(length()>920){print">"(++x);print}' > $FRAG2 ;

    nfra2=$(grep -c "^>" $FRAG2);                                         ### nfra2: no. fragments from FASTA2

    ## formatting 1020 bp-long fragments #####################################################################
    $MKBNDB -in $FRAG2 &>/dev/null ;
  fi
                                                                                                                                                      echo -n "---+" >&2 ;

  ############################################################################################################
  ####                                                                                                    ####
  #### SETTING BLASTN PARAMETERS                                                                          ####
  ####                                                                                                    ####
  ############################################################################################################

  ## old-fashioned blastn (blastall) parameters ##############################################################
  #  https://www.ncbi.nlm.nih.gov/Class/BLAST/blastallopts.txt
  #  http://etutorials.org/Misc/blast/Part+V+BLAST+Reference/Chapter+13.+NCBI-BLAST+Reference/13.3+blastall+Parameters/)
  #  blastall    -r 1       -q -3       -G 5         -E 2         -W 11           -y 20         -X 30                -Z 100
  #  BNOPT="-reward 1 -penalty -3 -gapopen 5 -gapextend 2 -word_size 11 -xdrop_ungap 20 -xdrop_gap 30  -xdrop_gap_final 100"

  ## tuned blastn parameters #################################################################################
  #  Goris et al. 2007              https://doi.org/10.1099/ijs.0.64483-0
  #  Konstantinidis and Tiedje 2005 https://dx.doi.org/10.1073/pnas.0409727102
  #  Lee et al. 2017                https://dx.doi.org/10.1007/s10482-017-0844-4
  BNOPT="   -reward 1 -penalty -1 -gapopen 5 -gapextend 2 -word_size 11 -xdrop_ungap 20 -xdrop_gap 150 -xdrop_gap_final 100"

  
  ############################################################################################################
  ####                                                                                                    ####
  #### COMPUTING ANI (Goris et al. 2007 https://doi.org/10.1099/ijs.0.64483-0)                            ####
  ####                                                                                                    ####
  ############################################################################################################
  if $ALL_OGRIS || $ONLY_FRAG
  then
    ## blastn similarity search of fragments against initial sequences #######################################
    #                                               output fields: 1----- 2--- 3----- 4--- 5----- 6-----
    $BLASTN -query $FRAG1 -db $SCFD2 $BNOPT -out $TMP1 -outfmt '6 qseqid qlen qstart qend nident pident' 2>$FERR ;                                    echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    $BLASTN -query $FRAG2 -db $SCFD1 $BNOPT -out $TMP2 -outfmt '6 qseqid qlen qstart qend nident pident' 2>$FERR ;                                    echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }

    ## computing cDNA (Goris et al. 2007) ####################################################################
    cdna12=$($TAWK -v l=$lgt1 '($1!=q&&$6>=90){q=$1;s+=($4-$3+1)}END{printf("%.2f", 100*s/l)}' $TMP1);
    cdna21=$($TAWK -v l=$lgt2 '($1!=q&&$6>=90){q=$1;s+=($4-$3+1)}END{printf("%.2f", 100*s/l)}' $TMP2);

    ## filtering out BLAST hits according to Goris et al. (2007) #############################################
    #  + nident/qlen < 0.3
    #  + local alignment < 70% query length
    $TAWK '($1==q || ($5/$2)<0.3 || ((l=($4-$3+1))/$2)<0.7){next} {q=$1;print $5/l}' $TMP1 > $OUT1 ;                                                  echo -n "-" >&2 ;
    $TAWK '($1==q || ($5/$2)<0.3 || ((l=($4-$3+1))/$2)<0.7){next} {q=$1;print $5/l}' $TMP2 > $OUT2 ;

    ## computing OGRIs #######################################################################################
    nfra12=$(cat $OUT1 | wc -l);                                         ### nfra12: no. FRAG1 matching FASTA2
    nfra21=$(cat $OUT2 | wc -l);                                         ### nfra21: no. FRAG2 matching FASTA1
    ani12=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $OUT1);          ### ani12:  ANI from FASTA1 to FASTA2
    ani21=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $OUT2);          ### ani21:  ANI from FASTA2 to FASTA1
    ani=$(bc -l <<<"scale=2;($ani12+$ani21)/2");                         ### ani:       avg of ani12 and ani21
                                                                                                                                                      echo -n "-" >&2 ;
    ## computing bootstrap-based confidence intervals ########################################################
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                             s=x=0;
                             while(++x<=n)s+=a[1+int(n*rand())];
                             d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $OUT1 > $TMP1 ;                                                 echo -n "-" >&2 ;
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                            s=x=0;
                            while(++x<=n)s+=a[1+int(n*rand())];
                            d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $OUT2 > $TMP2 ;
    ci1l=$($TAWK '{print$1;exit}' $TMP1);      ci1r=$($TAWK '{print$2;exit}' $TMP1); 
    ci2l=$($TAWK '{print$1;exit}' $TMP2);      ci2r=$($TAWK '{print$2;exit}' $TMP2); 
    cil=$(bc -l <<<"scale=2;($ci1l+$ci2l)/2"); cir=$(bc -l <<<"scale=2;($ci1r+$ci2r)/2");
    ci_ani12="[$ci1l-$ci1r]"; ci_ani21="[$ci2l-$ci2r]"; ci_ani="[$cil-$cir]";                                                                         else echo -n "-----" >&2 ;
  fi

  
  ############################################################################################################
  ####                                                                                                    ####
  #### COMPUTING OrthoANI (Lee et al. 2016 https://dx.doi.org/10.1007/s10482-017-0844-4)                  ####
  ####                                                                                                    ####
  ############################################################################################################
  if $ALL_OGRIS || $ONLY_FRAG || $ONLY_RBH
  then
    ## blastn similarity search between fragments ############################################################
    #                                              output fields: 1----- 2--- 3----- 4--- 5----- 6--- 7----- 8--- 9----- 10---- 11----
    $BLASTN -query $FRAG1 -db $FRAG2 $BNOPT -out $TMP1 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send nident length evalue' 2>$FERR ;     echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    $BLASTN -query $FRAG2 -db $FRAG1 $BNOPT -out $TMP2 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send nident length evalue' 2>$FERR ;     echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }

    ## filtering out BLAST hits according to Lee et al. (2016) ###############################################
    #  + qlen != 1020
    #  + slen != 1020
    #  + evalue > 1e-15
    #  + qend-qstart < 356
    #  + abs(send-sstart) < 356
    $TAWK 'function abs(x){return(x+=0)<0?-x:x}
           ($1==q || $2!=1020 || $6!=1020 || $11>1e-15 || ($4-$3)<356 || abs($8-$7)<356){next} {q=$1;print}' $TMP1 > $OUT1 ;                          echo -n "-" >&2 ;
    $TAWK 'function abs(x){return(x+=0)<0?-x:x}
           ($1==q || $2!=1020 || $6!=1020 || $11>1e-15 || ($4-$3)<356 || abs($8-$7)<356){next} {q=$1;print}' $TMP2 > $OUT2 ;                          echo -n "-" >&2 ;

    ## assessing reciprocal BLAST hits (RBH) #################################################################
    #  sorting OUT2 according to the decreasing order of the subject ids (field 5)
    sort -k5n,5 -k11g,11 -k10rn,10 -k9rg,9 $OUT2 > $TMP2 ;  mv $TMP2 $OUT2 ; touch $TMP2 ;
    # joining OUT1 and OUT2 to obtain RBHs (i.e. resulting fields $5 and $12 should be identical)
    join -t$'\t' -1 1 -2 5 $OUT1 $OUT2 | $TAWK '($5==$12)' | cut -f1-11 > $TMP1 ;                                                                     echo -n "-" >&2 ;

    ## computing OGRIs #######################################################################################
    $GAWK 'function abs(x){return(x+=0)<0?-x:x}
           {a=$9/($4-$3+1);b=$9/(abs($8-$7)+1);print((a+b)/2)}' $TMP1 > $TMP2 ;
    nfrbh=$(cat $TMP2 | wc -l);                                    ### nfrbh:  no. RBH between FRAG1 and FRAG2
    oani=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $TMP2);     ### oani: OrthoANI  between FRAG1 and FRAG2

    ## computing bootstrap-based confidence intervals ########################################################
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                             s=x=0;
                             while(++x<=n)s+=a[1+int(n*rand())];
                             d[r]=s/n}
                           asort(d);
                           printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $TMP2 > $TMP1 ;
    cil=$($TAWK '{print$1;exit}' $TMP1); cir=$($TAWK '{print$2;exit}' $TMP1); 
    ci_oani="[$cil-$cir]";                                                                                                                            echo -n "+" >&2 ; else echo -n "-----+" >&2 ;
  fi

  ############################################################################################################
  ####                                                                                                    ####
  #### PROCESSING CDS FROM FASTA2                                                                         ####
  ####                                                                                                    ####
  ############################################################################################################
  wait &>/dev/null ; # waiting for PRODIGAL (if any)
  
  if $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH
  then
    $GAWK '/^>/{print"";next}{printf$0}END{print""}' $CDSN2 |
      tr '[a-z]' '[A-Z]' |
        grep -v -E "R|Y|S|W|K|M|B|D|H|V|N|X|-" |
          $GAWK 'BEGIN{x=2000000}(length()%3==0 && length()>=99){print">"(++x);print$0}' > $TMP1 ;
    mv $TMP1 $CDSN2 ; touch $TMP1 ;

    ## formatting nucleotide CDS sequences ###################################################################
    $MKBNDB -in $CDSN2 &>/dev/null ;

    grep -v "^>" $CDSN2 |
      sed -n -e 's/\(...\)/\1 /gp' |
        sed 's/GC. /A/g;
             s/AG[AG] /R/g;
             s/CG. /R/g;
             s/AA[CT] /N/g;
             s/GA[CT] /D/g;
             s/TG[CT] /C/g;
             s/CA[AG] /Q/g;
             s/GA[AG] /E/g;
             s/GG. /G/g;
             s/CA[CT] /H/g;
             s/AT[ACT] /I/g;
             s/CT. /L/g;
             s/TT[AG] /L/g;
             s/AA[AG] /K/g;
             s/ATG /M/g;
             s/TT[CT] /F/g;
             s/CC. /P/g;
             s/TC. /S/g;
             s/AG[CT] /S/g;
             s/AC. /T/g;
             s/TGG /W/g;
             s/TA[CT] /Y/g;
             s/GT. /V/g;
             s/TA[AG] /*/g;
             s/TGA /*/g;
             s/... /X/g' | tr -d 'X*' | $GAWK 'BEGIN{x=2000000}{print">"(++x);print$0}' > $TMP1 ;
    mv $TMP1 $CDSA2 ; touch $TMP1 ;

    ncds2=$(grep -c "^>" $CDSA2);                                     ### ncds2: no. predicted CDS from FASTA2

    ## formatting amino acid CDS sequences ###################################################################
    $MKBPDB -in $CDSA2 &>/dev/null ;
  fi

  
  ############################################################################################################
  ####                                                                                                    ####
  #### COMPUTING cANI (Konstantinidis & Tiedje 2005 https://dx.doi.org/10.1073/pnas.0409727102)           ####
  ####                                                                                                    ####
  ############################################################################################################
  if $ALL_OGRIS || $ONLY_CDS
  then
    ## blastn similarity search between CDS ##################################################################
    #                                              output fields: 1----- 2--- 3----- 4--- 5----- 6--- 7----- 8--- 9----- 10---- 11----
    $BLASTN -query $CDSN1 -db $CDSN2 $BNOPT -out $TMP1 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send nident length evalue' 2>$FERR ;     echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    $BLASTN -query $CDSN2 -db $CDSN1 $BNOPT -out $TMP2 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send nident length evalue' 2>$FERR ;     echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }

    ## filtering out BLAST hits according to Konstantinidis & Tiedje (2005) ##################################
    #  + nident/qlen < 0.6
    #  + local alignment < 70% query length
    $TAWK 'function abs(x){return(x+=0)<0?-x:x}
           ($1==q || ($9/$2)<0.6 || ((l=($4-$3+1))/$2)<0.7){next} {q=$1;print $9/l}' $TMP1 > $OUT1 ;
    $TAWK 'function abs(x){return(x+=0)<0?-x:x}
           ($1==q || ($9/$2)<0.6 || ((l=($4-$3+1))/$2)<0.7){next} {q=$1;print $9/l}' $TMP2 > $OUT2 ;                                                  echo -n "-" >&2 ;

    ## computing OGRIs #######################################################################################
    ccds12=$(cat $OUT1 | wc -l);                                          ### ccds12: no. CDSN1 matching CDSN2
    ccds21=$(cat $OUT2 | wc -l);                                          ### ccds21: no. CDSN2 matching CDSN1
    cani12=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $OUT1);          ### cani12: cANI from CDSN1 to CDSN2
    cani21=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $OUT2);          ### cani21: cANI from CDSN2 to CDSN1
    cani=$(bc -l <<<"scale=2;($cani12+$cani21)/2");                       ### cani:   avg of cani12 and cani21

    ## computing bootstrap-based confidence intervals ########################################################
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                             s=x=0;
                             while(++x<=n)s+=a[1+int(n*rand())];
                             d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $OUT1 > $TMP1 ;                                                 echo -n "-" >&2 ;
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                            s=x=0;
                            while(++x<=n)s+=a[1+int(n*rand())];
                            d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $OUT2 > $TMP2 ;
    ci1l=$($TAWK '{print$1;exit}' $TMP1);      ci1r=$($TAWK '{print$2;exit}' $TMP1); 
    ci2l=$($TAWK '{print$1;exit}' $TMP2);      ci2r=$($TAWK '{print$2;exit}' $TMP2); 
    cil=$(bc -l <<<"scale=2;($ci1l+$ci2l)/2"); cir=$(bc -l <<<"scale=2;($ci1r+$ci2r)/2");
    ci_cani12="[$ci1l-$ci1r]"; ci_cani21="[$ci2l-$ci2r]"; ci_cani="[$cil-$cir]";                                                                      echo -n "-" >&2 ; else echo -n "-----" >&2 ;
  fi

  
  ############################################################################################################
  ####                                                                                                    ####
  #### COMPUTING gANI & AF (Varghese et al. 2015 https://dx.doi.org/10.1093/nar/gkv657)                   ####
  ####                                                                                                    ####
  ############################################################################################################
  if $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH
  then
    ## modern blastn parameters ##############################################################################
    #  https://www.ncbi.nlm.nih.gov/books/NBK279684/
    BNOPT="-reward 2 -penalty -3 -gapopen 5 -gapextend 2 -word_size 11 -xdrop_ungap 20 -xdrop_gap 30 -xdrop_gap_final 100";
							   
    ## blastn similarity search between CDS ##################################################################
    #                                              output fields: 1----- 2--- 3----- 4--- 5----- 6--- 7----- 8--- 9----- 10---- 11----
    $BLASTN -query $CDSN1 -db $CDSN2 $BNOPT -out $TMP1 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send pident length evalue' 2>$FERR ;     echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    $BLASTN -query $CDSN2 -db $CDSN1 $BNOPT -out $TMP2 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send pident length evalue' 2>$FERR ;     echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }

    ## filtering out BLAST hits according to Varghese et al. (2015) ##########################################
    #  + pident < 70%
    #  + local alignment < 70% shorter CDS length
    $TAWK 'function abs(x){return(x+=0)<0?-x:x}
           ($1==q || $9<70 || (($2<$6)?($4-$3+1)/$2:(abs($8-$7)+1)/$6)<0.7){next} {q=$1;print}' $TMP1 > $OUT1 ;
    $TAWK 'function abs(x){return(x+=0)<0?-x:x}
           ($1==q || $9<70 || (($2<$6)?($4-$3+1)/$2:(abs($8-$7)+1)/$6)<0.7){next} {q=$1;print}' $TMP2 > $OUT2 ;                                       echo -n "-" >&2 ;
    
    ## assessing reciprocal BLAST hits (RBH) #################################################################
    #  sorting OUT2 according to the decreasing order of the subject ids (field 5)
    sort -k5n,5 -k11g,11 -k10rn,10 -k9rg,9 $OUT2 > $TMP2 ;  mv $TMP2 $OUT2 ;  touch $TMP2 ;
    # joining OUT1 and OUT2 to obtain RBHs (i.e. resulting fields $5 and $12 should be identical)
    join -t$'\t' -1 1 -2 5 $OUT1 $OUT2 | $TAWK '($5==$12)' | cut -f1-11 > $TMP1 ;                                                                     echo -n "-" >&2 ;

    ## computing OGRIs #######################################################################################
    #  gANI = sum of pident*length, divided by the sum of the lengths of the RBH CDS
    #  AF = sum of the lengths of all RBH genes, divided by the sum of the lengths of all CDS
    ngrbh=$(cat $TMP1 | wc -l);                                   ### ngrbh:    no. RBH between CDSN1 to CDSN2
    gl1=$(grep -v ">" $CDSN1 | tr -d '\n' | wc -c);               ### gl1:         sum of the lengths of CDSN1
    gl2=$(grep -v ">" $CDSN2 | tr -d '\n' | wc -c);               ### gl2:         sum of the lengths of CDSN2
    $TAWK '{printf("%.3f\t%d\t%d\n", $9*$10, $2, $6)}' $TMP1 > $TMP2 ;
    sid=$($GAWK '{s+=$1}END{printf("%.3f",s)}' $TMP2);            ### sid:                sum of pident*length
    sl1=$($GAWK '{s+=$2}END{print s}' $TMP2);                     ### sl1: sum of the lengths of the RBH CDSN1
    sl2=$($GAWK '{s+=$3}END{print s}' $TMP2);                     ### sl2: sum of the lengths of the RBH CDSN2
    gani12=$(bc -l <<<"scale=2;$sid/$sl1");                       ### gani12:         gANI from CDSN1 to CDSN2
    gani21=$(bc -l <<<"scale=2;$sid/$sl2");                       ### gani21:         gANI from CDSN2 to CDSN1
    gani=$(bc -l <<<"scale=2;($gani12+$gani21)/2");               ### gani:           avg of gani12 and gani21
    af12=$(bc -l <<<"scale=3;$sl1/$gl1");
    af12=$(sed 's/^0$/0\.000/;s/^\./0\./' <<<"$af12");            ### af12:             AF from CDSN1 to CDSN2
    af21=$(bc -l <<<"scale=3;$sl2/$gl2");
    af21=$(sed 's/^0$/0\.000/;s/^\./0\./' <<<"$af21");            ### af21:             AF from CDSN2 to CDSN1
    af=$(bc -l <<<"scale=3;($af12+$af21)/2");
    af=$(sed 's/^0$/0\.000/;s/^\./0\./' <<<"$af");                ### af:                 avg of af12 and af21
                                                                                             
    ## computing bootstrap-based confidence intervals ########################################################
    $GAWK -v b=$BREP -v gl1=$gl1 -v gl2=$gl2 '   {il[(++n)]=$1;l1[n]=$2;l2[n]=$3}
                                              END{srand(n);
                                                  while(++r<=b){
                                                     sid=sl1=sl2=x=0;
                                                     while(++x<=n){
                                                        i=1+int(n*rand());sid+=il[i];sl1+=l1[i];sl2+=l2[i]}
                                                     dgani12[r]=sid/sl1;dgani21[r]=sid/sl2;
                                                     daf12[r]=sl1/gl1;daf21[r]=sl2/gl2;}
                                                  asort(dgani12);asort(dgani21);asort(daf12);asort(daf21);
                                                  printf("%.2f\t%.2f\n",dgani12[int(b/40)],dgani12[int(39*b/40)]);
                                                  printf("%.2f\t%.2f\n",dgani21[int(b/40)],dgani21[int(39*b/40)]);
                                                  printf("%.3f\t%.3f\n",daf12[int(b/40)],daf12[int(39*b/40)]);
                                                  printf("%.3f\t%.3f\n",daf21[int(b/40)],daf21[int(39*b/40)]);}' $TMP2 > $TMP1 ;                      echo -n "-" >&2 ;

    ci1l=$($TAWK '(NR==1){print$1;exit}' $TMP1);  ci1r=$($TAWK '(NR==1){print$2;exit}' $TMP1);
    ci2l=$($TAWK '(NR==2){print$1;exit}' $TMP1);  ci2r=$($TAWK '(NR==2){print$2;exit}' $TMP1); 
    cil=$(bc -l <<<"scale=2;($ci1l+$ci2l)/2");    cir=$(bc -l <<<"scale=2;($ci1r+$ci2r)/2");
    ci_gani12="[$ci1l-$ci1r]";  ci_gani21="[$ci2l-$ci2r]";  ci_gani="[$cil-$cir]";
    ci1l=$($TAWK '(NR==3){print$1;exit}' $TMP1);  ci1r=$($TAWK '(NR==3){print$2;exit}' $TMP1); 
    ci2l=$($TAWK '(NR==4){print$1;exit}' $TMP1);  ci2r=$($TAWK '(NR==4){print$2;exit}' $TMP1); 
    cil=$(bc -l <<<"scale=3;($ci1l+$ci2l)/2" | sed 's/^0$/0\.000/;s/^\./0\./');
    cir=$(bc -l <<<"scale=3;($ci1r+$ci2r)/2" | sed 's/^0$/0\.000/;s/^\./0\./');
    ci_af12="[$ci1l-$ci1r]";  ci_af21="[$ci2l-$ci2r]";  ci_af="[$cil-$cir]";                                                                          echo -n "+" >&2 ; else echo -n "-----+" >&2 ;
  fi

  
  ############################################################################################################
  ####                                                                                                    ####
  #### COMPUTING AAI (Konstantinidis & Tiedje 2005 https://doi.org/10.1128/JB.187.18.6258-6264.2005)      ####
  ####                                                                                                    ####
  ############################################################################################################
  if $ALL_OGRIS || $ONLY_CDS 
  then
    ## tblastn similarity search of CDS against initial sequences ############################################
    #                                         output fields: 1----- 2--- 3----- 4--- 5-----
    $TBLASTN -query $CDSA1 -db $SCFD2 -out $TMP1 -outfmt '6 qseqid qlen qstart qend nident' 2>$FERR ;                                                 echo -n "--" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    $TBLASTN -query $CDSA2 -db $SCFD1 -out $TMP2 -outfmt '6 qseqid qlen qstart qend nident' 2>$FERR ;                                                 echo -n "--" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }

    ## filtering out BLAST hits according to Konstantinidis & Tiedje (2005) ##################################
    #  + nident/qlen < 0.3
    #  + local alignment < 70% query length
    $TAWK '($1==q || ($5/$2)<0.3 || ((l=($4-$3+1))/$2)<0.7){next} {q=$1;print $5/l}' $TMP1 > $OUT1 ;                                                  echo -n "-" >&2 ;
    $TAWK '($1==q || ($5/$2)<0.3 || ((l=($4-$3+1))/$2)<0.7){next} {q=$1;print $5/l}' $TMP2 > $OUT2 ;                                                  echo -n "-" >&2 ;

    ## computing OGRIs #######################################################################################
    mcds12=$(cat $OUT1 | wc -l);                                 ### mcds12: no. CDSA1 matching against FASTA2
    mcds21=$(cat $OUT2 | wc -l);                                 ### mcds21: no. CDSA2 matching against FASTA1
    aai12=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $OUT1);  ### aai12:           AA1 from CDSA1 to FASTA2
    aai21=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $OUT2);  ### aai21:           ANI from CDSA2 to FASTA1
    aai=$(bc -l <<<"scale=2;($aai12+$aai21)/2");                 ### aai:               avg of ani12 and ani21
                                                                                                                                                      echo -n "-" >&2 ;
    ## computing bootstrap-based confidence intervals ########################################################
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                             s=x=0;
                             while(++x<=n)s+=a[1+int(n*rand())];
                             d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $OUT1 > $TMP1 ;                                                 echo -n "-" >&2 ;
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                             s=x=0;
                             while(++x<=n)s+=a[1+int(n*rand())];
                             d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $OUT2 > $TMP2 ;                                                 echo -n "-" >&2 ;

    ci1l=$($TAWK '{print$1;exit}' $TMP1);      ci1r=$($TAWK '{print$2;exit}' $TMP1);   
    ci2l=$($TAWK '{print$1;exit}' $TMP2);      ci2r=$($TAWK '{print$2;exit}' $TMP2); 
    cil=$(bc -l <<<"scale=2;($ci1l+$ci2l)/2"); cir=$(bc -l <<<"scale=2;($ci1r+$ci2r)/2");
    ci_aai12="[$ci1l-$ci1r]"; ci_aai21="[$ci2l-$ci2r]"; ci_aai="[$cil-$cir]";                                                                         echo -n "-+" >&2 ; else echo -n "----------+" >&2 ;
  fi

  
  ############################################################################################################
  ####                                                                                                    ####
  #### COMPUTING POCP (Qin et al. 2014 https://dx.doi.org/10.1128/JB.01688-14),                           ####
  ####   rAAI (Nicholson et al. 2020 https://dx.doi.org/10.1099/ijsem.0.003935), AND                      ####
  ####   ProCov (Kim et al. 2021 https://dx.doi.org/10.1007/s12275-021-1154-0)                            ####
  ####                                                                                                    ####
  ############################################################################################################
  if $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH
  then
    ## blastp similarity search between CDS ##################################################################
    #                                       output fields: 1----- 2--- 3----- 4--- 5----- 6--- 7----- 8--- 9----- 10---- 11----
    $BLASTP -query $CDSA1 -db $CDSA2 -out $TMP1 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send nident length evalue' 2>$FERR ;            echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    $BLASTP -query $CDSA2 -db $CDSA1 -out $TMP2 -outfmt '6 qseqid qlen qstart qend sseqid slen sstart send nident length evalue' 2>$FERR ;            echo -n "-" >&2 ;
    [ $? -ne 0 ] && { cat $FERR >&2 ; finalizer ; exit 1 ; }
    
    ## filtering out BLAST hits according to both Qin et al. (2014) and Kim et al. (2020) ####################
    #  + nident/length < 0.4
    #  + local alignment < 50% query length
    $TAWK '($1==q || ($9/$10)<0.4 || (($4-$3+1)/$2)<0.5){next} {q=$1;print}' $TMP1 > $OUT1 ;                                                          echo -n "-" >&2 ;
    $TAWK '($1==q || ($9/$10)<0.4 || (($4-$3+1)/$2)<0.5){next} {q=$1;print}' $TMP2 > $OUT2 ;                                                          echo -n "-" >&2 ;

    ## computing OGRIs #######################################################################################
    ncds12=$(cat $OUT1 | wc -l);                                      ### ncds12: no. CDSA1 matching against CDSA2
    ncds21=$(cat $OUT2 | wc -l);                                      ### ncds21: no. CDSA2 matching against CDSA1
    pocp=$(bc -l <<<"scale=2;100*($ncds12+$ncds21)/($ncds1+$ncds2)"); ### pocp:   POCP

    ## assessing reciprocal BLAST hits (RBH) #################################################################
    #  sorting OUT2 according to the decreasing order of the subject ids (field 5)
    sort -k5n,5 -k11g,11 -k10rn,10 -k9rg,9 $OUT2 > $TMP2 ;  mv $TMP2 $OUT2 ;  touch $TMP2 ;                                                           echo -n "-" >&2 ;
    # joining OUT1 and OUT2 to obtain RBHs (i.e. resulting fields $5 and $12 should be identical)
    join -t$'\t' -1 1 -2 5 $OUT1 $OUT2 | $TAWK '($5==$12)' | cut -f1-11 > $TMP1 ;                                                                     echo -n "-" >&2 ;

    ## computing OGRIs #######################################################################################
    $GAWK 'function abs(x){return(x+=0)<0?-x:x}
           {a=$9/($4-$3+1);b=$9/(abs($8-$7)+1);print((a+b)/2)}' $TMP1 > $TMP2 ;                                                                       echo -n "-" >&2 ;
    narbh=$(cat $TMP1 | wc -l);                                     ### narbh: no. RBH between CDSA1 and CDSA2
    raai=$($GAWK '{s+=$1}END{printf("%.2f",100*s/NR)}' $TMP2);      ### raai:     rAAI between CDSA1 and CDSA2
    procov=$(bc -l <<<"scale=3;2*$narbh/($ncds1+$ncds2)");          ### procov:              Proteome coverage
    procov=$(sed 's/^0$/0\.000/;s/^\./0\./' <<<"$procov");                                                                                            echo -n "-" >&2 ;

    ## computing bootstrap-based confidence intervals ########################################################
    $GAWK -v b=$BREP '   {a[(++n)]=$1}
                      END{srand(n);
                          while(++r<=b){
                             s=x=0;
                             while(++x<=n)s+=a[1+int(n*rand())];
                             d[r]=s/n}
                          asort(d);
                          printf("%.2f\t%.2f",100*d[int(b/40)],100*d[int(39*b/40)])}' $TMP2 > $TMP1 ;                                                 echo -n "-" >&2 ;

    cil=$($TAWK '{print$1;exit}' $TMP1); cir=$($TAWK '{print$2;exit}' $TMP1); 
    ci_raai="[$cil-$cir]";                                                                                                                            echo -n "-" >&2 ; else echo -n "----------" >&2 ;
  fi

  ## removing temporary files #####################################################
  rm -f $OUT2 $TMP2        $SCFD2    $FRAG2    $CDSN2    $CDSA2    ;
  for e in $NEXT; do rm -f $SCFD2.$e $FRAG2.$e $CDSN2.$e           ; done
  for e in $PEXT; do rm -f                               $CDSA2.$e ; done
                                                                                                                                                      echo "[100%]" >&2 ;

  ##############################################################################################################
  ####                                                                                                      ####
  #### DISPLAYNG RESULTS                                                                                    ####
  ####                                                                                                      ####
  ##############################################################################################################
  if ! $ORAW
  then
    echo ;
    echo " Genome files" ;
    echo "   GENO1             $FASTA1" ;
    echo "   GENO2             $FASTA2" ;
    echo ;
    if $ALL_OGRIS || $ONLY_FRAG
    then
      echo " Average Nucleotide Identity (Goris et al. 2007)" ;
      echo "   nFRA1  (nFRA12)   $nfra1 ($nfra12)" ;
      echo "   nFRA2  (nFRA21)   $nfra2 ($nfra21)" ;
      echo "   cDNA12 (lgt1)     $cdna12 ($lgt1)" ;
      echo "   cDNA21 (lgt2)     $cdna21 ($lgt2)" ;
      echo "   ANI12  [95%CI]    $ani12 $ci_ani12" ;
      echo "   ANI21  [95%CI]    $ani21 $ci_ani21" ;
      echo "   ANI    [95%CI]    $ani $ci_ani" ;
      echo ;
    fi
    if $ALL_OGRIS || $ONLY_FRAG || $ONLY_RBH
    then
      echo " OrthoANI (Lee et al. 2016)" ;
      echo "   nfRBH             $nfrbh" ;
      echo "   oANI   [95%CI]    $oani $ci_oani" ;
      echo ;
    fi
    if $ALL_OGRIS || $ONLY_CDS
    then
      echo " Percentage Of Conserved Proteins (Qin et al. 2014)" ;
      echo "   nCDS1  (nCDS12)   $ncds1 ($ncds12)" ;
      echo "   nCDS2  (nCDS21)   $ncds2 ($ncds21)" ;
      echo "   POCP              $pocp" ;
      echo ;
      echo " CDS-based ANI (Konstantinidis & Tiedje 2005)" ;
      echo "   nCDS1  (cCDS12)   $ncds1 ($ccds12)" ;
      echo "   nCDS2  (cCDS21)   $ncds2 ($ccds21)" ;
      echo "   cANI12 [95%CI]    $cani12 $ci_cani12" ;
      echo "   cANI21 [95%CI]    $cani21 $ci_cani21" ;
      echo "   cANI   [95%CI]    $cani $ci_cani" ;
      echo ;
    fi
    if $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH
    then
      echo " Whole-genome based ANI & Alignment Fraction (Varghese et al. 2015)" ;
      echo "   ngRBH             $ngrbh" ;
      echo "   gANI12 [95%CI]    $gani12 $ci_gani12" ;
      echo "   gANI21 [95%CI]    $gani21 $ci_gani21" ;
      echo "   gANI   [95%CI]    $gani $ci_gani" ;
      echo "   AF12   [95%CI]    $af12 $ci_af12" ;
      echo "   AF21   [95%CI]    $af21 $ci_af21" ;
      echo "   AF     [95%CI]    $af $ci_af" ;
      echo ;
    fi
    if $ALL_OGRIS || $ONLY_CDS
    then
      echo " Average Amino-acid Identity (one-way; Konstantinidis & Tiedje 2005)" ;
      echo "   nCDS1  (mCDS12)   $ncds1 ($mcds12)" ;
      echo "   nCDS2  (mCDS21)   $ncds2 ($mcds21)" ;
      echo "   AAI12  [95%CI]    $aai12 $ci_aai12" ;
      echo "   AAI21  [95%CI]    $aai21 $ci_aai21" ;
      echo "   AAI    [95%CI]    $aai $ci_aai" ;
      echo ;
    fi
    if $ALL_OGRIS || $ONLY_CDS || $ONLY_RBH
    then
      echo " Proteome Coverage (Kim et al. 2021) & rAAI (Nicholson et al. 2020)" ;
      echo "   naRBH             $narbh" ;
      echo "   ProCov            $procov" ;
      echo "   rAAI   [95%CI]    $raai $ci_raai" ;
      echo ;
    fi
  else
    echo -n -e "$FASTA1\t$FASTA2\t$lgt1\t$lgt2" ;
    $ALL_OGRIS || $ONLY_FRAG              && echo -n -e "\t$nfra1\t$nfra2\t$nfra12\t$nfra21\t$cdna12\t$cdna21\t$ani12 $ci_ani12\t$ani21 $ci_ani21\t$ani $ci_ani" ;
    $ALL_OGRIS || $ONLY_FRAG || $ONLY_RBH && echo -n -e "\t$nfrbh\t$oani $ci_oani" ;
    $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\t$ncds1\t$ncds2" ;
    $ALL_OGRIS || $ONLY_CDS               && echo -n -e "\t$ncds12\t$ncds21\t$pocp" ;
    $ALL_OGRIS || $ONLY_CDS               && echo -n -e "\t$ccds12\t$ccds21\t$cani12 $ci_cani12\t$cani21 $ci_cani21\t$cani $ci_cani" ;
    $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\t$ngrbh\t$gani12 $ci_gani12\t$gani21 $ci_gani21\t$gani $ci_gani" ;
    $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\t$af12 $ci_af12\t$af21 $ci_af21\t$af $ci_af" ;
    $ALL_OGRIS || $ONLY_CDS               && echo -n -e "\t$mcds12\t$mcds21\t$aai12 $ci_aai12\t$aai21 $ci_aai21\t$aai $ci_aai" ;
    $ALL_OGRIS || $ONLY_CDS  || $ONLY_RBH && echo -n -e "\t$narbh\t$procov\t$raai $ci_raai" ;
    echo ;
  fi

done

## removing temporary files #####################################################
rm -f $OUT1 $TMP1 $FERR  $SCFD1    $FRAG1    $CDSN1    $CDSA1    ;
for e in $NEXT; do rm -f $SCFD1.$e $FRAG1.$e $CDSN1.$e           ; done
for e in $PEXT; do rm -f                               $CDSA1.$e ; done

exit ;
