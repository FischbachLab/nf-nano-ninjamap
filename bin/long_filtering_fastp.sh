#!/bin/bash -x

set -e
set -u
set -o pipefail

START_TIME=$SECONDS
export PATH="/opt/conda/bin:${PATH}"

LOCAL=$(pwd)
coreNum=${coreNum:-8}

# s3 inputs from env variables
#longreads="${}" input long reads in fastq format

# Setup directory structure
OUTPUTDIR=${LOCAL}/tmp_$( date +"%Y%m%d_%H%M%S" )
RAW_FASTQ="${OUTPUTDIR}/raw_fastq"

LOCAL_OUTPUT="${OUTPUTDIR}/Sync"
LOG_DIR="${LOCAL_OUTPUT}/Logs"

SAMPLE_NAME="${sample}"

mkdir -p "${OUTPUTDIR}" "${LOCAL_OUTPUT}" "${LOG_DIR}" "${RAW_FASTQ}"
trap '{ rm -rf ${OUTPUTDIR} ; exit 255; }' 1

# Copy fastq.gz files from S3
aws s3 cp --quiet ${longreads} "${RAW_FASTQ}/long.fastq.gz"

echo "**************************"
echo "Pre-Processing Long reads"
echo "**************************"

: <<'COMMENT'
/fastp \
-w ${coreNum} \
-i "${RAW_FASTQ}/long.fastq.gz" \
-o "${SAMPLE_NAME}_fastp.fastq.gz" \
--disable_adapter_trimming \
--trim_front1 10 \
--cut_front \
--cut_tail \
--length_required 1000 \
--html "${SAMPLE_NAME}.html" \
--json "${SAMPLE_NAME}.json" \
--report_title "${SAMPLE_NAME}"
COMMENT


/fastp \
-w ${coreNum} \
-i "${RAW_FASTQ}/long.fastq.gz" \
-o "${SAMPLE_NAME}_fastp.fastq.gz" \
--trim_front1 10 \
--length_required 500 \
--cut_window_size 20 \
--cut_mean_quality 30 \
--cut_front \
--cut_tail \
--average_qual 30 \
--disable_adapter_trimming \
--html "${SAMPLE_NAME}.html" \
--json "${SAMPLE_NAME}.json" \
--report_title "${SAMPLE_NAME}"



######################### HOUSEKEEPING #############################
DURATION=$((SECONDS - START_TIME))
hrs=$(( DURATION/3600 )); mins=$(( (DURATION-hrs*3600)/60)); secs=$(( DURATION-hrs*3600-mins*60 ))
printf 'This AWSome pipeline took: %02d:%02d:%02d\n' $hrs $mins $secs
############################ PEACE! ################################
## Sync output
#aws s3 sync "${LOCAL_OUTPUT}" "${S3OUTPUTPATH}"
# rm -rf "${OUTPUTDIR}"
