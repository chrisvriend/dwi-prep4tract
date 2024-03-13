#!/bin/bash

#SBATCH --job-name=FS_clinical
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=8
#SBATCH --time=00-4:00:00
#SBATCH --nice=2000
#SBATCH -o FSclin_%A.log
#SBATCH --mail-type=END,FAIL

# usage instructions
Usage() {
    cat <<EOF


    (C) Chris Vriend - AmsUMC - 21-10-2023
    script to run recon-all-clinical and prepare FreeSurfer output 
    for fmri preprocessing using fmriprep
   
    Usage: sbatch GOALS_reconall_clinical.sh <bidsdir> <derivativesdir> <subjID> <session>  
    Obligatory:
    bidsdir = full path to bids directory that contains subject's anatomical file in bids format
    derivativesdir = full path to folder where the freesurfer output will be saved/created 
    subjID = subject ID according to BIDS (e.g. sub-1000)

    Optional:
	session = session ID, e.g. ses-T0. keep empty if there are no sessions

	additional options and paths may need to be checked/modified in the script
    at least the ACQUISITION variable

EOF
    exit 1
}

[ _$3 = _ ] && Usage

# source FreeSurfer
module load FreeSurfer/7.4.1.bugfix-centos8_x86_64

bidsdir=${1}
derivativesdir=${2}
subj=${3}
session=${4}
acquisition=${5}

## change these according to needs ##
ncores=8
#####################################

if [ -z "$session" ]; then
    # sess empty
    sessionpath=/
    sessionfile=_
else
    sessionpath=/${session}/
    sessionfile=_${session}_
fi

freesurferdir=${derivativesdir}/freesurfer
mkdir -p ${freesurferdir}
export SUBJECTS_DIR=${freesurferdir}

if [ ! -f ${bidsdir}/${subj}${sessionpath}anat/${subj}${sessionfile}${acquisition}_T1w.nii.gz ]; then
    echo "ERROR! input anatomical scan does not exist"
    echo ${subj}${sessionfile}${acquisition}_T1w.nii.gz
    exit
fi

if [[ ! -f ${freesurferdir}/${subj}/mri/aseg.auto.mgz || ! -f ${freesurferdir}/${subj}/mri/wm.awegedit.mgz ]]; then
    recon-all-clinical.sh \
        ${bidsdir}/${subj}${sessionpath}anat/${subj}${sessionfile}${acquisition}_T1w.nii.gz \
        ${subj} \
        ${ncores} \
        ${freesurferdir}
else
    echo "FreeSurfer already ran for ${subj}"

fi

# check if necessary FreeSurfer files are there
if [[ ! -f ${freesurferdir}/${subj}/mri/wmparc.mgz ||
    ! -f ${freesurferdir}/${subj}/mri/aseg.mgz ]]; then
    echo
    echo "ERROR! FreeSurfer did not finish correctly"
    echo "abort script"
    exit
fi

for scan in orig rawavg orig_nu T1 nu; do

    ln -sr ${freesurferdir}/${subj}/mri/native.mgz \
        ${freesurferdir}/${subj}/mri/${scan}.mgz

done
mkdir -p ${freesurferdir}/${subj}/mri/orig
ln -sr ${freesurferdir}/${subj}/mri/native.mgz \
    ${freesurferdir}/${subj}/mri/orig/001.mgz

ln -sr ${freesurferdir}/${subj}/mri/brainmask.mgz \
    ${freesurferdir}/${subj}/mri/brainmask.auto.mgz

ln -sr ${freesurferdir}/${subj}/mri/transforms/talairach.xfm.lta \
    ${freesurferdir}/${subj}/mri/transforms/talairach.auto.xfm.lta

ln -sr ${freesurferdir}/${subj}/mri/transforms/talairach.xfm \
    ${freesurferdir}/${subj}/mri/transforms/talairach.auto.xfm
ln -sr ${freesurferdir}/${subj}/mri/aseg.mgz \
    ${freesurferdir}/${subj}/mri/aseg.auto.mgz
ln -sr ${freesurferdir}/${subj}/mri/wm.mgz \
    ${freesurferdir}/${subj}/mri/wm.asegedit.mgz
ln -sr ${freesurferdir}/${subj}/mri/brain.mgz \
    ${freesurferdir}/${subj}/mri/brain.finalsurfs.mgz
