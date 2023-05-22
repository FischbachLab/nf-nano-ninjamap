#!/bin/bash -x

set -e
set -u
set -o pipefail

START_TIME=$SECONDS
export PATH="/opt/conda/bin:${PATH}"

LOCAL=$(pwd)
coreNum=${coreNum:-16}

# s3 inputs from env variables
#fastq1="${1}"
#fastq2="${2}"
#longreads="${3}" input long reads in fastq format
#S3OUTPUTPATH="${4}"
#ref="${}" reference


# Setup directory structure
OUTPUTDIR=${LOCAL}/tmp_$( date +"%Y%m%d_%H%M%S" )
RAW_FASTQ="${OUTPUTDIR}/raw_fastq"

LOCAL_OUTPUT="${OUTPUTDIR}/Sync"
QC_FASTQ="${LOCAL_OUTPUT}/filtered_short_reads"

LOG_DIR="${LOCAL_OUTPUT}/Logs"
FASTQC_OUTPUT="${LOCAL_OUTPUT}/fastqc_illumina"
FASTQC_OUTPUT2="${LOCAL_OUTPUT}/fastqc_nanopore"
#FASTQ_NAME=${fastq1%/*}
#SAMPLE_NAME=$(basename ${S3OUTPUTPATH})
SAMPLE_NAME="${sample}"

BAM_OUTPUT_LONG="${LOCAL_OUTPUT}/syn_reads_vs_ref_bam"
SYN_READS="${LOCAL_OUTPUT}/syn_reads"

mkdir -p "${OUTPUTDIR}" "${LOCAL_OUTPUT}" "${LOG_DIR}" "${RAW_FASTQ}" "${QC_FASTQ}" "${SYN_READS}"
mkdir -p "${FASTQC_OUTPUT}" "${FASTQC_OUTPUT2}" "${BAM_OUTPUT_LONG}"

trap '{ rm -rf ${OUTPUTDIR} ; exit 255; }' 1

hash_kmer=${hash_kmer:-51}

# Copy fastq.gz files from S3, only 2 files per sample
aws s3 cp --quiet ${fastq1} "${RAW_FASTQ}/read1.fastq.gz"
aws s3 cp --quiet ${fastq2} "${RAW_FASTQ}/read2.fastq.gz"
aws s3 cp --quiet ${longreads} "${RAW_FASTQ}/long.fastq.gz"
#cp ${trimmedlongreads} "${QC_FASTQ}/long_fastp.fastq.gz"
cp ${trimmedlongreads} "${QC_FASTQ}/long_trimmed.fastq.gz"
aws s3 cp --quiet ${ref} "${RAW_FASTQ}/ref.fasta"

###############################################################
# Pre-processing before assembly
echo "Reads Pre-processing before assembly"
###############################################################

# discard reads that have mismatching lengths of bases and qualities
echo "**************************" >> ${LOG_DIR}/bbtools.log.txt
echo "Reads Reformatting" >> ${LOG_DIR}/bbtools.log.txt
echo "**************************" >> ${LOG_DIR}/bbtools.log.txt
reformat.sh -Xmx16g -eoom \
  in="${RAW_FASTQ}/read1.fastq.gz" \
  in2="${RAW_FASTQ}/read2.fastq.gz" \
  out="${QC_FASTQ}/repaired-interleaved.fastq.gz" \
  tossbrokenreads=t &> ${LOG_DIR}/bbtools.log.txt


# Constant definitions for bbduk, increased the quailty
adapterFile="adapters,phix"
trimQuality=${trimQuality:-25} #old 25
minLength=${minLength:-50}  #old 50
kmer_value=${kmer_value:-23}
min_kmer_value=${min_kmer_value:-11}

# Use bbduk to trim short reads, -eoom exits when out of memory
#in1="${QC_FASTQ}/read1_deduped.fastq.gz" \
#in2="${QC_FASTQ}/read2_deduped.fastq.gz" \
echo "**************************" >> ${LOG_DIR}/bbtools.log.txt
echo "Reads trimming/filtering" >> ${LOG_DIR}/bbtools.log.txt
echo "**************************" >> ${LOG_DIR}/bbtools.log.txt
bbduk.sh -Xmx16g tbo -eoom hdist=1 qtrim=rl ktrim=r \
    entropy=0.5 entropywindow=50 entropyk=5 entropytrim=rl \
    in="${QC_FASTQ}/repaired-interleaved.fastq.gz" \
    out1="${QC_FASTQ}/read1_trimmed.fastq.gz" \
    out2="${QC_FASTQ}/read2_trimmed.fastq.gz" \
    ref=${adapterFile} \
    k="${kmer_value}" \
    mink="${min_kmer_value}" \
    trimq="${trimQuality}" \
    minlen="${minLength}" \
    tossbrokenreads=t \
    refstats="${LOCAL_OUTPUT}/BBDuk/adapter_trimming_stats_per_ref.txt" \
    >> ${LOG_DIR}/bbtools.log.txt 2>&1


#Run fastqc for short reads
fastqc \
-t ${coreNum} \
-o ${FASTQC_OUTPUT} \
"${QC_FASTQ}/read1_trimmed.fastq.gz" \
"${QC_FASTQ}/read2_trimmed.fastq.gz"


echo "**************************"
echo "Pre-Processing Long reads"
echo "**************************"

# get long read length Histogram
readlength.sh in="${RAW_FASTQ}/long.fastq.gz" bin=500 max=20000 ignorebadquality > ${LOG_DIR}/longreads.LengthHistogram.txt

# Quality priority rather than length priority

#filtlong \
#--min_length 5000 \
#--keep_percent 10 \
#--min_mean_q 25 \
#--mean_q_weight 10 \
#"${QC_FASTQ}/long_fastp.fastq.gz" | gzip > "${QC_FASTQ}/long_trimmed.fastq.gz"


#Run fastqc for long reads
fastqc \
-t ${coreNum} \
-o ${FASTQC_OUTPUT2} \
"${QC_FASTQ}/long_trimmed.fastq.gz"

# get filtered long read length Histogram
readlength.sh in="${QC_FASTQ}/long_trimmed.fastq.gz" bin=500 max=20000 ignorebadquality > ${LOG_DIR}/Filtered_longreads.LengthHistogram.txt

# short reads mapping

repair.sh \
 in="${QC_FASTQ}/read1_trimmed.fastq.gz" \
 in2="${QC_FASTQ}/read2_trimmed.fastq.gz" \
 out="${QC_FASTQ}/read1_trimmed_repaired.fastq.gz" \
 out2="${QC_FASTQ}/read2_trimmed_repaired.fastq.gz"

bbmap.sh -Xmx24g -eoom \
    perfectmode=t ambiguous=all tossbrokenreads=t \
    in="${QC_FASTQ}/read1_trimmed_repaired.fastq.gz"  \
    in2="${QC_FASTQ}/read2_trimmed_repaired.fastq.gz" \
    ref="${RAW_FASTQ}/ref.fasta" \
    out=stdout | pileup.sh in=stdin out=${LOG_DIR}/short_coverage.txt overwrite=t 2>${LOG_DIR}/short_stats.txt


# long reads mapping
minimap2 -t ${coreNum} -ax map-ont -a "${RAW_FASTQ}/ref.fasta"  "${QC_FASTQ}/long_trimmed.fastq.gz" | samtools sort -@${coreNum} -o "${BAM_OUTPUT_LONG}/longreads_vs_assembly.sorted.bam" -
samtools index "${BAM_OUTPUT_LONG}/longreads_vs_assembly.sorted.bam"

# filter for perfect reads - no 100% aligned ONT reads
bamParser.py -bam "${BAM_OUTPUT_LONG}/longreads_vs_assembly.sorted.bam" -id 99 -aln_len 99 -out "${BAM_OUTPUT_LONG}/filtered_longreads_vs_assembly.sorted.bam" > ${LOG_DIR}/long_bamParser.txt
pileup.sh in="${BAM_OUTPUT_LONG}/filtered_longreads_vs_assembly.sorted.bam" out=${LOG_DIR}/long_coverage.txt overwrite=t 2>${LOG_DIR}/long_stats.txt

# synthetic short reads from long reads - coverage

reformat.sh in="${QC_FASTQ}/long_trimmed.fastq.gz" out="${SYN_READS}/long_trimmed.fasta.gz" ignorebadquality=t

randomreads.sh -Xmx24g -eoom \
 ref="${SYN_READS}/long_trimmed.fasta.gz" \
 out="${SYN_READS}/syn_R1_001.fastq.gz" \
 out2="${SYN_READS}/syn_R2_001.fastq.gz" \
 q=30 banns=t \
 coverage=1 \
 length=150 paired=t \
 mininsert=400 maxinsert=500 \
 snprate=0 insrate=0 delrate=0 subrate=0 overwrite=t adderrors=f bell perfect=1

 repair.sh \
  in="${SYN_READS}/syn_R1_001.fastq.gz" \
  in2="${SYN_READS}/syn_R2_001.fastq.gz" \
  out="${SYN_READS}/syn_R1_repaired.fastq.gz" \
  out2="${SYN_READS}/syn_R2_repaired.fastq.gz"

# syn reads aligned to reference
 bbmap.sh -Xmx24g -eoom \
     perfectmode=t ambiguous=all tossbrokenreads=t \
     in="${SYN_READS}/syn_R1_repaired.fastq.gz" \
     in2="${SYN_READS}/syn_R2_repaired.fastq.gz" \
     ref="${RAW_FASTQ}/ref.fasta" \
     out=stdout | pileup.sh in=stdin out=${LOG_DIR}/syn_coverage.txt overwrite=t 2>${LOG_DIR}/syn_stats.txt

 # filtered short reads aligned to filtered long reads
 bbmap.sh -Xmx24g -eoom \
     perfectmode=t ambiguous=all tossbrokenreads=t \
     in="${QC_FASTQ}/read1_trimmed_repaired.fastq.gz"  \
     in2="${QC_FASTQ}/read2_trimmed_repaired.fastq.gz" \
     ref="${SYN_READS}/long_trimmed.fasta.gz"\
     out=stdout | pileup.sh in=stdin out=${LOG_DIR}/short_vs_long_coverage.txt overwrite=t 2>${LOG_DIR}/short_vs_long_stats.txt


#########################################################
echo "Get mapping stats"
#########################################################

# Count input reads, PE reads count once
totalShortReads=$(( $( zcat ${RAW_FASTQ}/read1.fastq.gz | wc -l ) / 4 ))
totalFilteredSreads=$(( $( zcat ${QC_FASTQ}/read1_trimmed.fastq.gz | wc -l ) / 4 ))

totalLongReads=$(( $( zcat ${RAW_FASTQ}/long.fastq.gz | wc -l ) / 4 ))
#sampledReads=$(( $( zcat  ${QC_FASTQ}/read1_sampled.fastq.gz | wc -l ) / 4 ))
#totalFilteredLreads=$(( $( zcat ${QC_FASTQ}/long_trimmed.fastq.gz | wc -l ) / 4 ))
#totalContigs=$(grep -c "^>" ${ASSEMBLY_OUTPUT}/assembly.fasta )
TotalSynReads=$(( $( zcat ${SYN_READS}/syn_R1_001.fastq.gz | wc -l ) / 4 ))

totalLongBases=`zcat ${RAW_FASTQ}/long.fastq.gz | paste - - - - | cut -f2 | wc -c`
totalFilteredLbases=`zcat ${QC_FASTQ}/long_trimmed.fastq.gz | paste - - - - | cut -f2 | wc -c`


ShortPMappedReads=`grep "Mapped reads:" ${LOG_DIR}/short_stats.txt | cut -f 2-`
ShortPMappedPct=`grep "Percent mapped:" ${LOG_DIR}/short_stats.txt | cut -f 2-`
ShortPAvgCovDepth=`grep "Average coverage:" ${LOG_DIR}/short_stats.txt | cut -f 2-`
ShortPCovPct=`grep "Percent of reference bases covered:" ${LOG_DIR}/short_stats.txt | cut -f 2-`

LongPMappedReads=`grep "Mapped reads:" ${LOG_DIR}/long_stats.txt | cut -f 2-`
#LongPMappedPct=`grep "Percent mapped:" ${LOG_DIR}/long_stats.txt | cut -f 2-`
LongPMappedPct=`grep -Po "(?<=\[).*(?=\])" ${LOG_DIR}/long_bamParser.txt | cut -d'~' -f 2 | cut -d'%' -f 1`
LongPAvgCovDepth=`grep "Average coverage:" ${LOG_DIR}/long_stats.txt | cut -f 2-`
LongPCovPct=`grep "Percent of reference bases covered:" ${LOG_DIR}/long_stats.txt | cut -f 2-`

SynPMappedReads=`grep "Mapped reads:" ${LOG_DIR}/syn_stats.txt | cut -f 2-`
SynPMappedPct=`grep "Percent mapped:" ${LOG_DIR}/syn_stats.txt | cut -f 2-`
SynPAvgCovDepth=`grep "Average coverage:" ${LOG_DIR}/syn_stats.txt | cut -f 2-`
SynPCovPct=`grep "Percent of reference bases covered:" ${LOG_DIR}/syn_stats.txt | cut -f 2-`

shortPMappedLReads=`grep "Mapped reads:" ${LOG_DIR}/short_vs_long_stats.txt | cut -f 2-`
shortPMappedLPct=`grep "Percent mapped:" ${LOG_DIR}/short_vs_long_stats.txt | cut -f 2-`
shortPAvgCovLDepth=`grep "Average coverage:" ${LOG_DIR}/short_vs_long_stats.txt | cut -f 2-`
shortPCovLPct=`grep "Percent of reference bases covered:" ${LOG_DIR}/short_vs_long_stats.txt | cut -f 2-`

shortUsedRate=`echo "scale=2; $totalFilteredSreads*100/$totalShortReads" | bc -l`
longUsedRate=`echo "scale=2; $totalFilteredLbases*100/$totalLongBases" | bc -l`

echo 'SampleName,TotalLongReads,TotalShortReads,TotalSynReads(1x),FilteredLongPct(Bases),FilteredShortPct(Reads),longPerfectMappingPct(0.99),shortPerectMappingPct,synPerectMappingPct,RefByPLongCoverage(0.99),RefByPShortCoverage,RefByPSynCoverage,RefByPLongCovDepth(0.99),RefByPShortCovDepth,RefByPSynCovDepth,shortPMappedLPct,shortPCovLPct,shortPAvgCovLDepth' > ${LOG_DIR}/mapping_stats.txt
echo ${SAMPLE_NAME}','${totalLongReads}','${totalShortReads}','${TotalSynReads}','${longUsedRate}','${shortUsedRate}','${LongPMappedPct}','${ShortPMappedPct}','${SynPMappedPct}','${LongPCovPct}','${ShortPCovPct}','${SynPCovPct}','${LongPAvgCovDepth}','${ShortPAvgCovDepth}','${SynPAvgCovDepth}','${shortPMappedLPct}',' \
${shortPCovLPct}','${shortPAvgCovLDepth} >> ${LOG_DIR}/mapping_stats.txt


######################### HOUSEKEEPING #############################
DURATION=$((SECONDS - START_TIME))
hrs=$(( DURATION/3600 )); mins=$(( (DURATION-hrs*3600)/60)); secs=$(( DURATION-hrs*3600-mins*60 ))
printf 'This AWSome pipeline took: %02d:%02d:%02d\n' $hrs $mins $secs > ${LOCAL_OUTPUT}/job.complete
echo "Live long and prosper" >> ${LOCAL_OUTPUT}/job.complete
############################ PEACE! ################################
## Sync output
aws s3 sync "${LOCAL_OUTPUT}" "${S3OUTPUTPATH}"
# rm -rf "${OUTPUTDIR}"
