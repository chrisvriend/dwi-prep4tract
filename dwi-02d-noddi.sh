#!/bin/bash

#SBATCH --job-name=NODDI
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-short
#SBATCH --cpus-per-task=1
#SBATCH --time=00-00:20:00
#SBATCH --nice=3000
#SBATCH --qos=anw
#SBATCH --output gpunoddi_%A.log

module load fsl/6.0.6.5
#module load cuda/10.2
CUDIMOT=/home/anw/cvriend/my-scratch/cudimot/FSLDEV
#CUDIMOT=/home/anw/cvriend/CUDIMOT

export CUDIMOT


# inputs
subjdir=${1}

${CUDIMOT}/bin/Pipeline_NODDI_Watson.sh ${subjdir}


