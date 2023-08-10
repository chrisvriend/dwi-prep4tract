#!/bin/bash

#SBATCH --job-name=atlas2FS
#SBATCH --mem=3G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=2
#SBATCH --time=00-0:20:00
#SBATCH --nice=2000
#SBATCH --out=atlas2FS_%A.log

# usage instructions
Usage() {
    cat <<EOF

    (C) C.Vriend - AmsUMC dec 16 2022
    script to warp several standard atlases to subject specific freesurfer space

    Usage: ./Atlas2FreeSurfer.sh <freesurferdir> <subj> 
    Obligatory:
    freesurferdir = full path to freesurfer directory that contains subject's FreeSurfer output
    subj = subject ID
   
	additional options and paths may need to be checked/modified in the script

EOF
    exit 1
}

[ _$2 = _ ] && Usage

# STANDARD ATLAS DIR
atlasdir=/data/anw/anw-gold/NP/doorgeefluik/atlas4FreeSurfer

# source software
module load fsl/6.0.6.5
module load FreeSurfer/7.3.2-centos8_x86_64
module load Anaconda3/2022.05
mrtrix_env=/scratch/anw/share/python-env/mrtrix
conda activate ${mrtrix_env}

#==========================
# INPUTS
#==========================

# FREESURFER DIRECTORY
SUBJECTS_DIR=${1}
# subjects to process
cd ${SUBJECTS_DIR}
export SUBJECTS_DIR
subj=${2}

# extra check because the slurm array sometimes behaves unexpected
if [[ "${subj}" != sub-* ]]; then echo "${subj} is not according to BIDS format; exiting" exit; fi

#=============================================================================
### wARP ATLASES TO FREESURFER SPACE
#=============================================================================

# BRAINNETOME ATLAS

if [[ ! -f ${SUBJECTS_DIR}/${subj}/label/lh.BN_Atlas.annot ]] ||
    [[ ! -f ${SUBJECTS_DIR}/${subj}/label/rh.BN_Atlas.annot ]]; then
    echo "warping cortical BNA to individual FreeSurfer space"
    for hemi in lh rh; do
        # warp cortical regions of atlas to subject
        mris_ca_label -seed 1234 -l ${SUBJECTS_DIR}/${subj}/label/${hemi}.cortex.label \
            ${subj} ${hemi} \
            ${SUBJECTS_DIR}/${subj}/surf/${hemi}.sphere.reg \
            ${atlasdir}/BNA/${hemi}.BN_Atlas.gcs ${SUBJECTS_DIR}/${subj}/label/${hemi}.BN_Atlas.annot

        # extract values to annot file
        mris_anatomical_stats -mgz -cortex ${SUBJECTS_DIR}/${subj}/label/${hemi}.cortex.label \
            -f ${SUBJECTS_DIR}/${subj}/stats/${hemi}.BN_Atlas.stats -b -a ${SUBJECTS_DIR}/${subj}/label/${hemi}.BN_Atlas.annot \
            -c ${atlasdir}/BNA/BNA_labels_orig_wsubcortex.txt ${subj} ${hemi} white

    done

fi
if [[ ! -f ${SUBJECTS_DIR}/${subj}/mri/BN_Atlas_subcortex.mgz ]]; then
    # warp subcortical regions of atlas to subject
    mri_ca_label -threads 2 ${SUBJECTS_DIR}/${subj}/mri/brain.mgz \
        ${SUBJECTS_DIR}/${subj}/mri/transforms/talairach.m3z ${atlasdir}/BNA/BN_Atlas_subcortex.gca \
        ${SUBJECTS_DIR}/${subj}/mri/BN_Atlas_subcortex.mgz
    # extract values to annot file
    mri_segstats --seg ${SUBJECTS_DIR}/${subj}/mri/BN_Atlas_subcortex.mgz \
        --ctab ${atlasdir}/BNA/BNA_labels_orig_wsubcortex.txt --excludeid 0 \
        --sum ${SUBJECTS_DIR}/${subj}/stats/BN_Atlas_subcortex.stats

fi

if [[ ! -f ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.nii.gz ]]; then
    # warp annotation label to mgz file
    mri_aparc2aseg --threads 2 --s ${subj} --annot BN_Atlas --o ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.mgz
    mrconvert ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.mgz ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.nii.gz -force
fi

#=============================================================================
# BUCKNER CEREBELLUM TO FREESURFER SPACE
#=============================================================================
if [[ ! -f ${SUBJECTS_DIR}/${subj}/mri/Buckner2011_atlas.nii.gz ]]; then
    #3. warp the BucknerAtlas1mm_FSI.nii.gz from freesurfer nonlinear volumetric space to each subject:

    mri_vol2vol --mov $SUBJECTS_DIR/${subj}/mri/norm.mgz --s ${subj} \
        --targ ${atlasdir}/cerebellum/BucknerAtlas1mm_FSI.nii.gz --m3z talairach.m3z \
        --o ${SUBJECTS_DIR}/${subj}/mri/Buckner2011_atlas.nii.gz --nearest --inv-morph

fi

if ([[ ! -f ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz ]] ||
    [[ ! -f ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz ]]) &&
    [ ! -f ${SUBJECTS_DIR}/${subj}/mri/Buck_cerebellum.nii.gz ]; then

    #4. Create a cerebellum gray matter mask in the native subject's space by applying mri_binarize to aparc+aseg.mgz of the subject
    # 47 = right, 8 = left
    mri_binarize --i $SUBJECTS_DIR/${subj}/mri/aparc+aseg.mgz --match 8 \
        --o ${SUBJECTS_DIR}/${subj}/mri/cerebellum_mask_left.nii.gz
    mri_binarize --i $SUBJECTS_DIR/${subj}/mri/aparc+aseg.mgz --match 47 \
        --o ${SUBJECTS_DIR}/${subj}/mri/cerebellum_mask_right.nii.gz
    mri_binarize --i $SUBJECTS_DIR/${subj}/mri/aparc+aseg.mgz --match 8 47 \
        --o ${SUBJECTS_DIR}/${subj}/mri/cerebellum_mask.nii.gz

    for hemi in left right; do

        #5. Using this mask to mask the Buckner cerebellum parcellations
        fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner2011_atlas.nii.gz \
            -mas ${SUBJECTS_DIR}/${subj}/mri/cerebellum_mask_${hemi}.nii.gz \
            ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_${hemi}.nii.gz

        float=$(fslstats ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_${hemi}.nii.gz -R | awk '{ print $2}')
        int=${float%.*}
        if test ${int} -lt 1; then
            echo "redo mask creation"
            fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner2011_atlas.nii.gz \
                -mas ${SUBJECTS_DIR}/${subj}/mri/cerebellum_mask_${hemi}.nii.gz \
                ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_${hemi}.nii.gz

        fi
    done

    fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz \
        -add 16000 ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz \
        -add 17000 ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz \
        -thr 16001 ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz \
        -thr 17001 ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz \
        -add ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz \
        ${SUBJECTS_DIR}/${subj}/mri/Buck_cerebellum.nii.gz
    # clean up
    rm ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_left.nii.gz \
        ${SUBJECTS_DIR}/${subj}/mri/Buckner_atlas_mask_right.nii.gz
fi

#=============================================================================
# MAKE HYBRID BNA CEREBELLUM ATLAS
#=============================================================================
if [ ! -f ${SUBJECTS_DIR}/${subj}/mri/BNA+cerebellum+aseg.nii.gz ]; then

    mri_convert ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.mgz ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/cerebellum_mask.nii.gz -binv ${SUBJECTS_DIR}/${subj}/mri/inv_cerebellum_mask.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg.nii.gz -mul ${SUBJECTS_DIR}/${subj}/mri/inv_cerebellum_mask.nii.gz \
        ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg_cortical.nii.gz
    fslmaths ${SUBJECTS_DIR}/${subj}/mri/BNA+aseg_cortical.nii.gz -add ${SUBJECTS_DIR}/${subj}/mri/Buck_cerebellum.nii.gz \
        ${SUBJECTS_DIR}/${subj}/mri/BNA+cerebellum+aseg.nii.gz
fi

#=============================================================================
# Schaefer atlases TO FREESURFER SPACE
#=============================================================================

echo "warping Schaefer aparc to individual FreeSurfer space"
rsync -av --ignore-existing ${FREESURFER_HOME}/subjects/fsaverage ${SUBJECTS_DIR}

for parcel in 300P7N 300P17N 400P7N 400P17N; do
    echo "parcellation = ${parcel}"

    if [[ ${parcel} == "300P7N" ]]; then
        ID="300Parcels_7Networks"
    elif [[ ${parcel} == "300P17N" ]]; then
        ID="300Parcels_17Networks"
    elif [[ ${parcel} == "200P7N" ]]; then
        ID="200Parcels_7Networks"
    elif [[ ${parcel} == "100P7N" ]]; then
        ID="100Parcels_7Networks"
    elif [[ ${parcel} == "400P7N" ]]; then
        ID="400Parcels_7Networks"
    elif [[ ${parcel} == "400P17N" ]]; then
        ID="400Parcels_17Networks"
    else
        echo "error: atlas not found"
        exit
    fi

    if [[ ! -f ${SUBJECTS_DIR}/${subj}/label/lh.${parcel}.annot ]] ||
        [[ ! -f ${SUBJECTS_DIR}/${subj}/label/rh.${parcel}.annot ]]; then

        for hemi in lh rh; do
            mri_surf2surf --srcsubject fsaverage --trgsubject ${subj} --hemi ${hemi} \
                --sval-annot ${atlasdir}/Schaefer/fsaverage/label/${hemi}.Schaefer2018_${ID}_order.annot \
                --tval ${SUBJECTS_DIR}/${subj}/label/${hemi}.${parcel}.annot

        done

    fi
    # convert 2 volume space
    if [ ! -f ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg.mgz ]; then
        mri_aparc2aseg --s ${subj} --o ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg.mgz --annot ${parcel}
    fi
    #=============================================================================
    # MAKE HYBRID 300/400P7N CEREBELLUM ATLAS
    #=============================================================================
    # hybrid atlases
    if [[ ${parcel} == "300P7N" ]] || [[ ${parcel} == "400P7N" ]]; then
        if [ ! -f ${SUBJECTS_DIR}/${subj}/mri/${parcel}+cerebellum+aseg.nii.gz ]; then
            echo "add cerebellar regions to ${parcel}"
            mri_convert ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg.mgz ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg.nii.gz
            fslmaths ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg.nii.gz -mul ${SUBJECTS_DIR}/${subj}/mri/inv_cerebellum_mask.nii.gz \
                ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg_cortical.nii.gz
            fslmaths ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg_cortical.nii.gz \
                -add ${SUBJECTS_DIR}/${subj}/mri/Buck_cerebellum.nii.gz ${SUBJECTS_DIR}/${subj}/mri/${parcel}+cerebellum+aseg.nii.gz
            # clean up
            rm ${SUBJECTS_DIR}/${subj}/mri/${parcel}+aseg_cortical.nii.gz

        fi
    fi
done

# aparc 500
if [[ ! -f ${SUBJECTS_DIR}/${subj}/label/lh.aparc500.annot ]] ||
    [[ ! -f ${SUBJECTS_DIR}/${subj}/label/rh.aparc500.annot ]]; then

    for hemi in lh rh; do
        mri_surf2surf --srcsubject fsaverage --trgsubject ${subj} --hemi ${hemi} \
            --sval-annot ${atlasdir}/aparc500/${hemi}.500.aparc.annot \
            --tval ${SUBJECTS_DIR}/${subj}/label/${hemi}.aparc500.annot

    done

fi
# convert 2 volume space
if [ ! -f ${SUBJECTS_DIR}/${subj}/mri/aparc500+aseg.mgz ]; then
    mri_aparc2aseg --s ${subj} --o ${SUBJECTS_DIR}/${subj}/mri/aparc500+aseg.mgz --annot aparc500
  #  mrconvert ${SUBJECTS_DIR}/${subj}/mri/aparc500+aseg.mgz ${SUBJECTS_DIR}/${subj}/mri/aparc500+aseg.nii.gz -force

fi

echo "--------------------------"
echo "done with subject = ${subj}"
echo "--------------------------"
