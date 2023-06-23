#!/bin/bash

## SLURM INPUTS ##
#SBATCH --job-name=dwiwrapper
#SBATCH --mem=2G
#SBATCH --partition=luna-cpu-long
#SBATCH --qos=anw-cpu
#SBATCH --cpus-per-task=1
#SBATCH --time=02-00:00:00
#SBATCH --nice=2000
#SBATCH --output=dwiwrapper_%A_%a.log

###################

# Define color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[34m'
NC='\033[0m' # No Color

# Initialize variables
scriptdir=""
bidsdir=""
outputdir=""
workdir=""
freesurferdir=""
subjects=""
noddi=""
# input variables
# Parse command line arguments

while getopts ":i:o:f:w:n:ss:c:" opt; do
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
    ss)
        subjects="$OPTARG"
        ;;
    c)
        scriptdir="$OPTARG"
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
    esac
done


echo "scriptdir=${scriptdir}"
echo "subjects:"
cat ${subjects}

subj=$(sed "${SLURM_ARRAY_TASK_ID}q;d") ${subjects}
# random delay
duration=$((RANDOM % 120 + 2))
echo -e "${YELLOW}sleep for ${duration} sec${NC}"
echo
sleep ${duration}

echo
echo -e "${BLUE}--------"
echo -e "${subj}"
echo -e "---------------${NC}"
echo
sbatch --job-name=job_${subj} --output=${subj}_dwipipe.log ${scriptdir}/dwi-01-pipeline.sh -i ${bidsdir} \
    -o ${outputdir} -w ${workdir} -s ${subj} -f ${freesurferdir} -n 1 -c ${scriptdir}
