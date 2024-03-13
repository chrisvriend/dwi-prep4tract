#!/bin/bash

#SBATCH --job-name=tck2conn
#SBATCH --mem=4G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=4
#SBATCH --time=00-01:00:00
#SBATCH --nice=2000
#SBATCH --output=dwi-tck2conn_%A.log

threads=4

Usage() {
    cat <<EOF

    (C) C.Vriend - 5/30/2023
    calculates connectomes for MRTRIX3 processed data
    Usage: ./dwi-tracts2conn.sh subject 
    JobName = subject ID w/ sub-????


EOF
    exit 1
}

[ _$1 = _ ] && Usage

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
nstreamlines=""
# input variables
# Parse command line arguments
while getopts ":i:o:w:s:t:n:" opt; do
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
    n)
        nstreamlines="$OPTARG"
        ;;
    \?)
        echo "Invalid option -$OPTARG" >&2
        ;;
    esac
done

# source software
module load fsl/6.0.6.5
module load Anaconda3/2022.05
conda activate /scratch/anw/share/python-env/mrtrix

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

    cd ${dwidir}
    dwiacqs=$(ls -1 ${subj}${sessionfile}*_dwi.nii.gz)
    acqs=$(echo "$dwiacqs" | cut -d'-' -f4 | cut -d'_' -f1 | sort -u)

    for acq in ${acqs}; do

        dwiruns=$(ls -1 ${subj}${sessionfile}acq-${acq}*_dwi.nii.gz)
        runs=$(echo "$dwiruns" | cut -d'-' -f5 | cut -d'_' -f1 | sort -u)

        for run in ${runs}; do

            ##############
            # CHECK FILES
            ##############
            files=$(echo "
	${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}.tck
	${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt
	${workdir}/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-biascor_dwi.mif")
            for file in ${files}; do

                if [ ! -f ${file} ]; then
                    echo -e "${RED}!!!ERROR!!!${NC}"
                    echo -e "${RED}a scan was not found in the workdir ${NC}"
                    echo -e "${file}"
                    echo -e "cannot continue without this file"
                    exit
                fi

            done

            if [ -f ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-odi_noddi.nii.gz ]; then
                echo -e "${YELLOW}found noddi output in output directory"
                echo -e "...copying to workdir${NC}"
                echo
                rsync -a ${outputdir}/dwi-preproc/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-odi_noddi.nii.gz \
                    ${workdir}/${subj}${sessionpath}dwi/
            fi

            #========================
            ### TRANSFER FILES
            #========================
            rsync -az --ignore-existing ${outputdir}/dwi-preproc/${subj}${sessionpath}anat/*dseg* \
                ${workdir}/${subj}${sessionpath}anat/

            mkdir -p "${outputdir}/dwi-connectome/${subj}${sessionpath}conn"
            mkdir -p "${workdir}/${subj}${sessionpath}conn"

            cd ${workdir}/${subj}${sessionpath}dwi

            if [ ! -f ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-bLOW_FA.nii.gz ]; then
                echo -e "${BLUE}dtifit ${NC}"
               
                mrconvert ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-biascor_dwi.mif \
                 ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-biascor_dwi.nii.gz \
                    -export_grad_fsl bLOW.bvec bLOW.bval -force
                dtifit -k ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-biascor_dwi.nii.gz \
                    -m ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-brain_mask.nii.gz \
                    -r bLOW.bvec -b bLOW.bval \
                    -o ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-bLOW --sse
                rm b*.bv*
            fi

            # create tract map file
            # if [ ! -f ${workdir}/QC/tdi_hires.nii.gz ]; then
            # tckmap ${DWIdir}/dwi_100M.tck ${workdir}/QC/tdi_hires.nii.gz \
            # -tck_weights_in ${DWIdir}/sift.txt -vox 0.25 -datatype uint16 -nthreads ${Ncores}
            # fi

            ###############################################################################
            # DWI CONNECTOME GENERATION                                                   #
            ###############################################################################
            # https://mrtrix.readthedocs.io/en/latest/quantitative_structural_connectivity/structural_connectome.html

            if [ ! -f ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-lengths_stats.csv ]; then
                # extract lengths
                tckstats -dump ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-lengths_stats.csv \
                 ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}.tck \
                    -tck_weights_in ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt \
                    -force -nthreads ${threads}
            fi
            # FA / ND
            for diff in FA ndi; do
                if [[ ${diff} == FA ]]; then
                    inputfile=${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-preproc-bLOW_FA.nii.gz
                elif [[ ${diff} == ndi ]]; then
                    inputfile=${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-odi_noddi.nii.gz
                fi

                if [ ! -f ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-${diff}_stats.csv ] &&
                    [ -f ${inputfile} ]; then
                    tcksample ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}.tck \
                        ${inputfile} \
                        ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-${diff}_stats.csv -stat mean -nthreads ${threads}
                fi

            done

            for atlas in BNA 300P7N 300P17N 400P7N 400P17N aparc500; do
                if [ ! -f ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_atlas-${atlas}_dseg.nii.gz ]; then
                    echo -e "${YELLOW}!!WARNING!!${atlas} atlas not available${NC}"
                    echo
                    continue
                fi
                echo
                echo -e "${BLUE}atlas = ${atlas}${NC}"
                # streamline count
                # normalization: https://community.mrtrix.org/t/normalization-of-connectomes/4363
                if [ ! -f ${workdir}/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-${atlas}_desc-streams_connmatrix.csv ]; then
                    echo -e "${BLUE}...streamlines...${NC}"
                    tck2connectome ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}.tck \
                        ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_atlas-${atlas}_dseg.nii.gz \
                        ${workdir}/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-${atlas}_desc-streams_connmatrix.csv \
                        -zero_diagonal \
                        -tck_weights_in ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt \
                        -nthreads ${threads} -force -symmetric \
                        -assignment_radial_search 4 \
                        -out_assignments ${workdir}/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-${atlas}_trackassign.txt
                fi
                for scalar in lengths FA ndi; do
                    if [ ! -f ${workdir}/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-${atlas}_desc-${scalar}_connmatrix.csv ]; then
                        if [ -f ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-${scalar}_stats.csv ]; then
                            echo -e "${BLUE}...${scalar}...${NC}"
                            tck2connectome ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}.tck \
                                ${workdir}/${subj}${sessionpath}anat/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_atlas-${atlas}_dseg.nii.gz \
                                ${workdir}/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-${atlas}_desc-${scalar}_connmatrix.csv \
                                -scale_file ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_desc-${scalar}_stats.csv \
                                -zero_diagonal \
                                -tck_weights_in ${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt \
                                -stat_edge mean \
                                -assignment_radial_search 4 \
                                -nthreads ${threads} -force -symmetric
                        else
                            echo
                            echo -e "${YELLOW}!WARNING! ${scalar} scalar file does not exist - skipping${NC}"
                            echo
                        fi

                    fi
                done

            done
            echo
            echo -e "${GREEN}finished tck2connectome. Transfer files${NC}"
            rsync -av ${workdir}/${subj}${sessionpath}conn/* ${outputdir}/dwi-connectome/${subj}${sessionpath}conn

            if (($(ls ${outputdir}/dwi-connectome/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-*_desc-*_connmatrix.csv 2>/dev/null | wc -l) > 0)); then

                echo "--------------------------------------------------"
                echo -e "${GREEN}finished fod/tck/conn generation subject = ${subj}${NC}"
                echo "---------------------------------------------------"

                #clean-up
                rm ${workdir}/${subj}${sessionpath}dwi/*.mif
            else
                echo
                echo -e "${RED}ERROR! fod/tck/conn generation failed for subject = ${subj}${sessionfile}"
                echo -e "inspect the log file${NC}"
                continue

            fi

        done
    done
done
