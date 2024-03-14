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

    if [[ ! -f ${dwidir}/${subj}${sessionfile}dwi.nii.gz || ! -f ${dwidir}/${subj}${sessionfile}dwi.bvec ]]; then
        echo -e "${YELLOW}no dwi scan/bvec found for ${subj} - ${session}${NC}"

        continue

    fi

    echo -e ${YELLOW}----------------------${NC}
    echo -e ${YELLOW}Preprocessing dwi data${NC}
    echo -e ${YELLOW}${subj}${NC}
    echo -e ${YELLOW}${session}${NC}
    echo -e ${YELLOW}----------------------${NC}

    if [[ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz ]] &&
        [[ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval ]] &&
        [[ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec ]]; then
        echo -e "${GREEN}${subj}${sessionfile} already preprocessed with eddy${NC}"
        continue
    fi

    mkdir -p "${workdir}/${subj}${sessionpath}dwi"
    mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}dwi"
    mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}logs"
    mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}fmap"
    mkdir -p "${outputdir}/dwi-preproc/${subj}${sessionpath}figures"

    # Specify the path to the DWI JSON sidecar
    dwi_json_path=$(ls ${sessiondir}/dwi/${subj}${sessionfile}dwi.json)
    # extract TotalReadoutTime
    dwi_trt=$(cat ${dwi_json_path} | jq -r '.TotalReadoutTime')

    # Specify the path to the fieldmap folder
    fieldmap_folder=${sessiondir}/fmap

    # MP-PCA denoising of dwi scan
    if [ ! -f ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns+degibbs_dwi.nii.gz ]; then
        dwidenoise ${sessiondir}/dwi/${subj}${sessionfile}dwi.nii.gz \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns_dwi.mif \
            -nthreads ${threads}
        #Remove Gibbs Ringing Artifacts
        mrdegibbs ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns_dwi.mif \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns+degibbs_dwi.nii.gz \
            -nthreads ${threads}
        rm ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns_dwi.mif
    fi
    # Check if the fieldmap folder exists
    if [ -d ${fieldmap_folder} ]; then
        mkdir -p ${workdir}/${subj}${sessionpath}fmap
        # Iterate over the fieldmap JSON sidecars
        if [[ $(ls ${fieldmap_folder}/*acq-dwi*.json | wc -l) -gt 2 ]]; then
            echo -e "${RED}ERROR! more than 2 fieldmaps for acq-dwi found in ${fieldmap_folder}${NC}"
            exit 0
        fi
        for filename in "$fieldmap_folder"/*acq-dwi*.json; do

            # Load the fieldmap JSON sidecar
            fieldmap_json=$(cat ${filename})

            # Check if PhaseEncodingDirection matches the DWI JSON sidecar
            dwi_json=$(cat ${dwi_json_path})
            fieldmap_direction=$(echo ${fieldmap_json} | jq -r '.PhaseEncodingDirection')
            dwi_direction=$(echo ${dwi_json} | jq -r '.PhaseEncodingDirection')

            # Check if PhaseEncodingDirection contains "j" or "j-"
            if [[ $fieldmap_direction == *"j"* ]] || [[ $fieldmap_direction == *"j-"* ]]; then
                # Extract the TotalReadoutTime from the JSON file
                total_readout_time=$(jq -r '.TotalReadoutTime' "$filename")

                echo "${filename}"
                echo -e "${BLUE}PhaseEncodingDirection: $fieldmap_direction${NC}"
                echo -e "${BLUE}TotalReadoutTime: $total_readout_time${NC}"
                echo
            else
                echo -e "${RED}PhaseEncodingDirection does not contain 'j' or 'j-'${NC}"
                exit
            fi

            if [ "$fieldmap_direction" == "$dwi_direction" ]; then
                fmap_dirAP=$(basename "$filename" .json)
                echo -e "${BLUE}${fmap_dirAP} has same PE as DWI${NC}"

                if [[ $(fslnvols ${fieldmap_folder}/${fmap_dirAP}.nii.gz) -gt 1 ]]; then
                    if [ ! -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-degibss_epi.nii.gz ]; then
                        dwidenoise ${fieldmap_folder}/${fmap_dirAP}.nii.gz \
                            ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-dns_epi.mif
                        #Remove Gibbs Ringing Artifacts
                        mrdegibbs ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-dns_epi.mif \
                            ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-degibss_epi.nii.gz
                        rm ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-dns_epi.mif
                    fi
                else
                    mrdegibbs ${fieldmap_folder}/${fmap_dirAP}.nii.gz \
                        ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-degibss_epi.nii.gz

                    APvol=1
                fi

            else
                fmap_dirPA=$(basename "$filename" .json)

                if [[ $(fslnvols ${fieldmap_folder}/${fmap_dirPA}.nii.gz) -gt 1 ]]; then
                    if [ ! -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz ]; then

                        dwidenoise ${fieldmap_folder}/${fmap_dirPA}.nii.gz \
                            ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-dns_epi.mif
                        #Remove Gibbs Ringing Artifacts
                        mrdegibbs ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-dns_epi.mif \
                            ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz
                        rm ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-dns_epi.mif
                    fi
                else
                    mrdegibbs ${fieldmap_folder}/${fmap_dirPA}.nii.gz \
                        ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz

                    PAvol=1
                fi

            fi

        done
    fi
    # in case only PA fmap but not AP available
    # options:
    # 1) extract mean b0 from dwi and merge with fieldma but rigid reg with interpolation necessary
    # 2) take first b0 of dwi map as fieldmap is acquired right before dwi (on Siemens Vida); then uneven number of nvols
    if [ ! -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-degibss_epi.nii.gz ] &&
        [ -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz ]; then

        if (($(head -n 1 "${sessiondir}/dwi/${subj}${sessionfile}dwi.bval" | awk '{print $1}') < 50)); then
            fslroi ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns+degibbs_dwi.nii.gz \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz 0 1

            fslmerge -t ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz
            rm ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz
        else
            # in case b0 is not the first volume

            # extract mean b0 from dwi
            dwiextract -nthreads ${threads} \
                ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns+degibbs_dwi.nii.gz - -bzero \
                -fslgrad ${sessiondir}/dwi/${subj}${sessionfile}*dwi.bvec ${sessiondir}/dwi/${subj}${sessionfile}*dwi.bval |
                mrmath - mean ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz -axis 3

            # create mean b0 from PA fieldmap
            if [[ $(fslnvols ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz) -gt 1 ]]; then
                mrmath ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz \
                    mean \
                    ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-temp_epi.nii.gz -axis 3
            else
                ln -s ${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz \
                    ${subj}${sessionfile}acq-PA_space-dwi_desc-temp_epi.nii.gz
            fi

            # rigid registration of dwi mean b0 (AP) and PA fieldmap
            antsRegistrationSyN.sh -d 3 -m ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-temp_epi.nii.gz \
                -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz \
                -o ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}rigidreg -t r -n ${threads} -p d
            # apply to multi-volume PA fieldmap
            antsApplyTransforms -d 3 -e 3 -i ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz \
                -r ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz \
                -t ${subj}${sessionfile}rigidreg0GenericAffine.mat \
                -o ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-warped-degibss_epi.nii.gz -v -u int
            rm -f ${workdir}/${subj}${sessionpath}fmap/*rigidreg*
            fslmerge -t ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-temp_epi.nii.gz \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-warped-degibss_epi.nii.gz

            rm ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-warped-degibss_epi.nii.gz \
                ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}*temp*.nii.gz

        fi
        # write TRT to refparams file
        cd ${workdir}/${subj}${sessionpath}fmap
        echo "0 1 0 ${dwi_trt}" >${subj}${sessionfile}acq-APPA_desc-refparams.tsv
        for ((i = 0; i < $(fslnvols ${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz); i++)); do
            echo "0 -1 0 ${total_readout_time}" >>"${subj}${sessionfile}acq-APPA_desc-refparams.tsv"
        done

    elif [ -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-AP_space-dwi_desc-degibss_epi.nii.gz ] &&
        [ -f ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-PA_space-dwi_desc-degibss_epi.nii.gz ]; then

        # merge blip up/down scans for topup (if available)
        echo -e "${BLUE}merge blip up/down scans for topup${NC}"
        fslmerge -t ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz \
            ${workdir}/${subj}${sessionpath}fmap/*degibss_epi.nii.gz
        cd ${workdir}/${subj}${sessionpath}fmap

        refnvols=$(fslnvols ${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz)

        if ((refnvols % 2 == 0)); then
            if ((refnvols == 2)); then
                echo "0 1 0 ${total_readout_time}" >${subj}${sessionfile}acq-APPA_desc-refparams.tsv
                echo "0 -1 0 ${total_readout_time}" >>${subj}${sessionfile}acq-APPA_desc-refparams.tsv
            elif ((refnvols == 4)); then
                echo "0 1 0 ${total_readout_time}" >${subj}${sessionfile}acq-APPA_desc-refparams.tsv
                echo "0 1 0 ${total_readout_time}" >>${subj}${sessionfile}acq-APPA_desc-refparams.tsv
                echo "0 -1 0 ${total_readout_time}" >>${subj}${sessionfile}acq-APPA_desc-refparams.tsv
                echo "0 -1 0 ${total_readout_time}" >>${subj}${sessionfile}acq-APPA_desc-refparams.tsv
            else
                echo -e "${YELLOW}WARNING! number of blip up/down volumes = ${refnvols}${NC}"
                echo -e "${YELLOW}this is currently not supported. Modify the script${NC}"
                exit
            fi
        else
            echo -e "${RED}ERROR! not an even number of volumes of blip up/down volumes${NC}"
            exit
        fi

    else

        echo -e "${RED}ERROR! no fieldmaps avaialble${NC}"
        echo -e "${RED}exiting script${NC}"
        exit
    fi
    rsync -a ${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz \
        ${subj}${sessionfile}acq-APPA_desc-refparams.tsv \
        ${outputdir}/dwi-preproc/${subj}${sessionpath}fmap

    if [ ! -f ${subj}${sessionfile}space-dwi_desc-unwarped_epi.nii.gz ] ||
        [ ! -f ${subj}${sessionfile}space-dwi_desc-topup_fieldcoeff.nii.gz ]; then

        #    https://www.jiscmail.ac.uk/cgi-bin/webadmin?A2=FSL;6c4c9591.2002
        #        b02b0_4.cnf  -- Recommended when the data matrix is an integer multiple of 4 in all direction
        #       b02b0_2.cnf  -- Recommended when the data matrix is an integer multiple of 2 in all direction
        #      b02b0_1.cnf  -- Recommended when the data matrix is odd in one or more directions

        dim3=$(fslinfo ${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz | grep -w dim3 | awk '{ print $2 }' | awk '{print int($0)}')
        if ((dim3 % 4 == 0)); then
            echo "slices are integer multiple of 4; using b02b0_4.cnf for topup"
            configfile=b02b0_4.cnf
        elif ((dim3 % 2 == 0)); then
            echo "slices are integer multiple of 2; using b02b0_2.cnf for topup"
            configfile=b02b0_2.cnf
        else
            echo "odd number of slices; using b02b0_1.cnf as config file for topup"
            configfile=b02b0_1.cnf
        fi

        echo
        echo -e "${BLUE}running topup${NC}"
        topup --imain=${subj}${sessionfile}acq-APPA_space-dwi_desc-4topup_epi.nii.gz \
            --datain=${subj}${sessionfile}acq-APPA_desc-refparams.tsv \
            --config=${configfile} \
            --out=${subj}${sessionfile}space-dwi_desc-topup \
            --iout=${subj}${sessionfile}space-dwi_desc-unwarped_epi \
            --fout=${subj}${sessionfile}space-dwi_desc-topup_fieldmap --verbose >${subj}${sessionfile}topup.log
        cp ${subj}${sessionfile}topup.log ${outputdir}/dwi-preproc/${subj}${sessionpath}logs

    fi
    ###################
    ### round bvals ###
    ###################
    ${scriptdir}/round_bvals.py ${sessiondir}/dwi/${subj}${sessionfile}dwi.bval

    #######################
    ## create brain mask ##
    #######################
    # mean of unwarped image to allow registration
    mrmath ${subj}${sessionfile}space-dwi_desc-unwarped_epi.nii.gz mean \
        ${subj}${sessionfile}space-dwi_desc-nodif_epi.nii.gz -axis 3

    # Get the mean b-zero (un-corrected)
    dwiextract -nthreads ${threads} \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns+degibbs_dwi.nii.gz - -bzero \
        -fslgrad ${sessiondir}/dwi/${subj}${sessionfile}*dwi.bvec ${sessiondir}/dwi/${subj}${sessionfile}dwi.bval |
        mrmath - mean ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-meanb0-uncorrected_dwi.nii.gz -axis 3

    # rigid registration of nodif_epi to b0
    antsRegistrationSyN.sh -d 3 -m ${subj}${sessionfile}space-dwi_desc-nodif_epi.nii.gz \
        -f "${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-meanb0-uncorrected_dwi.nii.gz" \
        -o ${subj}${sessionfile}rigidreg -t r -n ${threads} -p d
    mv ${subj}${sessionfile}rigidregWarped.nii.gz ${subj}${sessionfile}space-dwi_desc-nodif_epi.nii.gz
    rm *rigidreg*

    apptainer run --cleanenv ${synthstrippath} \
        -i ${subj}${sessionfile}space-dwi_desc-nodif_epi.nii.gz \
        --mask ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-brain-uncorrected_mask.nii.gz

    ##########
    ## EDDY ##
    ##########
    cd ${scriptdir}/${subj}

    echo
    echo -e "${BLUE}starting EDDY${NC}"
    echo
    echo "0 1 0 ${dwi_trt}" >${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-DWI_desc-acqparams.tsv

    sbatch --wait --gres=gpu:1g.10gb:1 ${scriptdir}/dwi-02b-eddy.sh \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-dns+degibbs_dwi.nii.gz \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-brain-uncorrected_mask.nii.gz \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-DWI_desc-acqparams.tsv \
        ${sessiondir}/dwi/${subj}${sessionfile}*dwi.bvec \
        ${sessiondir}/dwi/${subj}${sessionfile}*dwi.bval \
        ${sessiondir}/dwi/${subj}${sessionfile}*dwi.json \
        ${workdir}/${subj}${sessionpath}fmap/${subj}${sessionfile}space-dwi_desc-topup \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc \
        default

    cp eddy_*.log ${outputdir}/dwi-preproc/${subj}${sessionpath}logs/${subj}${sessionfile}eddy.log

    # rename output
    mv ${subj}${sessionfile}space-dwi_desc-preproc.eddy_rotated_bvecs \
        ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec
    mv ${subj}${sessionfile}space-dwi_desc-preproc.nii.gz \
        ${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz
    mv ${subj}${sessionfile}space-dwi_desc-preproc.eddy_cnr_maps.nii.gz \
        ${subj}${sessionfile}space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz
    cp ${sessiondir}/dwi/${subj}${sessionfile}*dwi.bval \
        ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval
    mv *.qc eddyqc

    rsync -av ${subj}${sessionfile}space-dwi*_dwi.* ${subj}${sessionfile}space-dwi_desc-brain-uncorrected_mask.nii.gz eddyqc \
        ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi

    # clean-up
    if [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz ] &&
        [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec ] &&
        [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz ]; then
        rm -r ${workdir}/${subj}${sessionpath}
        rm ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/*meanb0* \
            ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/*dns+degibbs*

        echo
        echo -e ${GREEN}FINISHED processing ${subj}${sessionpath}${NC}
        echo

    else
        echo -e "${RED}ERROR! not all output was created successfully${NC}"

    fi

done
