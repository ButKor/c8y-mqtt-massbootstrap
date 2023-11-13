#!/bin/bash

NR_DEVICES=$1

# Cleanup runtime folder & make sure same process is not already running
rm runtime/*
pkill -9 -f $0
pkill -9 -f auditResults
pkill -9 -f deviceregistration

# Delete all existing devices and device-registrations
c8y devices list --type mqttTest --includeAll | c8y inventory delete -f --workers 4
c8y deviceregistration list --includeAll | c8y deviceregistration delete -f --workers 4
c8y users list --onlyDevices --includeAll | c8y users delete -f --workers 3


echo "create device registrations..."
seq $NR_DEVICES | xargs -I {} uuidgen | c8y deviceregistration register -f --workers 5 \
    | jq '{mqttClientId:.id}' -c | jq -s >./runtime/clientIds.json

echo "start background process to auto-approve device registrations..."
while :; do
    c8y deviceregistration list --includeAll --filter "status like PENDING_ACCEPTANCE" \
        | c8y deviceregistration approve -f --delay 250ms
    sleep 3
done &

echo "bootstrap devices ..."
batchSize=10
resultFile=./runtime/mqtt-clients.log.json
cat ./runtime/clientIds.json | jq -r '.[] | .mqttClientId' \
    | xargs -I {} echo "python3 bootstrapMqttDevice.py $C8Y_MQTTHOST $C8Y_MQTTPORT {} $resultFile" \
    | xargs -I CMD --max-procs=$batchSize bash -c CMD

echo "audit results ..."
./auditResults.sh

exit 0