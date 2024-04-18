#!/bin/bash


#SBATCH --job-name=dwiclean
#SBATCH --mem=1G
#SBATCH --partition=luna-cpu-short
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=00-00:15:00
#SBATCH --nice=2000
#SBATCH --output=dwi-cleanup_%A.log


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
while getopts ":i:o:w:s:n:" opt; do
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




for dwidir in ${bidsdir}/${subj}/{,ses*/}dwi; do
    if [ ! -d ${dwidir} ]; then
        continue
    fi
    sessiondir=$(dirname ${dwidir})
    echo
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

cd ${outputdir}
    echo
    echo -e "${BLUE}${subj}${sessionfile}acq-${acq}_run-${run}${NC}"
    echo
	files=$(echo "
	${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}.tck
	${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tracto-${nstreamlines}_desc-sift_weights.txt
	${outputdir}/dwi-connectome/${subj}${sessionpath}dwi/${subj}${sessionfile}acq-${acq}_run-${run}_tissue-WM-norm_fod.nii.gz
    ${outputdir}/dwi-connectome/${subj}${sessionpath}rpf/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tissue-WM_response.txt
    ${outputdir}/dwi-connectome/${subj}${sessionpath}rpf/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tissue-CSF_response.txt
    ${outputdir}/dwi-connectome/${subj}${sessionpath}rpf/${subj}${sessionfile}acq-${acq}_run-${run}_space-dwi_tissue-GM_response.txt")
   


            i=0
            for file in ${files}; do

                if [ ! -f ${file} ]; then
                    echo -e "${RED}a scan was not found in the outputdir ${NC}"
                    echo -e "${file}"
                    i=$((i+1))
                    
                 fi
            done

            if (( i > 0 )); then 

                    echo -e "${RED}!!!ERROR!!!${NC}"
                    echo -e "not all files are available in the output directory"
                    echo -e "cancel clean-up of workdir"
                    continue
            else

            if (( $(ls ${outputdir}/dwi-connectome/${subj}${sessionpath}conn/${subj}${sessionfile}acq-${acq}_run-${run}_atlas-*_desc-*_connmatrix.csv 2>/dev/null | wc -l) > 0 )); then 

                    echo -e "${GREEN}!!!SUCCESS!!!${NC}"
                    echo -e "dwi and conn files found in output dir of ${subj}${sessionfile}acq-${acq}_run-${run}"
                    find ${workdir}/${subj} -name "${subj}${sessionfile}acq-${acq}_run-${run}*" -exec rm {} \;



            else

                    echo -e "${RED}!!!ERROR!!!${NC}"
                    echo -e "no connectivity matrices available in output directory"
                    echo -e "cancel clean-up of workdir"
                    continue
            fi


            fi

               


        done
    done

if (( $(find ${workdir}/${subj}${sessionpath} -type f | wc -l) == 0 )); then 

    rm -r ${workdir}/${subj}${sessionpath}

    else 
                    echo -e "${YELLOW}WARNING!!!${NC}"
                    echo -e "work directory of ${subj}${sessionpath} is not empty"
                    echo


fi
done
