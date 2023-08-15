#!/bin/bash 


# (C) C. Vriend - Aumc ANW/Psy - June '23
# c.vriend@amsterdamumc.nl
# script launches the pipeline using dwi-01-pipeline.sh for one subject specified under ${subj}


# input variables and paths
scriptdir=/data/anw/anw-gold/NP/projects/data_chris/Tmult/scripts
bidsdir=/data/anw/anw-gold/NP/projects/data_propark/bids/
workdir=~/my-scratch/dwi-preproc
outputdir=/home/anw/cvriend/my-scratch/propark_derivatives
freesurferdir=/data/anw/anw-gold/NP/projects/data_propark/derivatives/freesurfer
subj=sub-proparkXXXX


# launch pipeline for one subject
sbatch ${scriptdir}/dwi-01-pipeline.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} \
    -s ${subj} -f ${freesurferdir} -n ${noddi} -c ${scriptdir}