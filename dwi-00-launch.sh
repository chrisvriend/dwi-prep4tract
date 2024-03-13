#!/bin/bash 


# (C) C. Vriend - Aumc ANW/Psy - June '23
# c.vriend@amsterdamumc.nl
# script launches the pipeline using dwi-01-pipeline.sh for one subject specified under ${subj}


# input variables and paths
scriptdir=/home/anw/cvriend/dwi-prep4tract
bidsdir=/data/anw/anw-archive/NP/imaging-samples/OCD_global
workdir=~/my-scratch/dwi-preproc
outputdir=/data/anw/anw-archive/NP/projects/archive_OBS/derivatives
freesurferdir=/data/anw/anw-archive/NP/projects/archive_OBS/derivatives/freesurfer
subj=sub-5125
noddi=0


# launch pipeline for one subject
sbatch ${scriptdir}/dwi-01-pipeline.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} \
    -s ${subj} -f ${freesurferdir} -n ${noddi} -c ${scriptdir}
