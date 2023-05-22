#!/usr/bin/env nextflow
nextflow.enable.dsl=1
// If the user uses the --help flag, print the help text below
params.help = false

// Function which prints help message text
def helpMessage() {
    log.info"""
    Run the mappping pipeline for a given ref, short and long read dataset

    Required Arguments:
      --seedfile      file        a file contains sample_name, ref, reads1, reads2 and long reads
      --output_path   path        Output s3 path

    Options:
      -profile        docker      run locally


    """.stripIndent()
}

// Show help message if the user specifies the --help flag at runtime
if (params.help){
    // Invoke the function above which prints the help message
    helpMessage()
    // Exit out and do not run anything else
    exit 0
}

if (params.output_path == "null") {
	exit 1, "Missing the output path"
}

Channel
  .fromPath(params.seedfile)
  .ifEmpty { exit 1, "Cannot find the input seedfile" }

/*
 * Defines the pipeline inputs parameters (giving a default value for each for them)
 * Each of the following parameters can be specified as command line options
 */

def output_path = "${params.output_path}"
//def output_path=s3://genomics-workflow-core/Pipeline_Results/${params.output_prefix}"

//println output_path

Channel
	.fromPath(params.seedfile)
	.ifEmpty { exit 1, "Cannot find any seed file matching: ${params.seedfile}." }
  .splitCsv(header: ['sample', 'ref', 'reads1', 'reads2', 'long_reads'], sep: '\t')
	.map{ row -> tuple(row.sample, row.ref, row.reads1, row.reads2, row.long_reads)}
	.set { seedfile_ch }


  process fastp_filtering {

      tag "$sample"

      container "fischbachlab/nf-fastp:20230516110344"
      cpus 8
      memory 16.GB

      publishDir "${output_path}/${sample}/filtered_long_reads", mode:'copy', pattern: '*.html'
      publishDir "${output_path}/${sample}/filtered_long_reads", mode:'copy', pattern: '*_fastp.fastq.gz'

      input:
      tuple val(sample), val(ref), val(reads1), val(reads2), val(long_reads) from seedfile_ch


      output:
      tuple val(sample), path("${sample}_fastp.fastq.gz"), val(ref), val(reads1), val(reads2), val(long_reads) into fastp_ch
      path "*.html"


      script:
      """
      export sample="${sample}"
      export longreads="${long_reads}"
      long_filtering_fastp.sh
      """
  }

  //seedfile_ch.view()
  /*
   * Run mapping Pipeline
   */
  process perfect_alignment {

      tag "$sample"
      //container "xianmeng/nf-hybridassembly:latest"
      container params.container
      cpus 16
      memory 32.GB

      //publishDir "${output_path}", mode:'copy'

      input:
    	tuple val(sample), path(filtered_long), val(ref), val(reads1), val(reads2), val(long_reads) from fastp_ch

      output:
      //path "*"

      script:
      """
      export sample="${sample}"
      export ref="${ref}"
      export fastq1="${reads1}"
      export fastq2="${reads2}"
      export longreads="${long_reads}"
      export trimmedlongreads="${filtered_long}"
      export S3OUTPUTPATH="${output_path}/${sample}"
      cal_perfect_alignment.sh
      """
  }
