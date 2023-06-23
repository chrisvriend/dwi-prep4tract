#!/bin/bash 

# input variables and paths
scriptdir=/data/anw/anw-gold/NP/projects/data_chris/Tmult/scripts
bidsdir=/data/anw/anw-gold/NP/projects/data_propark/bids/
workdir=~/my-scratch/dwi-preproc
outputdir=/home/anw/cvriend/my-scratch/propark_derivatives
freesurferdir=/data/anw/anw-gold/NP/projects/data_propark/derivatives/freesurfer
subj=sub-proparkXXXX



#how many in parallel?
simul=2
# run noddi? 1/0 = yes/no
noddi=1


cd ${bidsdir}


sbatch --array="1-${nsubj}%${simul}" ${scriptdir}/dwi-01-pipeline.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} \
    -s ${subj} -f ${freesurferdir} -n ${noddi} -c ${scriptdir}