#!/bin/bash

# configuration and variables

# Notify after $NOTIFY_AFTER seconds of being on backup
NOTIFY_AFTER=300
# Swap QOS after $SWAP_QOS_AFTER seconds of being on a new state
SWAP_QOS_AFTER=60
# Number of seconds between each loop cycle
SLEEP_VALUE=5
# Number of seconds to wait before sending notification
WAIT_BEFORE_NOTIFY=60

# keep this in sync with swap-qos.sh
LOG_MSG_MAIN_LINE="INFO: IVY Main connection is up"
LOG_MSG_BACKUP_LINE="ALERT: IVY Backup connection was activated"

# LOG_FILE of swap-qos.sh
LOG_TO_WATCH=/config/scripts/wlb.log
# My own log file
LOG_FILE=/config/scripts/wlb_notification.log

# user sms configuration
SMS_USER=SMS_USER
SMS_PASS=SMS_PASS

# Wrapper for QOS command
WRAPPER=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper


TEST=0
if [[ $TEST == "1" ]]
then
    LOG_TO_WATCH=wlb.log
    LOG_FILE=wlb_notification.log
    WRAPPER=echo
    # olivier
    SMS_USER=TEST_SMS_USER
    SMS_PASS=TEST_SMS_PASS
    # I'm not patient enough
    SWAP_QOS_AFTER=7
    NOTIFY_AFTER=15
    SLEEP_VALUE=1
    WAIT_BEFORE_NOTIFY=1
fi

# function to set the QOS when we are on the main line
function set_qos_main {
    log "Set QOS for main line"
    $WRAPPER begin
    $WRAPPER delete interfaces ethernet eth2 traffic-policy out QOS-DOWNLOAD-BACKUP
    $WRAPPER delete interfaces input ifb2 traffic-policy out QOS-UPLOAD-BACKUP
    $WRAPPER set interfaces input ifb2 traffic-policy out QOS-UPLOAD
    $WRAPPER set interfaces ethernet eth2 traffic-policy out QOS-DOWNLOAD
    $WRAPPER commit
    $WRAPPER end
}

# function to set the QOS when we are on the backup line
function set_qos_backup {
    log "Set QOS for backup line"
    $WRAPPER begin
    $WRAPPER delete interfaces ethernet eth2 traffic-policy out QOS-DOWNLOAD
    $WRAPPER delete interfaces input ifb2 traffic-policy out QOS-UPLOAD
    $WRAPPER set interfaces input ifb2 traffic-policy out QOS-UPLOAD-BACKUP
    $WRAPPER set interfaces ethernet eth2 traffic-policy out QOS-DOWNLOAD-BACKUP
    $WRAPPER commit
    $WRAPPER end
}

# function to notify that something has changed
function notify {
    sleep $WAIT_BEFORE_NOTIFY
    msg=$1
    notify_email "$msg"
    notify_sms "$msg"
    log "Notified $msg"
}

# function to notify through email that something has changed
function notify_email {
    msg=$1
echo "To: your@email.com
From: Routeur
Subject: $msg
Content-Type: text/plain; charset=utf-8; format=flowed

Om Tare Toutare toure soha." | /usr/sbin/ssmtp -f your@email.com your@email.com
}
# function to notify through sms that something has changed
function notify_sms {
    msg=$1
    curl -k "https://smsapi.free-mobile.fr/sendmsg?user=$SMS_USER&pass=$SMS_PASS&msg=$msg" -o -
}

# return the line number "n" from the log or empty if not existent
function get_line {
    local n=$1
    local log=$2
    local line=$(tail -n +$n $log | head -n 1)
    echo $line
}

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

# last line of the log to watch
line_number=$(wc -l $LOG_TO_WATCH | cut -d\  -f1)
# go to the next line as $line_number will always be the next line to treat
line_number=$(($line_number+1))

# will go from MAIN to BACKUP and BACKUP to MAIN
line_state=MAIN
# 1 if backup state have been notified, 0 if not yet
backup_state_notified=1
# In current state since $IN_STATE_SINCE seconds
in_state_since=0
# last backup situation: line value
last_backup_line=meuh
# 1 if the qos was swapped - I start with 0 so it will set the QOS automatically
swapped_qos=0

while true
do
    # get the next line from the log
    line=$(get_line $line_number $LOG_TO_WATCH)
    if [ -n "$line" ]
    then
        if [ $line_state == "MAIN" ]
        then
            # I'm waiting a "go to backup" message
            if echo $line | grep "$LOG_MSG_BACKUP_LINE" > /dev/null
            then
                log "After $in_state_since seconds, going in line_state=BACKUP"
                line_state=BACKUP
                in_state_since=0
                backup_state_notified=0
                last_backup_line=$line
                swapped_qos=0
            fi
        else
            # I'm waiting a "go to main" message
            if echo $line | grep "$LOG_MSG_MAIN_LINE" > /dev/null
            then
                log "After $in_state_since seconds, going in line_state=MAIN"
                line_state=MAIN
                in_state_since=0
                if [ $backup_state_notified == 1 ]
                then
                    # I did a notification when I was on backup - I should notify coming back to normal
                    notify "$line"
                fi
                swapped_qos=0
            fi
        fi
        # this line has been treated
        line_number=$(($line_number+1))
    fi
    # sleep between 2 checks
    sleep $SLEEP_VALUE
    # count number of seconds I'm in this state
    in_state_since=$(($in_state_since+$SLEEP_VALUE))
    # check if I need to notify backup situation
    if [ $line_state == "BACKUP" ]
    then
        if [ $backup_state_notified == 0 ]
        then
            if [ $in_state_since -gt $NOTIFY_AFTER ]
            then
                notify "$last_backup_line"
                backup_state_notified=1
            fi
        fi
    fi
    # check if I need to set a new QOS
    if [ $swapped_qos == 0 ]
    then
        if [ $in_state_since -gt $SWAP_QOS_AFTER ]
        then
            if [ $line_state == "BACKUP" ]
            then
                set_qos_backup
            else
                set_qos_main
            fi
            swapped_qos=1
        fi
    fi
done
