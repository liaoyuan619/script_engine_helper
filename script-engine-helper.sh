#!/bin/sh

ACTION=$1

PLUGIN_DOCKER_REPO="31920/android-mgc"
PLUGIN_DOCKER_BIN="/app/system/miner.plugin-dockerd.ipk/bin"
PLUGIN_MGC_SDK_PATH="/app/system/miner.plugin-mgcapp.ipk/depend/mgc_sdk"
PLUGIN_MGC_APP_PATH="/app/system/miner.plugin-mgcapp.ipk/depend/mgc_app"
PLUGIN_START_TIMEOUT=5
PLUGIN_STOP_TIMEOUT=5
timeout=0
PLUGIN_HELPER_LOG_FILE="/tmp/script-engine-helper.log"

function log () {
    echo "====`date`==== $1" >> $PLUGIN_HELPER_LOG_FILE
}

ulimit -v unlimited
export PATH=$PATH:$PLUGIN_DOCKER_BIN

PLUGIN_DOCKER_MAX_TAG=`docker images --format "{{.Repository}}:{{.Tag}}" | grep "$PLUGIN_DOCKER_REPO" | awk -F ":v" '{print $2 | "sort -r -n"}' | head -1`
PLUGIN_DOCKER_IMG="$PLUGIN_DOCKER_REPO:v$PLUGIN_DOCKER_MAX_TAG"


if [ "$ACTION" = "start" ]; then
    PLUGIN_CONTAINER_NAME=$2
    PLUGIN_DIR=$3
    PLUGIN_ENTRY=$4
    PLUGIN_CELLPHONE_SERIAL=$5
    
    $PLUGIN_MGC_APP_PATH/scripts/script-engine-helper.sh stop $PLUGIN_CONTAINER_NAME

    log "$ACTION $PLUGIN_CONTAINER_NAME $PLUGIN_DIR $PLUGIN_ENTRY $PLUGIN_CELLPHONE_SERIAL"
    
    PLUGIN_LOG_DIR="/tmp/.mgc_docker_log/$PLUGIN_CONTAINER_NAME.log/"
    mkdir -p $PLUGIN_LOG_DIR
    
    # add plugin user and permission
    adduser -D -u 11200 mgc-plugin
    chmod 755 $PLUGIN_MGC_SDK_PATH

    mkdir -p $PLUGIN_MGC_SDK_PATH/__pycache__
    chmod -R 777 $PLUGIN_MGC_SDK_PATH/__pycache__    
    
    chmod 755 $PLUGIN_MGC_SDK_PATH/vendor
    chmod 777 $PLUGIN_DIR

    docker run -d --name $PLUGIN_CONTAINER_NAME --cap-drop=ALL --user 11200:11200 --net=container:provider --log-driver json-file --log-opt max-size=1M --log-opt max-file=2 --log-opt log-path=$PLUGIN_LOG_DIR -v /tmp/.efuse_sn:/tmp/.efuse_sn:ro -v $PLUGIN_MGC_SDK_PATH:/usr/local/lib/python3.7/site-packages/mgc_sdk -v $PLUGIN_MGC_SDK_PATH/vendor:/vendor -v "$PLUGIN_DIR":/myapp -w /myapp "$PLUGIN_DOCKER_IMG" python $PLUGIN_ENTRY $PLUGIN_CELLPHONE_SERIAL

    while true
    do
        docker_ps_result=`docker ps | grep $PLUGIN_CONTAINER_NAME`
        if [ -z "$docker_ps_result" ]; then
            timeout=`expr $timeout + 1`
            [ $timeout -gt $PLUGIN_START_TIMEOUT ] && exit 2
        else
            exit 0
        fi

        sleep 1
    done
elif [ "$ACTION" = "stop" ]; then
    PLUGIN_CONTAINER_NAME=$2

    log "$ACTION $PLUGIN_CONTAINER_NAME"
    docker stop "$PLUGIN_CONTAINER_NAME" -t 1 &
    
    while true
    do
        docker_ps_result=`docker ps | grep $PLUGIN_CONTAINER_NAME`
        if [ -n "$docker_ps_result" ]; then
            timeout=`expr $timeout + 1`
            [ $timeout -gt $PLUGIN_STOP_TIMEOUT ] && exit 3
        else
            #exit 0
            log "rm $PLUGIN_CONTAINER_NAME"
            docker rm $PLUGIN_CONTAINER_NAME
            if [ $? -eq 0 ]; then
                exit 0
            else
                exit 4
            fi
        fi

        sleep 1
    done
elif [ "$ACTION" = "ps" ]; then
    #docker ps --format "{{.Names}}"
    docker ps --format "{{.Names}}" --filter name=^/plugin-*

elif [ "$ACTION" = "inspect" ]; then
    PLUGIN_CONTAINER_NAME=$2
    docker inspect $PLUGIN_CONTAINER_NAME

else
    exit 1
fi


