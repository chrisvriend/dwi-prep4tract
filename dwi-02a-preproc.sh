#!/bin/bash

# (C) Chris Vriend - Amsterdam UMC - May 23 2023

#SBATCH --job-name=dwi-preproc
#SBATCH --mem=6G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=8
#SBATCH --time=00-02:00:00
#SBATCH --nice=2000
#SBATCH --output=dwi-preproc_%A.log

#notes:

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[34m'
NC='\033[0m' # No Color

## source software
module load fsl/6.0.6.5
module load ANTs/2.5.0
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python-env/mrtrix
synthstrippath=/scratch/anw/share-np/fmridenoiser/synthstrip.1.2.sif
threads=8

# Initialize variables
bidsdir=""
outputdir=""
workdir=""
subj=""
scriptdir=""
# input variables
# Parse command line arguments
while getopts ":i:o:w:s:c:" opt; do
    case $opt in
    i)
        bidsdir="$OPTARG"
        ;;
    o)
        outputdir="$OPTARG"
        ;;
    w)
        workdir="$OPTARG"
        ;;
    s)
        subj="$OPTARG"
        ;;
    c)
        scriptdir="$OPTARG"
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        ;;
    esac
done

mkdir -p ${workdir}
mkdir -p "${outputdir}/dwi-preproc"

for dwidir in ${bidsdir}/${subj}/{,ses*/}dwi; do
    if [ ! -d ${dwidir} ]; then
        continue
    fi
    sessiondir=$(dirname ${dwidir})

    # if [[ $(ls ${sessiondir}/dwi/*dwi.nii.gz | wc -l) -gt 1 ]]; then
    #     echo -e "${RED}ERROR! this script cannot handle >1 dwi scan per session${NC}"
    #     echo -e "${RED}exiting script${NC}"
    #     exit
    # fi

    session=$(echo "${sessiondir}" | grep -oP "(?<=${subj}/).*")
    if [ -z ${session} ]; then
        sessionpath=/
        sessionfile=_
    else
        sessionpath=/${session}/
        sessionfile=_${session}_

    fi

    cd ${dwidir}

    dwiacqs=$(ls -1 ${subj}${sessionfile}*_dwi.nii.gz)
    acqs=$(echo "$dwiacqs" | cut -d'-' -f4 | cut -d'_' -f1 | sort -u)

    for acq in ${acqs}; do

        dwiruns=$(ls -1 ${subj}${sessionfile}acq-${acq}*_dwi.nii.gz)
        runs=$(echo "$dwiruns" | cut -d'-' -f5 | cut -d'_' -f1 | sort -u)

        for run in ${runs}; do

            if [[ ! -f ${dwidir}/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.nii.gz || ! -f ${dwidir}/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.bvec ]]; then
                echo -e "${YELLOW}no dwi scan/bvec found for ${subj} - ${session} | acq-${acq} | run-${run} ${NC}"

                continue

            fi

            echo -e ${YELLOW}----------------------${NC}
            echo -e ${YELLOW}Preprocessing dwi data${NC}
            echo -e ${YELLOW}${subj}${NC}
            echo -e ${YELLOW}${session}${NC}
            echo -e ${YELLOW}acq-${acq}${NC}
            echo -e ${YELLOW}run-${run}${NC}
            echo -e ${YELLOW}----------------------${NC}

            mkdir -p "${outputdir}/dwi-preproc/${subj}/logs"

            if [[ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.nii.gz ]] &&
                [[ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.bval ]] &&
                [[ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.bvec ]]; then
                echo -e "${GREEN}${subj}${sessionfile} already preprocessed with eddy${NC}"
                continue
            fi

            mkdir -p "${workdir}/${subj}${sessionpath}dwi"
            mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}dwi"
            mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}logs"
            mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}figures"

            # Specify the path to the DWI JSON sidecar
            dwi_json_path=$(ls ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.json)
            # extract TotalReadoutTime
            dwi_trt=$(cat ${dwi_json_path} | jq -r '.TotalReadoutTime')

            # Specify the path to the fieldmap folder
            fieldmap_folder=${sessiondir}/fmap

            # MP-PCA denoising of dwi scan
            if [ ! -f ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns+degibbs_dwi.nii.gz ]; then
                dwidenoise ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.nii.gz \
                    ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns_dwi.mif \
                    -nthreads ${threads}
                #Remove Gibbs Ringing Artifacts
                mrdegibbs ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns_dwi.mif \
                    ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns+degibbs_dwi.nii.gz \
                    -nthreads ${threads}
                rm ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns_dwi.mif
            fi

            ###################
            ### round bvals ###
            ###################
         #   ${scriptdir}/round_bvals.py ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.bval

            #######################
            ## create brain mask ##
            #######################

            # Get the mean b-zero (un-corrected)
            dwiextract -nthreads ${threads} \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns+degibbs_dwi.nii.gz - -bzero \
                -fslgrad ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}*dwi.bvec ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.bval |
                mrmath - mean ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-nodif_epi.nii.gz -axis 3

           
            if [ ! -f ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-brain-uncorrected_mask.nii.gz ]; then
            apptainer run --cleanenv ${synthstrippath} \
                -i ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-nodif_epi.nii.gz \
                --mask ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-brain-uncorrected_mask.nii.gz
            fi
            ##########
            ## EDDY ##
            ##########
            cd ${scriptdir}/${subj}

            echo
            echo -e "${BLUE}starting EDDY${NC}"
            echo
            echo "0 1 0 ${dwi_trt}" >${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_desc-acqparams.tsv
          
          # opted now for eddy_openmp instead of gpu (because of frequent inavailability of gpu on luna1)
          #  sbatch --wait --gres=gpu:1g.10gb:1 ${scriptdir}/dwi-02b-eddy.sh \

            sbatch --wait ${scriptdir}/dwi-02b-eddy-cpu.sh \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-dns+degibbs_dwi.nii.gz \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-brain-uncorrected_mask.nii.gz \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_desc-acqparams.tsv \
                ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.bvec \
                ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.bval \
                ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}_dwi.json \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}space-dwi_desc-topup \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc \
                nofmap
            # topup/fmap does not exist but left in
            cp eddy_*.log ${outputdir}/dwi-preproc/${subj}${sessionpath}logs/${subj}${sessionfile}acq-${acq}_run-${run}_eddy.log

            # rename output
            cd ${workdir}/${subj}${sessionpath}dwi
            mv ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc.eddy_rotated_bvecs \
                ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.bvec
            mv ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc.nii.gz \
                ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.nii.gz
            mv ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc.eddy_cnr_maps.nii.gz \
                ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz
            cp ${sessiondir}/dwi/${subj}${sessionfile}acq-${acq}_run-${run}*dwi.bval \
                ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.bval
            mv *.qc eddyqc

            rsync -av ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi*_dwi.* ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-brain-uncorrected_mask.nii.gz eddyqc \
                ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi

            # clean-up
            if [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.nii.gz ] &&
                [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc_dwi.bvec ] &&
                [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz ]; then
                rm -r ${workdir}/${subj}${sessionpath}
                rm ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/*meanb0* \
                    ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/*dns+degibbs*

                echo
                echo -e ${GREEN}FINISHED processing ${subj}${sessionpath}acq-${acq}_run-${run}${NC}
                echo

            else
                echo -e "${RED}ERROR! not all output was created successfully${NC}"

            fi

        done
    done

done
