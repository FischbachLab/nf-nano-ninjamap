# Base Image
FROM continuumio/miniconda3:4.6.14
LABEL authors="Xiandong Meng" \
      description="Docker image for short and long reads mapping" \
      software.name="miti-projects" \
      software.description="short and long reads perfect mapping" \
      software.website="" \
      container.category="tool"


# Update conda to latest version.
RUN conda update -n base -c defaults conda

# Install software
RUN conda install --freeze-installed -c conda-forge -y awscli bc perl python=3.7 \
  && conda install --freeze-installed -c bioconda -y bbmap=38.73 sambamba=0.7.1 samtools fastqc filtlong minimap2 qualimap fastp java-jdk perl-bioperl numpy pysam pandas \
  && conda clean -afy

# Conda upgrade all packages
#RUN conda update --all


RUN mkdir -p /work
WORKDIR /work

COPY . .
