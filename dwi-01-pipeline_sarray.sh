#!/bin/bash 


# (C) C. Vriend - Aumc ANW/Psy - June '23
# c.vriend@amsterdamumc.nl

# dwi preprocessing and tractography pipeline using slurm arrays to process multiple subjects in parallel (called by dwi-00-launch_sarray.sh )
# CV - update Jul '25 - implemented slurm 'afterok'

#################
# tree of outputs
#################
# derivatives
# │
# ├── dwi-connectome
# │   └── sub-[subjID]_[sessionID]
# │       ├── conn
# │       │   ├── sub-[subjID]_[sessionID]_atlas-300P7N_desc-FA_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-300P7N_desc-lengths_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-300P7N_desc-ndi_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-300P7N_desc-streams_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-300P7N_trackassign.txt
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P17N_desc-FA_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P17N_desc-lengths_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P17N_desc-ndi_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P17N_desc-streams_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P17N_trackassign.txt
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P7N_desc-FA_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P7N_desc-lengths_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P7N_desc-ndi_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P7N_desc-streams_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-400P7N_trackassign.txt
# │       │   ├── sub-[subjID]_[sessionID]_atlas-aparc500_desc-FA_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-aparc500_desc-lengths_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-aparc500_desc-ndi_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-aparc500_desc-streams_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-aparc500_trackassign.txt
# │       │   ├── sub-[subjID]_[sessionID]_atlas-BNA_desc-FA_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-BNA_desc-lengths_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-BNA_desc-ndi_connmatrix.csv
# │       │   ├── sub-[subjID]_[sessionID]_atlas-BNA_desc-streams_connmatrix.csv
# │       │   └── sub-[subjID]_[sessionID]_atlas-BNA_trackassign.txt
# │       ├── dwi
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-sift-50M_stats.csv
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_mu.txt
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_tracto-50M_desc-sift_weights.txt
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_tracto-50M-sift_dwi.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_tracto-50M.tck
# │       │   └── sub-[subjID]_[sessionID]_tissue-WM-norm_fod.nii.gz
# │       ├── figures
# │       │   ├── sub-[subjID]_[sessionID]_siftoverlay3D.png
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_tissue-overlay.png
# │       │   └── sub-[subjID]_[sessionID]_space-dwi_tractoverlay.png
# │       ├── logs
# │       │   └── sub-[subjID]_[sessionID]_dwi-tckconn.log
# │       └── rpf
# │           ├── sub-[subjID]_[sessionID]_space-dwi_tissue-CSF_response.txt
# │           ├── sub-[subjID]_[sessionID]_space-dwi_tissue-GM_response.txt
# │           └── sub-[subjID]_[sessionID]_space-dwi_tissue-WM_response.txt
# ├── dwi-preproc
# │   └── sub-[subjID]_[sessionID]
# │       ├── anat
# │       │   ├── sub-[subjID]_[sessionID]_desc-5tt-hsvs_probseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_desc-brain_mask.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_desc-brain_T1w.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_desc-gmwm_probseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_desc-preproc_T1w.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_desc-wm_probseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-300P7N_dseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-300P7N_roivols.txt
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-400P17N_dseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-400P17N_roivols.txt
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-400P7N_dseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-400P7N_roivols.txt
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-aparc500_dseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-aparc500_roivols.txt
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_atlas-BNA_dseg.nii.gz
# │       │   └── sub-[subjID]_[sessionID]_space-dwi_atlas-BNA_roivols.txt
# │       ├── dwi
# │       │   ├── eddyqc
# │       │   │   ├── avg_b0_pe0.png
# │       │   │   ├── avg_b0.png
# │       │   │   ├── avg_b1000.png
# │       │   │   ├── avg_b2000.png
# │       │   │   ├── avg_b3000.png
# │       │   │   ├── cnr0000.nii.gz.png
# │       │   │   ├── cnr0001.nii.gz.png
# │       │   │   ├── cnr0002.nii.gz.png
# │       │   │   ├── cnr0003.nii.gz.png
# │       │   │   ├── qc.json
# │       │   │   ├── qc.pdf
# │       │   │   ├── ref_list.png
# │       │   │   ├── ref.txt
# │       │   │   └── vdm.png
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-5tt-hsvs_probseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-brain_mask.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-brain-uncorrected_mask.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-gmwm_probseg.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-isovf_noddi.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-ndi_noddi.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-nodif-brain_dwi.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-nodif_dwi.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-odi_noddi.nii.gz
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-preproc_dwi.bval
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-preproc_dwi.bvec
# │       │   ├── sub-[subjID]_[sessionID]_space-dwi_desc-preproc_dwi.nii.gz
# │       │   └── sub-[subjID]_[sessionID]_space-dwi_label-cnr-maps_desc-preproc_dwi.nii.gz
# │       ├── figures
# │       │   ├── sub-[subjID]_[sessionID]_label-300P7N_overlay.png
# │       │   ├── sub-[subjID]_[sessionID]_label-400P17N_overlay.png
# │       │   ├── sub-[subjID]_[sessionID]_label-400P7N_overlay.png
# │       │   ├── sub-[subjID]_[sessionID]_label-aparc500_overlay.png
# │       │   ├── sub-[subjID]_[sessionID]_label-BNA_overlay.png
# │       │   └── sub-[subjID]_[sessionID]_maskQC.png
# │       ├── fmap
# │       │   ├── sub-[subjID]_[sessionID]_acq-APPA_desc-refparams.tsv
# │       │   └── sub-[subjID]_[sessionID]_acq-APPA_space-dwi_desc-4topup_epi.nii.gz
# │       ├── logs
# │       │   ├── sub-[subjID]_[sessionID]_dwi-anat2dwi.log
# │       │   ├── sub-[subjID]_[sessionID]_dwi-noddi.log
# │       │   ├── sub-[subjID]_[sessionID]_dwi-preproc.log
# │       │   ├── sub-[subjID]_[sessionID]_eddy.log
# │       │   └── sub-[subjID]_[sessionID]_topup.log
# │       └── xfms
# │           ├── diff-2-T1w.mat
# │           ├── sub-[subjID]_[sessionID]_epireg_fast_wmedge.nii.gz
# │           ├── sub-[subjID]_[sessionID]_epireg_fast_wmseg.nii.gz
# │           ├── sub-[subjID]_[sessionID]_epireg_init.mat
# │           ├── sub-[subjID]_[sessionID]_epireg_inversed.mat
# │           ├── sub-[subjID]_[sessionID]_epireg.mat
# │           ├── sub-[subjID]_[sessionID]_epireg.nii.gz
# │           └── T1w-2-diff.mat


# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[34m'
NC='\033[0m' # No Color

# Initialize variables
nstreamlines=50M
bidsdir=""
outputdir=""
workdir=""
freesurferdir=""
subj=""
noddi=""
scriptdir=""
# Parse command line arguments
while getopts ":i:o:f:w:j:n:c:" opt; do
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
    n)
        noddi="$OPTARG"   
        ;;
    j)
        subjects="$OPTARG"
        ;;
    c)
        scriptdir="$OPTARG"
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        ;;
    esac
done

# SLURM ARRAY INPUTS 
subj=$(sed -n "${SLURM_ARRAY_TASK_ID}p" ${subjects})
# Random delay
duration=$((RANDOM % 40 + 2))
echo -e "${YELLOW}INITIALIZING...(wait a sec)${NC}"
echo
sleep ${duration}

mkdir -p ${workdir}
mkdir -p ${scriptdir}/${subj}
cd ${scriptdir}/${subj}

###########################
##  DWI-PREPROCESSING    ##
###########################
echo
echo -e "${BLUE}Preprocessing ${subj}${NC}"
echo
job_id_preproc=$(sbatch ${scriptdir}/dwi-02a-preproc.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} -s ${subj} -c ${scriptdir} | awk '{print $4}')
echo "Submitted preprocessing job with ID: $job_id_preproc"
sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" *preproc_*.log >> ${outputdir}/dwi-preproc/${subj}/logs/${subj}_dwi-preproc.log

###########################
##      DWI - NODDI      ##
###########################
if [[ ${noddi} == 1 ]]; then 
    echo
    echo -e "${BLUE}Performing NODDI${NC}"
    echo
    job_id_noddi=$(sbatch --dependency=afterok:$job_id_preproc ${scriptdir}/dwi-02c-prep4noddi.sh -w ${workdir} -o ${outputdir} -s ${subj} -c ${scriptdir} | awk '{print $4}')
    echo "Submitted NODDI job with ID: $job_id_noddi"
    sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" *noddi_*.log >> ${outputdir}/dwi-preproc/${subj}/logs/${subj}_dwi-noddi.log
fi

###########################
## DWI-2-T1 registration ##
###########################
echo
echo -e "${BLUE}Anat-2-DWI registration${NC}"
echo
job_id_anat2dwi=$(sbatch --dependency=afterok:${job_id_noddi:-$job_id_preproc} ${scriptdir}/dwi-03-anat2dwi.sh -i ${bidsdir} -o ${outputdir} -f ${freesurferdir} -w ${workdir} -s ${subj} -c ${scriptdir} | awk '{print $4}')
echo "Submitted Anat-2-DWI registration job with ID: $job_id_anat2dwi"
sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" *anat2dwi*.log > ${outputdir}/dwi-preproc/${subj}/logs/${subj}_dwi-anat2dwi.log

###########################
##   DWI-TRACTOGRAPHY    ##
###########################
echo
echo -e "${BLUE}DWI FOD + Tractogram${NC}"
echo
job_id_fodtck=$(sbatch --dependency=afterok:$job_id_anat2dwi ${scriptdir}/dwi-04a-connectome.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} -s ${subj} -c ${scriptdir} | awk '{print $4}')
echo "Submitted FOD + Tractogram job with ID: $job_id_fodtck"
sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" *fod+tck*.log > ${outputdir}/dwi-connectome/${subj}/logs/${subj}_dwi-fodtck.log

echo -e "${BLUE}DWI Tract - 2 - Connectome${NC}"
job_id_tck2conn=$(sbatch --dependency=afterok:$job_id_fodtck ${scriptdir}/dwi-04b-tracts2conn_v2.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} -s ${subj} -n ${nstreamlines} | awk '{print $4}')
echo "Submitted Tract-to-Connectome job with ID: $job_id_tck2conn"
sed -E "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" *tck2conn*.log > ${outputdir}/dwi-connectome/${subj}/logs/${subj}_dwi-tckconn.log

###########################
##   DWI-AUTOTRACT    ##
###########################

# pending 

#rm ${bidsdir}/${subj}/*.log
