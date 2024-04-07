#!/bin/bash

VERSION="2023.03.23"

echo "-- Auto bench v.${VERSION}"

if [ -z "$1" ] ; then
    echo "Usage: $0 <label>"
    echo "Eg.: $0 NVIDIA_2080TI"
    exit 1
fi

if [ -z "$(command -v curl)" ] ; then
    echo "-- CURL not installed, aborting"
    exit 1
fi

if [ -z "$(command -v docker)" ] ; then
    echo "-- DOCKER not installed, aborting"
    exit 1
fi

CWD=$(pwd)
TAG=${TAG-cvedia/public:runtime-$(uname -p)-public-2023.1.0}
BACKEND=${BACKEND-tensorrt.1}

SKIP_BS1="${SKIP_BS1-0}"
SKIP_BSX="${SKIP_BSX-0}"
SKIP_BLL="${SKIP_BLL-0}"

TEST_DURATION="${TEST_DURATION-60}"
TEST_WARMUP="${TEST_WARMUP-5}"

BSX_ME="${OPT_ME-3}"
BLL_ME="${OPT_ME-10}"

CVEDIA_RT_INSTALL="${CVEDIA_RT_INSTALL-https://bin.cvedia.com/2023.1.0/Linux-2023.1.0.tar.gz}"
METRICS_BACKEND="${METRICS_BACKEND-https://www.overflow.biz/upload/upload?token=f9403fc5f537b4ab332d}"
KEEP_METRICS="${KEEP_METRICS-0}"
WD=$(mktemp -d)

# batch size 1 flat
if [ "$SKIP_BS1" == "0" ] ; then
    echo "-- Adding BS1 tests"
    TESTS="bs1"
fi

# optimize for best batch size
if [ "$SKIP_BSX" == "0" ] ; then
    echo "-- Adding BSX tests"
    TESTS="$TESTS bsx"
fi

if [ "$SKIP_BLL" == "0" ] ; then
    echo "-- Adding BLL tests"
    TESTS="$TESTS bll"
fi

# optimize for lowest latency
if [ -z "$TESTS" ] ; then
    echo "-- No tests to run, aborting!"
    exit 1
fi

prefix=$(hostname)_$1
echo "-- TAG: $TAG WD: $WD PREFIX: $prefix TESTS: $TESTS"

cd $WD
set -e
curl $CVEDIA_RT_INSTALL -sqq -o - | tar -zx
set +e

for t in $TESTS; do
    if [ "$t" == "bsx" ] ; then
        BENCH_PARAMS="-o 10 -M ${BSX_ME} -S thruput"
    elif [ "$t" == "bll" ] ; then
        BENCH_PARAMS="-o 10 -M ${BLL_ME} -S latency"
    fi

    echo "-- Running: $t $BENCH_PARAMS"

    # regular models
    for m in 3dbbox_reg/rgb/default_64x64/220907 cuav_classifier/rgb_thermal/default/211116b cuav_ufo_det/rgb_thermal/medium/220222b face_det/rgb/10g_512x512/221018 packages_detector/rgb/default/220506b par_classifier/rgb/resnet34_224_224/220325b people_det/rgb/tiny/221221b people_fallen_classifier/rgb/normal/221221b pva_classifier/rgb/default/220318b pva_classifier/rgb/resnet18_64x64/220826 pva_classifier/thermal/resnet18_64x64/220620 pva_det/rgb_aerial/medium_512x512/221214 pva_det/rgb_ground/medium_512x512/220330 pva_det/rgb_gs/nano_160x160/220527b pva_det/rgb/medium_1280x736/230118 pva_det/rgb/medium_512x512/230124 pva_det/rgb/small_320x320/221123 pva_det/rgb/small_320x320_aerial/221128 pva_det/rgb/small_320x320_ground/221129 pva_det/thermal/medium/220307b pva_det/thermal/medium_512x512/220413b pva_det/thermal/medium_512x512/220728 vehicle_model_classifier/rgb_thermal/resnet18_128x128/221021 vehicle_model_classifier/rgb_thermal/resnet18_128x128/221122; do
        echo "-- Running: ${m}..."
        ./run.sh --disable_mqtt -UCEPM benchmark -t ${TAG} ${RUN_PARAMS} -- -e CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES-0} -e DEVICE_INDEX=${DEVICE_INDEX-0} -e NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES-0} -- -u ${BACKEND}://${m} -n 1000000 ${BENCH_PARAMS} -w ${TEST_WARMUP} -d ${TEST_DURATION} -i 5 -j /opt/cvedia-rt/persist/${prefix}_${t}_${m//\//_}.json
    done

    # models which we need to specify the size
    for m in crowd_detection/rgb/mae_749/220930; do
        echo "-- Running: ${m}..."
        ./run.sh --disable_mqtt -UCEPM benchmark -t ${TAG} ${RUN_PARAMS} -- -e CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES-0} -e DEVICE_INDEX=${DEVICE_INDEX-0} -e NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES-0} -- -u ${BACKEND}://${m} -n 1000000 ${BENCH_PARAMS} -w ${TEST_WARMUP} -d ${TEST_DURATION} -i 5 --width 1280 --height 720 -j /opt/cvedia-rt/persist/${prefix}_${t}_${m//\//_}.json
    done
    
    unset BENCH_PARAMS
done

OFN=${prefix}_$(date +%Y%m%d_%H%M%S).tar.gz

cd persist
rm -f rtshm.json &> /dev/null

K=$(find . -maxdepth 1 -type f -iname '*.json' | wc -l)
if [ "$K" == "0" ] ; then
    echo "-- No valid metrics to publish, aborting!"
    exit 1
fi

echo "-- Publishing metrics..."

tar -czf ${OFN} ./*.json

while true; do
    curl -sk -Ffile=@${OFN} $METRICS_BACKEND
    RT=$?
    
    echo
    
    if [ "$RT" == "0" ] ; then
        echo "-- Metrics published"
        break
    else
        echo "-- Failed to publish metrics, retrying..."
        sleep 5
    fi
done

if [ "$KEEP_METRICS" == "0" ] ; then
    cd ${CWD}
    rm -fr $WD
fi

echo "-- Completed, ${OFN} published, ${SECONDS}s wasted."
exit 0
