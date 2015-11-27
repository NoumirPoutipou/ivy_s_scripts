#!/bin/bash

# configuration
TEST=0
if [[ $TEST == "1" ]]
then
    LOG_FILE=wlb.log
else
    LOG_FILE=/config/scripts/wlb.log
fi

# Arguments
GROUP=$1
INTERFACE=$2
STATUS=$3

# log a message - auto add a date
function log {
    msg=$1
    datetime=`date +"%F %T"`
    echo "$datetime $msg"  2>&1 >>$LOG_FILE
    # limit log size when exceeding
    if [ $(wc -l $LOG_FILE | cut -d\  -f1) -gt 2000 ]
    then
        tail -n 500 $LOG_FILE > $LOG_FILE.tmp
        mv $LOG_FILE.tmp $LOG_FILE
    fi
}

case "$STATUS" in
    active)
        case "$INTERFACE" in
            eth0)
                log "INFO: IVY Main connection is up"
            ;;
            eth1)
                log "ALERT: IVY Backup connection was activated"
            ;;
        esac
    ;;
    inactive)
    ;;
    failover)
        # case "$INTERFACE" in
            # eth0)
                # log "ALERT: IVY Main connection is down"
            # ;;
            # eth1)
                # log "INFO: IVY Backup connection was desactivated"
            # ;;
        # esac
    ;;
    *)
    log "Oh crap, $INTERFACE going [$STATUS]"
  ;;
esac

exit 0
