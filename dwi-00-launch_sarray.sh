#!/bin/bash 

# (C) C. Vriend - Aumc ANW/Psy - June '23
# c.vriend@amsterdamumc.nl

# wrapper script to launch multiple instances of dwi preprocessing and tractography pipeline using SLURM arrays.
# pipeline is launched for all folders found in the BIDS directory that begin with sub-*
# modify input variables and no. simultaneous subjects to process

# input variables and paths

scriptdir=/home/anw/cvriend/dwi-prep4tract
bidsdir=/data/anw/anw-archive/NP/imaging-samples/OCD_ARRIBA
workdir=~/my-scratch/dwi-preproc
outputdir=/data/anw/anw-archive/NP/projects/archive_ARRIBA/derivatives
freesurferdir=~/my-scratch/ARRIBA_FS


#how many in parallel?
simul=4
# run noddi? 1/0 = yes/no
noddi=0


# insert own subjlist OR let the script produce it for you from the bids directory

#cd ${bidsdir}
#ls -d sub-*/ | sed 's:/.*::' > ${scriptdir}/subjects.txt
#nsubj=$(ls -d sub-*/ | wc -l)
nsubj=$(cat ${scriptdir}/subjects2.txt | wc -l)

cd ${scriptdir}

# launch pipeline slurm array
sbatch --array="1-${nsubj}%${simul}" ${scriptdir}/dwi-01-pipeline_sarray.sh \
 -i ${bidsdir} \
 -o ${outputdir} -w ${workdir} \
 -j ${scriptdir}/subjects2.txt \
 -f ${freesurferdir} -n ${noddi} -c ${scriptdir}
