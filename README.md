Sample scripts
====================

# A simple script showing the submission example for the Nextflow framework on aws.


# Seedfile example
## Note that the seedfile is a tab-separated values file without header
## The format is sample_name, assembly_path, short_R1, short_R2 and long_reads

```{bash}
SH0002532-00280	s3://genomics-workflow-core/Results/HybridAssembly/MITI-MCB/SH0002532-00280/20230505/UNICYCLER/assembly.fasta	s3://czb-seqbot/fastqs/230202_A01679_0080_AHJC32DMXY/2300120_MITI-MCB-WGS-QCPlate5/230112_MCB_DD_FLEX_E2_SH0002532-00280_S174_R1_001.fastq.gz	s3://czb-seqbot/fastqs/230202_A01679_0080_AHJC32DMXY/2300120_MITI-MCB-WGS-QCPlate5/230112_MCB_DD_FLEX_E2_SH0002532-00280_S174_R2_001.fastq.gz	s3://genomics-workflow-core/Results/Nanoseq/230427_MITI-WGS_FAV21068-Kit114/nanolyse/SH0002532-00280_R1.fastq.gz
```
# MITI samples
### Final output path: s3://genomics-workflow-core/Results/nano-ninjamap/
```{bash}
aws batch submit-job \
  --job-name nf-miti-project \
  --job-queue priority-maf-pipelines \
  --job-definition nextflow-production \
  --container-overrides command="FischbachLab/nf-nano-ninjamap, \
"--seedfile", "s3://genomics-workflow-core/Results/mitiprojects/230510_seedfile.tsv", \
"--output_path", "s3://genomics-workflow-core/Results/nano-ninjamap" "
```
