#!/bin/bash 

# input variables and paths
scriptdir=/data/anw/anw-gold/NP/projects/data_chris/Tmult/scripts/dwi-scripts
bidsdir=/data/anw/anw-gold/NP/projects/data_propark/bids
workdir=~/my-scratch/dwi-preproc
outputdir=/home/anw/cvriend/my-scratch/propark_derivatives2
freesurferdir=/data/anw/anw-gold/NP/projects/data_propark/derivatives/freesurfer

#how many in parallel?
simul=2
# run noddi? 1/0 = yes/no
noddi=1


cd ${bidsdir}
ls -d sub-*/ | sed 's:/.*::' > subjects.txt
nsubj=$(ls -d sub-*/ | wc -l)


sbatch --array="1-${nsubj}%${simul}" ${scriptdir}/dwi-01-pipeline_sarray.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} \
    -j ${bidsdir}/subjects.txt -f ${freesurferdir} -n ${noddi} -c ${scriptdir}