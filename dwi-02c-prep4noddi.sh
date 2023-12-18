#!/bin/bash

#SBATCH --job-name=prepNODDI
#SBATCH --mem=4G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=8
#SBATCH --time=00-00:45:00
#SBATCH --nice=2000
#SBATCH --output=noddi_%A.log

###############################################################################
# source software                                                    #
###############################################################################
module load fsl/6.0.6.5
module load ANTs/2.4.1
module load Anaconda3/2022.05
synthstrippath=/data/anw/anw-gold/NP/doorgeefluik/container_apps/synthstrip.1.2.sif
conda activate /scratch/anw/share/python-env/mrtrix
#scriptdir=/data/anw/anw-gold/NP/projects/data_chris/Tmult/scripts

threads=8

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[34m'
NC='\033[0m' # No Color

# Initialize variables
outputdir=""
workdir=""
subj=""
scriptdir=""
# input variables
# Parse command line arguments
while getopts ":o:w:s:c:" opt; do
    case $opt in
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

for dwidir in ${outputdir}/dwi-preproc/${subj}/{,ses*/}dwi; do
    if [ ! -d ${dwidir} ]; then
        continue
    fi
    sessiondir=$(dirname ${dwidir})
    echo
    echo ${sessiondir}
    echo

    session=$(echo "${sessiondir}" | grep -oP "(?<=${subj}/).*")
    if [ -z ${session} ]; then
        sessionpath=/
        sessionfile=_
    else
        sessionpath=/${session}/
        sessionfile=_${session}_
        sessionID=-${session}

    fi

    # determine whether it is single or multishell
    read -r line <${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval
    # Split the line into an array of values
    IFS=" " read -ra values <<<"$line"
    # Filter out values greater than 0 and keep only unique values
    unique_values=$(printf "%s\n" "${values[@]}" | awk '$1 > 0' | sort -u)
    # Count the number of shells
    Nshells=$(echo "$unique_values" | wc -w)

    if ((Nshells > 1)); then
        echo
        echo -e "${GREEN}${subj}${sessionfile} is multishell. Preparing for NODDI${NC}"
        echo
        mkdir -p ${workdir}/${subj}${sessionpath}dwi
        rsync -a ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc* \
            ${workdir}/${subj}${sessionpath}dwi
        cd ${workdir}/${subj}${sessionpath}dwi

        if [ ! -f ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz ] ||
            [ ! -f ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz ]; then
            echo -e "${BLUE}skullstrip dwi and create mask${NC}"
            dwiextract -nthreads ${threads} \
                ${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz - -bzero \
                -fslgrad ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec \
                ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval | mrmath - mean ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz -axis 3
            # skullstrip mean b0 (nodif_brain)
            apptainer run --cleanenv ${synthstrippath} \
                -i ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
                -o ${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz \
                --mask ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz
        fi

        # transfer and rename files to NODDI compatible filenames

        mkdir -p ${workdir}/${subj}${sessionpath}noddi/${subj}${sessionID}
        cp ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
            ${workdir}/${subj}${sessionpath}noddi/${subj}${sessionID}/nodif_brain_mask.nii.gz
        cp ${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz \
            ${workdir}/${subj}${sessionpath}noddi/${subj}${sessionID}/data.nii.gz
        cp ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec \
            ${workdir}/${subj}${sessionpath}noddi/${subj}${sessionID}/bvecs
        cp ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval \
            ${workdir}/${subj}${sessionpath}noddi/${subj}${sessionID}/bvals

        cd ${workdir}/${subj}${sessionpath}noddi
        sbatch --wait --gres=gpu:1g.10gb:1 ${scriptdir}/dwi-02d-noddi.sh ${subj}${sessionID}

        if [ -f ${subj}${sessionID}.NODDI_Watson/mean_fiso.nii.gz ]; then
            # rename and move output from NODDI

            #ICVF is the intracellular volume fraction (also known as NDI),
            #OD is the orientation dispersion (the variance of the Bingham; also known as ODI)
            #and ISOVF is the isotropic component volume fraction (also known as IVF)
            # ndi, isovf, odi

            mv ${subj}${sessionID}.NODDI_Watson/OD.nii.gz \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-odi_noddi.nii.gz
            mv ${subj}${sessionID}.NODDI_Watson/mean_fintra.nii.gz \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-ndi_noddi.nii.gz
            mv ${subj}${sessionID}.NODDI_Watson/mean_fiso.nii.gz \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-isovf_noddi.nii.gz

        else

            echo -e "${RED}ERROR! NODDI failed${NC}"
            exit

        fi

        rsync -av ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi*noddi.nii.gz \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
            ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/
      #  rm -r ${workdir}/${subj}${sessionpath}


    elif ((Nshells == 1)); then
        echo
        echo -e "${YELLOW}DWI ${subj}${sessionpath} is single shell | skipping NODDI${NC}"
        echo
    else
        echo
        echo -e "${RED}ERROR! something went wrong with reading the bval file of ${subj}${sessionpath}"
        echo -e "${RED}NODDI failed${NC}"

    fi

done
