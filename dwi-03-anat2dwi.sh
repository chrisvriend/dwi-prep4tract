#!/bin/bash

#SBATCH --job-name=anat2dwi
#SBATCH --mem=8G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=8
#SBATCH --time=00-01:00:00
#SBATCH --nice=2000
#SBATCH --output=anat2dwi_%A.log

###############################################################################
# source software                                                    #
###############################################################################
module load fsl/6.0.6.5
module load FreeSurfer/7.3.2-centos8_x86_64
module load ANTs/2.4.1
module load art
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python-env/mrtrix

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[34m'
NC='\033[0m' # No Color

# Initialize variables
bidsdir=""
outputdir=""
workdir=""
freesurferdir=""
subj=""
scriptdir=""
# input variables
# Parse command line arguments

while getopts ":i:o:f:w:s:c:" opt; do
    case $opt in
    i)
        bidsdir="$OPTARG"
        ;;
    o)
        outputdir="$OPTARG"
        ;;
    f)
        freesurferdir="$OPTARG"
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

#scriptdir=/data/anw/anw-gold/NP/projects/data_chris/Tmult/scripts
synthstrippath=/scratch/anw/share-np/fmridenoiser/synthstrip.1.2.sif
atlasdir=/data/anw/anw-gold/NP/doorgeefluik/atlas4FreeSurfer
threads=8

###############################################################################

##############################
# warp atlases to FreeSurfer
##############################
echo -e "${BLUE}transfer FreeSurfer output to work directory${NC}"
mkdir -p ${workdir}/${subj}

if [[ ! -d ${freesurferdir}/${subj}/mri ]]; then
    echo -e "${RED}FreeSurfer output not available${NC}"
    echo -e "${RED}processing stopped for ${subj}${NC}"
    sleep 1
    exit
fi
rsync -az --ignore-existing ${freesurferdir}/${subj} ${workdir}/${subj}/freesurfer/
export SUBJECTS_DIR=${workdir}/${subj}/freesurfer
mkdir -p ${SUBJECTS_DIR}/${subj}/dwi
echo
echo -e "${BLUE}Warp atlases to FreeSurfer output${NC}"
sbatch --wait ${scriptdir}/atlas2FreeSurfer.sh ${SUBJECTS_DIR} ${subj}
echo
echo -e "${BLUE}continue with anat to dwi registration${NC}"
echo

for dwidir in ${bidsdir}/${subj}/{,ses*/}dwi; do
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

    fi

# check if output already available #
if (( $( ls ${outputdir}/dwi-preproc/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-*_dseg.nii.gz 2>/dev/null | wc -l ) > 0 )); then
echo -e "${GREEN}${subj}${sessionfile} already has atlasses in dwi-space${NC}"
echo -e "...skip...${NC}"
echo
continue 
fi
##---------------------------------##
    mkdir -p "${workdir}/${subj}${sessionpath}dwi"
    mkdir -p "${workdir}/${subj}${sessionpath}anat"
    mkdir -p "${workdir}/${subj}${sessionpath}figures"
    mkdir -p "${workdir}/${subj}/anat"
    mkdir -p "${workdir}/${subj}/figures"
    mkdir -p "${outputdir}/dwi-preproc/${subj}/logs"

    cd ${workdir}/${subj}${sessionpath}

    # assumes that there is only ONE!! FreeSurfer output per subject

    if [ ! -f ${outputdir}/dwi-preproc/${subj}/anat/${subj}_desc-5tt-hsvs_probseg.nii.gz ] ||
        [ ! -f ${outputdir}/dwi-preproc/${subj}/anat/${subj}_desc-gmwm_probseg.nii.gz ] ||
        [ ! -f ${outputdir}/dwi-preproc/${subj}/anat/${subj}_desc-wm_probseg.nii.gz ]; then

        # using T1 from Freesurfer directory
        if [ ! -f ${workdir}/${subj}/anat/${subj}_desc-preproc_T1w.nii.gz ] ||
            [ ! -f ${workdir}/${subj}/anat/${subj}_desc-brain_T1w.nii.gz ]; then

            rsync -azv --ignore-existing \
                ${freesurferdir}/${subj}/mri/T1.mgz \
                ${freesurferdir}/${subj}/mri/brain.mgz \
                ${workdir}/${subj}/anat

            cd ${workdir}/${subj}/anat
            # convert to nii.gz
            mri_convert --in_type mgz --out_type nii \
                --out_orientation RAS brain.mgz ${subj}_desc-brain_T1w.nii.gz
            mri_convert --in_type mgz --out_type nii \
                --out_orientation RAS T1.mgz ${subj}_desc-preproc_T1w.nii.gz
            # binarize
            fslmaths ${subj}_desc-brain_T1w.nii.gz -bin ${subj}_desc-brain_mask.nii.gz
            rm T1.mgz brain.mgz

            # check overay
            slicer ${subj}_desc-brain_T1w.nii.gz ${subj}_desc-brain_T1w.nii.gz \
                -a ${workdir}/${subj}/figures/${subj}_BETQC.png
        fi
        if [ ! -f ${workdir}/${subj}/anat/${subj}_desc-5tt-hsvs_probseg.nii.gz ]; then
            # review settings
            echo -e "${YELLOW}Prepare 5TT estimation${NC}"
            5ttgen hsvs ${workdir}/${subj}/freesurfer/${subj} \
                ${subj}_5TThsvs.nii.gz \
                -hippocampi aseg -thalami aseg -white_stem -nthreads ${threads} \
                -nocrop -nocleanup -scratch ${workdir}/${subj}/temp_5ttgen -force
            rm ${subj}_5TThsvs.nii.gz
            ${scriptdir}/modify_5ttgen.sh ${workdir}/${subj}/temp_5ttgen ${workdir}/${subj}/freesurfer/ ${subj}
            mv ${workdir}/${subj}/temp_5ttgen/${subj}_5TThsvs.nii.gz ${workdir}/${subj}/anat/${subj}_desc-5tt-hsvs_probseg.nii.gz
            rm -r ${workdir}/${subj}/temp_5ttgen
        fi
        cd ${workdir}/${subj}/anat
        if [ ! -f ${workdir}/${subj}/anat/${subj}_desc-gmwm_probseg.nii.gz ]; then

            5tt2gmwmi ${subj}_desc-5tt-hsvs_probseg.nii.gz ${subj}_desc-gmwm_probseg.nii.gz \
                -nthreads ${threads} -info -force
        fi
        # reorient to FSL RAS
        fslreorient2std ${subj}_desc-5tt-hsvs_probseg.nii.gz ${subj}_desc-5tt-hsvs_probseg.nii.gz
        fslreorient2std ${subj}_desc-gmwm_probseg.nii.gz ${subj}_desc-gmwm_probseg.nii.gz

        # used in BBR to speed up and prevent NaN errors
        fslroi ${subj}_desc-5tt-hsvs_probseg.nii.gz \
            ${subj}_desc-wm_probseg.nii.gz 2 1

        # transfer from work directory to output directory
        rsync -a *.nii.gz ${outputdir}/dwi-preproc/${subj}/anat

    fi

    ###########################
    # T1 to DWI registration
    ###########################

    rsync -a ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc* \
        ${workdir}/${subj}${sessionpath}dwi
    rsync -a --ignore-existing ${outputdir}/dwi-preproc/${subj}/anat/* ${workdir}/${subj}/anat

    if [ -d ${outputdir}/dwi-preproc/${subj}${sessionpath}xfms ]; then
        rsync -a ${outputdir}/dwi-preproc/${subj}${sessionpath}xfms ${workdir}/${subj}${sessionpath}
    fi
    cd ${workdir}/${subj}${sessionpath}dwi

    # create mean b0 (nodif)
    if [ ! -f ${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz ] ||
        [ ! -f ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz ]; then
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

    mkdir -p ${workdir}/${subj}${sessionpath}xfms

    if [ ! -f ${workdir}/${subj}${sessionpath}xfms/${subj}${sessionfile}epireg.mat ] ||
        [ ! -f ${workdir}/${subj}${sessionpath}xfms/${subj}${sessionfile}epireg_inversed.mat ]; then
        echo -e "${BLUE}anat to DWI registration${NC}"

        # ants better?

        flirt -in ${workdir}/${subj}/anat/${subj}_desc-brain_T1w.nii.gz \
            -ref ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
            -omat ${workdir}/${subj}${sessionpath}xfms/T1w-2-diff.mat \
            -searchrx -90 90 -searchry -90 90 -searchrz -90 90 \
            -dof 6 -cost corratio

        convert_xfm -omat ${workdir}/${subj}${sessionpath}xfms/diff-2-T1w.mat \
            -inverse ${workdir}/${subj}${sessionpath}xfms/T1w-2-diff.mat

        epi_reg --epi=${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
            --t1=${workdir}/${subj}/anat/${subj}_desc-preproc_T1w.nii.gz \
            --t1brain=${workdir}/${subj}/anat/${subj}_desc-brain_T1w.nii.gz \
            --wmseg=${workdir}/${subj}/anat/${subj}_desc-wm_probseg.nii.gz \
            --out=${workdir}/${subj}${sessionpath}xfms/${subj}${sessionfile}epireg

        convert_xfm -omat ${workdir}/${subj}${sessionpath}xfms/${subj}${sessionfile}epireg_inversed.mat \
            -inverse ${workdir}/${subj}${sessionpath}xfms/${subj}${sessionfile}epireg.mat

    fi
    
    if [ ! -f ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-5tt-hsvs_probseg.nii.gz ] ||
        [ ! -f ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-gmwm_probseg.nii.gz ]; then

        for label in 5tt-hsvs gmwm; do
            echo -e "${BLUE}warp ${label} to DWI-space${NC}"
            flirt -in ${workdir}/${subj}/anat/${subj}_desc-${label}_probseg.nii.gz \
                -ref ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz -applyxfm \
                -init ${workdir}/${subj}${sessionpath}xfms/${subj}${sessionfile}epireg_inversed.mat \
                -out ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-${label}_probseg.nii.gz -interp nearestneighbour

            #mrconvert ${workdir}/${subj}${sessionpath}/dwi/${subj}_space-dwi_desc-${label}_probseg.nii.gz \
            #${workdir}/${subj}${sessionpath}/dwi/${subj}_space-dwi_desc-${label}_probseg.mif
        done

    fi

    # QA
    if [ ! -f ${outputdir}/dwi-preproc/${subj}${sessionpath}figures/${subj}${sessionfile}5tt-overlay.png ]; then
        5tt2vis ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-5tt-hsvs_probseg.nii.gz \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}5ttvis.mif
        mrview ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}5ttvis.mif \
            -capture.prefix ${subj}_5tt- \
            -noannot -mode 2 -capture.grab -exit
        mv ${subj}_5tt-*.png ${outputdir}/dwi-preproc/${subj}${sessionpath}figures/${subj}${sessionfile}5tt-overlay.png
        rm ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}5ttvis.mif
    fi
    # mask fit
    if [ ! -f ${outputdir}/dwi-preproc/${subj}${sessionpath}figures/${subj}${sessionfile}maskQC.png ]; then
        slicer ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
            -A 2000 ${outputdir}/dwi-preproc/${subj}${sessionpath}figures/${subj}${sessionfile}maskQC.png
    fi

    # transfer to output directory
    mkdir -p ${outputdir}/dwi-preproc/${subj}/anat
    mkdir -p ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/
    rsync -a ${workdir}/${subj}/anat/* ${outputdir}/dwi-preproc/${subj}/anat
    rsync -a ${workdir}/${subj}${sessionpath}xfms ${outputdir}/dwi-preproc/${subj}${sessionpath}

    # gmwm hsvs do not exist?

    rsync -a ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-gmwm_probseg.nii.gz \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-5tt-hsvs_probseg.nii.gz \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
        ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz \
        ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/

    ##################################
    # FREESURFER to DWI registration
    ##################################
    if [ ! -f ${SUBJECTS_DIR}/${subj}/dwi/${subj}${sessionfile}register.dat ]; then
        bbregister --s ${subj} \
            --mov ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
            --init-best --reg ${SUBJECTS_DIR}/${subj}/dwi/${subj}${sessionfile}register.dat --dti
    fi

    # warp atlases to dwi space
    for atlas in BNA 300P7N 300P17N 400P7N 400P17N aparc500; do

                if [[ ${atlas} == "300P7N" ]]; then
                    ID="Schaefer_300P7N"
                elif [[ ${atlas} == "300P17N" ]]; then
                    ID="Schaefer_300P17N"
                elif [[ ${atlas} == "400P7N" ]]; then
                    ID="Schaefer_400P7N"
                elif [[ ${atlas} == "400P17N" ]]; then
                    ID="Schaefer_400P17N"
                elif [[ ${atlas} == "200P7N" ]]; then
                    ID="Schaefer_200P7N"
                elif [[ ${atlas} == "100P7N" ]]; then
                    ID="Schaefer_100P7N"
                elif [[ ${atlas} == "aparc500" ]]; then
                    ID="aparc500_labels"
                elif [[ ${atlas} == "BNA" ]]; then
                    ID="BNA_labels"
                elif [[ ${atlas} == "BNA+cerebellum" ]]; then
                    ID="BNA+CER_labels"
                else
                    echo "atlas not found!"
                    exit
                fi

        if [ ! -f ${SUBJECTS_DIR}/${subj}/mri/${atlas}+aseg.mgz ]; then
            echo
            echo -e "${YELLOW}WARNING! atlas: ${atlas} - not available in FreeSurfer directory of ${subj}${NC}"
            continue
        else

            if [ ! -f ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_dseg.nii.gz ]; then

                # register atlas to DWI
                mri_vol2vol --mov ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
                    --targ ${SUBJECTS_DIR}/${subj}/mri/${atlas}+aseg.mgz \
                    --o ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_temp.nii.gz \
                    --reg ${SUBJECTS_DIR}/${subj}/dwi/${subj}${sessionfile}register.dat --inv --no-save-reg --interp nearest


                if [[ ${ID} != *"Schaefer"* ]]; then
                    # convert and sort labels
                    labelconvert ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_temp.nii.gz \
                        ${atlasdir}/${atlas}/${ID}_orig.txt \
                        ${atlasdir}/${atlas}/${ID}_modified.txt \
                        ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_dseg.nii.gz -force
                else
                    labelconvert ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_temp.nii.gz \
                        ${atlasdir}/Schaefer/${ID}_orig.txt \
                        ${atlasdir}/Schaefer/${ID}_modified.txt \
                        ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_dseg.nii.gz -force
                fi

              rm ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_temp.nii.gz

            fi

        fi

        # QC registration of atlas to dwi
        ${scriptdir}/check_atlasreg.py \
            --subjid ${subj}${sessionfile} \
            --atlas ${atlas} \
            --atlas_image ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_dseg.nii.gz \
            --nodif ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
            --output ${outputdir}/dwi-preproc/${subj}${sessionpath}figures

        fslstats -K ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_dseg.nii.gz \
            ${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc-nodif_dwi.nii.gz \
            -V >roivols.txt
        # delete line with Unknown and print columns 1 and 2

        if [[ ${ID} != *"Schaefer"* ]]; then
            labelfile=${atlasdir}/${atlas}/${ID}_modified.txt
        else
            labelfile=${atlasdir}/Schaefer/${ID}_modified.txt
        fi
        grep -v "Unknown" ${labelfile} | awk '{ print $1,$2 }' >labels.txt
        paste labels.txt roivols.txt >${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas-${atlas}_roivols.txt
        rm roivols.txt labels.txt

        # NEED TO CHECK THIS!
        # echo "check roi volumes  ${atlas}"
        # ${scriptdir}/check_roivols_luna.py -subjid ${subj} -atlas ${atlas} \
        # -file ${workdir}/QC/${subjbase}_${atlas}_roivols.txt

    done

    # transfer files
    rsync -av ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas* \
        ${outputdir}/dwi-preproc/${subj}${sessionpath}anat/
    rsync -av --ignore-existing ${SUBJECTS_DIR}/${subj} ${freesurferdir}

done

# clean up
chmod -R u+w ${workdir}/${subj}/freesurfer/fsaverage
rm -rf ${workdir}/${subj}

echo "-----------------------------------"
echo "finished anat2dwi subject = ${subj}"
echo "-----------------------------------"
