#!/bin/bash

#SBATCH --job-name=eddy
#SBATCH --mem-per-cpu=6G
#SBATCH --partition=luna-short
#SBATCH --cpus-per-task=1
#SBATCH --time=00-2:00:00
#SBATCH --nice=3000
#SBATCH --qos=anw
#SBATCH --output eddy_%A.log

module load fsl/6.0.6.5

# inputs
DWImain=${1}
DWImask=${2}
DWIacqp=${3}
DWIbvecs=${4}
DWIbvals=${5}
DWIjson=${6}
topup=${7}
DWIout=${8}
method=${9}

# choose method of eddy correction (default or volcorr)

basedir=$(dirname DWImain)
cd ${basedir}

# create index.txt file
idx=$(fslnvols ${DWImain})
printf '1 %.0s' $(seq 1 "$idx") >${basedir}/index.txt

# json available with slice-timing?
if jq -e '.SliceTiming' "${DWIjson}" >/dev/null; then
    STavail=1
else
    STavail=0
fi

# default
if [[ ${method} == "default" ]]; then
    eddy_cuda10.2 \
        --imain=${DWImain} \
        --mask=${DWImask} \
        --acqp=${DWIacqp} \
        --index=index.txt \
        --bvecs=${DWIbvecs} \
        --bvals=${DWIbvals} \
        --out=${DWIout} \
        --topup=${topup} \
        --repol --cnr_maps \
        --slm=linear \
        --estimate_move_by_susceptibility --verbose

    # run QC
    echo 
    echo "running QC" 
    eddy_quad ${DWIout} \
        -idx index.txt \
        -par ${DWIacqp} \
        -m ${DWImask} \
        -b ${DWIbvals} \
        -f ${topup}_fieldmap.nii.gz

elif [[ ${method} == "volcorr" ]]; then

    if ((STavail == 1)); then
        # w/ slice-to-vol correction
        eddy_cuda10.2 \
            --imain=${DWImain} \
            --mask=${DWImask} \
            --acqp=${DWIacqp} \
            --index=index.txt \
            --json=${DWIjson} \
            --bvecs=${DWIbvecs} \
            --bvals=${DWIbvals} \
            --out=${DWIout} \
            --topup=${topup} \
            --repol --cnr_maps \
            --slm=linear \
            --estimate_move_by_susceptibility --verbose
        --mbs_niter=10 --mbs_lambda=10 --mbs_ksp=10 \
            --niter=8 --fwhm=10,6,4,2,0,0,0,0
        --mporder=8 --s2v_niter=8 --slspec=../slspec.txt \
            --s2v_lambda=1 --s2v_interp=trilinear >${basedir}/eddy.log

    else

        eddy_cuda10.2 \
            --imain=${DWImain} \
            --mask=${DWImask} \
            --acqp=${DWIacqp} \
            --index=index.txt \
            --json=${DWIjson} \
            --bvecs=${DWIbvecs} \
            --bvals=${DWIbvals} \
            --out=${DWIout} \
            --topup=${topup} \
            --repol --cnr_maps \
            --slm=linear \
            --estimate_move_by_susceptibility --verbose
        --mbs_niter=10 --mbs_lambda=10 --mbs_ksp=10 \
            --niter=8 --fwhm=10,6,4,2,0,0,0,0
        --mporder=8 --s2v_niter=8 --slspec=../slspec.txt \
            --s2v_lambda=1 --s2v_interp=trilinear >${basedir}/eddy.log
    fi
else

    echo "proper method for eddy not set"
    echo "exiting script"
    exit
fi

