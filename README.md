Sample scripts
====================

### A batch script showing the submission example for the Nextflow framework on aws.


## Seedfile example
### Note that the seedfile is a tab-separated values file without header
### The format is sample_name, assembly_path, short_R1, short_R2 and long_reads

```{bash}
SH0002532-00280	s3://genomics-workflow-core/Results/HybridAssembly/MITI-MCB/SH0002532-00280/20230505/UNICYCLER/assembly.fasta	s3://czb-seqbot/fastqs/230202_A01679_0080_AHJC32DMXY/2300120_MITI-MCB-WGS-QCPlate5/230112_MCB_DD_FLEX_E2_SH0002532-00280_S174_R1_001.fastq.gz	s3://czb-seqbot/fastqs/230202_A01679_0080_AHJC32DMXY/2300120_MITI-MCB-WGS-QCPlate5/230112_MCB_DD_FLEX_E2_SH0002532-00280_S174_R2_001.fastq.gz	s3://genomics-workflow-core/Results/Nanoseq/230427_MITI-WGS_FAV21068-Kit114/nanolyse/SH0002532-00280_R1.fastq.gz
```
## MITI samples
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

## long reads alignment threshold: 99%
### A sample output stat file at s3://genomics-workflow-core/Results/mitiprojects/test7/SH0001517-00271/Logs/mapping_stats.txt

```{bash}
SampleName,TotalLongReads,TotalShortReads,TotalSynReads(1x),FilteredLongPct(Bases),FilteredShortPct(Reads),longPerfectMappingPct(0.99),shortPerectMappingPct,synPerectMappingPct,RefByPLongCoverage(0.99),RefByPShortCoverage,RefByPSynCoverage,RefByPLongCovDepth(0.99),RefByPShortCovDepth,RefByPSynCovDepth,shortPMappedLPct,shortPCovLPct,shortPAvgCovLDepth
SH0001517-00271,234958,11726520,5966527,83.39,75.04,0.002,97.698,39.023,0.05,100.00,99.99,0.001,540.217,160.272,97.932,15.42,1.306
```
