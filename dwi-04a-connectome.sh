#!/bin/bash

#SBATCH --job-name=dwi-fod-tck
#SBATCH --mem=12G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=16
#SBATCH --time=00-04:00:00
#SBATCH --nice=2000
#SBATCH --output=dwi-fod+tck_%A.log

Usage() {
  cat <<EOF

    (C) C.Vriend - Amsterdam UMC - May 24 2023 
    creates 5TT file for MRTRIX3 and performs tractography
    Usage: ./MRTRIX_connectome_v3.sh JobName DWI tar-file
    JobName = subject ID
    DWI tar-file = filename of tar file with the DWI data (as data.nii.gz), nodif*, bvecs and bvals files

EOF
  exit 1
}

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
subj=""
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

nstreamlines=50M
threads=16

###############################################################################
# source software                                                    #
###############################################################################
module load fsl/6.0.6.5
module load FreeSurfer/7.3.2-centos8_x86_64
module load ANTs/2.4.1
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python-env/mrtrix
export PATH=${PATH}:/scratch/anw/share/python-env/mrtrix/MRtrix3Tissue/bin

###############################################################################

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
  if (($(ls ${outputdir}/dwi-preproc/${subj}${sessionpath}anat/${subj}${sessionfile}space-dwi_atlas* 2>/dev/null | wc -l) == 0)); then
    echo -e "${RED}${subj}${sessionfile} has no atlases asoutput"
    echo -e "did anat2dwi fail / no FreeSurfer output available?"
    echo -e "aborting ${NC}"
    continue
  fi

  # check if output already available #
  if [ -f ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}tissue-WM-norm_fod.nii.gz ] &&
    [ -f ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt ] &&
    [ -f ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_tracto-${nstreamlines}.tck ] &&
    (($(ls ${outputdir}/dwi-connectome/${subj}${sessionpath}conn/${subj}${sessionfile}atlas-*_desc-*_connmatrix.csv 2>/dev/null | wc -l) > 0)); then
    echo -e "${GREEN}${subj}${sessionfile} already has tractogram, sift and >1 conn matrix${NC}"
    echo -e "...skip...${NC}"
    echo
    continue
  fi
  ##---------------------------------##

  mkdir -p "${workdir}/${subj}/${sessionpath}dwi"

  for folder in dwi figures logs; do
    mkdir -p "${outputdir}/dwi-connectome/${subj}${sessionpath}/${folder}"
  done

  rsync -a ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}space-dwi_desc* \
    ${workdir}/${subj}${sessionpath}dwi

  # in case there is a previous run

  if (($(ls ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}* 2>/dev/null | wc -l) > 0)); then
    rsync -a ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}* \
      ${outputdir}/dwi-connectome/${subj}${sessionpath}rpf/* \ 
    ${workdir}/${subj}${sessionpath}dwi
  fi

  ####################
  # BIAS CORRECTION
  ####################

  cd ${workdir}/${subj}${sessionpath}dwi
  mrconvert ${subj}${sessionfile}space-dwi_desc-preproc_dwi.nii.gz \
    -fslgrad ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval \
    ${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif

  # BIAS CORRECTION

  if [ ! -f ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif ]; then

    dwibiascorrect ants ${subj}${sessionfile}space-dwi_desc-preproc_dwi.mif \
      ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif -nthreads ${threads} \
      -bias ${subj}${sessionfile}space-dwi_desc-biasest_dwi.mif \
      -scratch ${workdir}/${subj}/tempbiascorrect
    #-fslgrad ${subj}${sessionfile}space-dwi_desc-preproc_dwi.bvec \
    #${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval

  fi

  # dilate/erode brain mask
  for manipulation in dilate erode; do
    maskfilter -npass 2 ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
      ${manipulation} ${subj}${sessionfile}space-dwi_desc-brain-${manipulation}d_mask.mif \
      -nthreads ${threads} -info
  done

  ###############################################################################
  # USE AVERAGE RESPONSE FUNCTIONs                                                 #
  ###############################################################################
  # not available/implemented
  # wm_response=${rfdir}/${site}/group_average_response_wm.txt
  # gm_response=${rfdir}/${site}/group_average_response_gm.txt
  # csf_response=${rfdir}/${site}/group_average_response_csf.txt

  # calculate subject-specific response functions

  # determine whether it is single or multishell
  read -r line <${subj}${sessionfile}space-dwi_desc-preproc_dwi.bval
  # Split the line into an array of values
  IFS=" " read -ra values <<<"$line"
  # Filter out values greater than 0 and keep only unique values
  unique_values=$(printf "%s\n" "${values[@]}" | awk '$1 > 0' | sort -u)
  # Count the number of shells
  Nshells=$(echo "$unique_values" | wc -w)

  unset shells
  # Iterate over the b-values to identify the unique shells
  for value in "${values[@]}"; do
    # Check if the value is greater than 0
    if (($(echo "$value > 0" | bc -l))); then
      # Add the value to the unique_values variable if it's not already present
      if ! [[ "$shells" =~ (^|,)"$value"($|,) ]]; then
        if [[ -z "$shells" ]]; then
          shells="$value"
        else
          shells="$shells,$value"
        fi
      fi
    fi
  done

  if ((Nshells == 1)); then
    echo
    echo -e ${BLUE}"Estimate response functions - dhollander${NC}"
    echo
    dwi2response dhollander ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif \
      ${subj}${sessionfile}space-dwi_tissue-WM_response.txt \
      ${subj}${sessionfile}space-dwi_tissue-GM_response.txt \
      ${subj}${sessionfile}space-dwi_tissue-CSF_response.txt \
      -nthreads ${threads} -scratch ${workdir}/${subj}/tempdwiresponse

    # MRtrix3tissue is a separate tool from mrtrix3 (compliments of Tommy Broeders ;
    # https://3tissue.github.io/doc/ss3t-csd.html)
    echo
    echo -e ${BLUE}"Spherical Deconvolution - ss3t ${NC}"
    echo
    ss3t_csd_beta1 ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif \
      ${subj}${sessionfile}space-dwi_tissue-WM_response.txt ${subj}${sessionfile}FOD-wm.mif \
      ${subj}${sessionfile}space-dwi_tissue-GM_response.txt ${subj}${sessionfile}FOD-gm.mif \
      ${subj}${sessionfile}space-dwi_tissue-CSF_response.txt ${subj}${sessionfile}FOD-csf.mif \
      -mask ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz
    # use non-dilated mask
    #      -mask ${subj}${sessionfile}space-dwi_desc-brain-dilated_mask.mif

    # alternative based on mrtrix3_connectome
    # dwi2fod msmt_csd ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif \
    #   ${subj}${sessionfile}space-dwi_tissue-WM_response.txt ${subj}${sessionfile}FOD-wm.mif \
    #   ${subj}${sessionfile}space-dwi_tissue-CSF_response.txt ${subj}${sessionfile}FOD-csf.mif \
    #   -mask ${subj}${sessionfile}space-dwi_desc-brain-dilated_mask.mif \
    #   -shell 0,${shells} -nthreads ${threads}

  elif ((Nshells > 1)); then
    # msmt
    if [ ! -f ${subj}${sessionfile}space-dwi_tissue-WM_response.txt ] ||
      [ ! -f ${subj}${sessionfile}space-dwi_tissue-GM_response.txt ] ||
      [ ! -f ${subj}${sessionfile}space-dwi_tissue-CSF_response.txt ]; then
      echo
      echo -e "${BLUE}estimate response functions - msmt${NC}"
      echo
      dwi2response msmt_5tt \
        ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif \
        ${subj}${sessionfile}space-dwi_desc-5tt-hsvs_probseg.nii.gz \
        ${subj}${sessionfile}space-dwi_tissue-WM_response.txt \
        ${subj}${sessionfile}space-dwi_tissue-GM_response.txt \
        ${subj}${sessionfile}space-dwi_tissue-CSF_response.txt \
        -shell 0,${shells} -mask ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
        -nthreads ${threads} -scratch ${workdir}/${subj}/tempdwiresponse
      rm -rf ${workdir}/${subj}/tempdwiresponse
    fi

    if [ ! -f ${subj}${sessionfile}FOD-wm.mif ] ||
      [ ! -f ${subj}${sessionfile}FOD-gm.mif ] ||
      [ ! -f ${subj}${sessionfile}FOD-csf.mif ]; then
      # in the absence of a group average response function use subject-specific
      echo
      echo -e ${BLUE}"Spherical Deconvolution - msmt csd ${NC}"
      echo
      dwi2fod msmt_csd ${subj}${sessionfile}space-dwi_desc-preproc-biascor_dwi.mif \
        ${subj}${sessionfile}space-dwi_tissue-WM_response.txt ${subj}${sessionfile}FOD-wm.mif \
        ${subj}${sessionfile}space-dwi_tissue-GM_response.txt ${subj}${sessionfile}FOD-gm.mif \
        ${subj}${sessionfile}space-dwi_tissue-CSF_response.txt ${subj}${sessionfile}FOD-csf.mif \
        -mask ${subj}${sessionfile}space-dwi_desc-brain-dilated_mask.mif \
        -shell 0,${shells} -nthreads ${threads}
    fi
  fi

  echo
  echo -e "${BLUE}Multi-tissue informed log-domain intensity normalisation${NC}"
  echo
  mtnormalise ${subj}${sessionfile}FOD-wm.mif ${subj}${sessionfile}FOD-wm-norm.mif \
    ${subj}${sessionfile}FOD-gm.mif ${subj}${sessionfile}FOD-gm-norm.mif \
    ${subj}${sessionfile}FOD-csf.mif ${subj}${sessionfile}FOD-csf-norm.mif \
    -mask ${subj}${sessionfile}space-dwi_desc-brain-eroded_mask.mif \
    -nthreads ${threads} -force

  # for visualisation | generates a 4D image with 3 volumes,
  # corresponding to the tissue densities of CSF, GM and WM,
  # which will then be displayed in mrview as an RGB image with CSF as red,
  # GM as green and WM as blue (as was presented in the MSMT CSD manuscript).
  mrconvert ${subj}${sessionfile}FOD-wm.mif - -coord 3 0 | mrcat ${subj}${sessionfile}FOD-csf.mif ${subj}${sessionfile}FOD-gm.mif - ${subj}${sessionfile}space-dwi_tissue-RGB.mif -axis 3

  mrview -noannotation \
    -size 1200,1200 \
    -config MRViewOrthoAsRow 1 \
    -config MRViewDockFloating 1 \
    -config MRViewOdfScale 8 \
    -mode 2 \
    -load ${subj}${sessionfile}space-dwi_tissue-RGB.mif \
    -odf.load_sh ${subj}${sessionfile}FOD-wm.mif \
    -capture.prefix ${subj}${sessionfile}space-dwi_tissue- \
    -capture.grab -exit
  mv ${subj}${sessionfile}space-dwi_tissue-*.png \
    ${outputdir}/dwi-connectome/${subj}${sessionpath}figures/${subj}${sessionfile}space-dwi_tissue-overlay.png

  ###############################################################################
  # DWI STREAMLINE TRACTOGRAPHY                                                 #
  ###############################################################################

  # since the propagation and termination of streamlines is
  #primarily handled by the 5TT image, it is no longer necessary to provide a mask
  #using the -mask option. In fact, for whole-brain tractography,
  #it is recommend that you _not_ provide such an image when using ACT:
  #depending on the accuracy of the DWI brain mask, its inclusion may only cause erroneous
  #termination of streamlines inside the white matter due to exiting this mask. ( -mask ###)

  # 6/5/20 changed from wmfod --> wmfod_norm + added backtrack and crop_at_gmwmi
  # -backtrack allow tracks to be truncated and
  #re-tracked if a poor structural termination is encountered
  # -crop_at_gmwmi crop streamline endpoints more precisely as they cross the GM-WM interface

  # 12/6/22 using seed_gmwmi, cutoff 0.1 and 50M streamlines based on Tim's work

  if [ ! -f ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}.tck ]; then
    echo
    echo "${BLUE}start tractography${NC}"
    echo
    tckgen ${subj}${sessionfile}FOD-wm-norm.mif \
      ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}.tck \
      -seed_gmwmi ${subj}${sessionfile}space-dwi_desc-gmwm_probseg.nii.gz \
      -act ${subj}${sessionfile}space-dwi_desc-5tt-hsvs_probseg.nii.gz \
      -maxlength 250 \
      -cutoff 0.1 \
      -seeds ${nstreamlines} \
      -select 0 \
      -nthreads ${threads} \
      -info
    # either start tracking 50M tracts, regardless of reaching its goal
    # or select a total of 50M tracts
  #  -select 50M
  #  -seeds 50M

  fi

  # to aid visualization
  tckedit ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}.tck \
    ${subj}${sessionfile}space-dwi_tracto-100k.tck -number 100k

  mrview -noannotation -size 1200,1200 \
    -config MRViewOrthoAsRow 1 \
    -config MRViewDockFloating 1 \
    -mode 2 \
    -load ${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz -tractography.load ${subj}${sessionfile}space-dwi_tracto-100k.tck \
    -capture.prefix temp -capture.grab -exit
  mv temp*.png \
    ${outputdir}/dwi-connectome/${subj}${sessionpath}figures/${subj}${sessionfile}space-dwi_tractoverlay.png

  ###############################################################################
  # DWI Spherical-deconvolution Informed Filtering of space-dwi_tractos (SIFT)        #
  ###############################################################################
  # https://mrtrix.readthedocs.io/en/latest/quantitative_structural_connectivity/sift.html?highlight=tcksift
  #the number of streamlines connecting two regions of the brain becomes a proportional estimate of the total cross-sectional area of the white matter fibre pathway connecting those regions; this is inherently a highly biologically relevant measure of ‘structural connectivity’

  if [ ! -f ${subj}${sessionfile}space-dwi_desc-sift-${nstreamlines}_stats.csv ]; then
    echo
    echo "${BLUE}start tck2sift${NC}"
    echo
    tcksift2 ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}.tck \
      ${subj}${sessionfile}FOD-wm-norm.mif \
      ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt \
      -act ${subj}${sessionfile}space-dwi_desc-5tt-hsvs_probseg.nii.gz \
      -out_mu ${subj}${sessionfile}space-dwi_mu.txt \
      -csv ${subj}${sessionfile}space-dwi_desc-sift-${nstreamlines}_stats.csv \
      -force -nthreads ${threads}
  fi
  tckmap ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}.tck \
    ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_dwi.nii.gz \
    -template ${subj}${sessionfile}space-dwi_desc-brain_mask.nii.gz \
    -tck_weights ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt \
    -force -nthreads ${threads}

  # QC
  fslmaths ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_dwi.nii.gz \
    -bin ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_mask.nii.gz
  overlay 1 0 ${subj}${sessionfile}space-dwi_desc-nodif-brain_dwi.nii.gz \
    -a ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_mask.nii.gz 0 1 ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_overlay.nii.gz
  slicer ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_overlay.nii.gz \
    -i 0 1 -a ${outputdir}/dwi-connectome/${subj}${sessionpath}figures/${subj}${sessionfile}siftoverlay3D.png
  rm ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_mask.nii.gz ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}-sift_overlay.nii.gz

  rsync -a ${subj}${sessionfile}space-dwi_tracto-${nstreamlines}* *sift* *mu* \
    ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi
  rsync -a *response* ${outputdir}/dwi-connectome/${subj}${sessionpath}rpf
  mrconvert ${subj}${sessionfile}FOD-wm-norm.mif \
    ${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}tissue-WM-norm_fod.nii.gz
  ############################
  # Tracts to connectome     #
  #############################

  cd ${bidsdir}/${subj}
  if [ -z ${session} ]; then
    sbatch --wait ${scriptdir}/dwi-04b-tracts2conn.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} -s ${subj} -n ${nstreamlines}
  else
    sbatch --wait ${scriptdir}/dwi-04b-tracts2conn.sh -i ${bidsdir} -o ${outputdir} -w ${workdir} -t ${session} -s ${subj} -n ${nstreamlines}
  fi

  if (($(ls ${outputdir}/dwi-connectome/${subj}${sessionpath}conn/${subj}${sessionfile}atlas-*_desc-*_connmatrix.csv 2>/dev/null | wc -l) > 0)); then

    echo "--------------------------------------------------"
    echo -e "${GREEN}finished fod/tck/conn generation subject = ${subj}${NC}"
    echo "---------------------------------------------------"

    #clean-up
    rm ${workdir}/${subj}${sessionpath}dwi/*.mif
    rm *.mif
  else
    echo
    echo -e "${RED}ERROR! fod/tck/conn generation failed for subject = ${subj}${sessionfile}"
    echo -e "inspect the log file${NC}"
    continue

  fi

done
