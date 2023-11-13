#!/bin/bash

# Request ClientId to Device-Id Mapping
cat ./runtime/mqtt-clients.log.json | jq -c '{id:.mqttClientId,deviceUserName}' |
    c8y identity get --type c8y_Serial --outputTemplate '{mqttClientId:input.value.id,deviceId:output.managedObject.id}' 2>/dev/null |
    c8y inventory get --id -.deviceId --outputTemplate '{mqttClientId:input.value.mqttClientId,deviceId:output.id,name:output.name,type:output.type,owner:output.owner}' -o json -c |
    jq -s >./runtime/audit_clientToDevices.json

# Request Measurement count for each Device-ID
cat ./runtime/audit_clientToDevices.json | jq -c '.[] | {id:.deviceId,mqttClientId}' |
    c8y measurements list -p 1 --withTotalElements --raw \
        --outputTemplate "{mqttClientId:input.value.mqttClientId,deviceId:input.value.id,ctMeasurements:output.statistics.totalElements}" -c |
    jq -s >./runtime/audit_clientToMeasurements.json

# Join MQTT-Clients with Device- and Measurement Mapping
jq '[JOIN(INDEX(input[]; .mqttClientId); .[]; .mqttClientId; add)]' ./runtime/clientIds.json ./runtime/audit_clientToDevices.json \
    >./runtime/audit_clientToDeviceJoin.json
jq '[JOIN(INDEX(input[]; .mqttClientId); .[]; .mqttClientId; add)]' ./runtime/audit_clientToDeviceJoin.json ./runtime/audit_clientToMeasurements.json \
    >./runtime/audit_clientDeviceMeasurementJoin.json

# create report
> audit-result.log
echo "### MQTT BOOTSTRAP TEST RESULTS ###" >> audit-result.log
echo "" >> audit-result.log
echo -e "Date: \t$(date)" >> audit-result.log
echo -e "Host: \t$(cat ./runtime/mqtt-clients.log.json | jq -r .host | head -n 1)" >> audit-result.log
echo -e "Tenant: $(cat ./runtime/mqtt-clients.log.json | jq -r .tenantId | head -n 1)" >> audit-result.log
echo "" >> audit-result.log

create_log(){
    c8y template execute --template '{description:var("desc"),value:var("value")}' -o json -c \
        --templateVars desc="$1",value="$2" >>output.tmp
}
resFile=./runtime/audit_clientDeviceMeasurementJoin.json
>output.tmp
create_log Description Value
create_log "------------------------------------------------" "--------"
v=$(cat ./runtime/clientIds.json | jq '.[]' -c | wc -l | sed 's/ //g')
create_log "Count Client IDs total" $v

v=$(cat ./runtime/mqtt-clients.log.json | jq 'select(.deviceUserName != null and .devicePassword != null)' -c | wc -l | sed 's/ //g')
create_log "Count Client IDS with Device Credentials" $v

v=$(cat ./runtime/mqtt-clients.log.json | jq 'select(.deviceUserName == null or .devicePassword == null)' -c | wc -l | sed 's/ //g')
create_log "Count Client IDS without Device Credentials" $v

v=$(cat $resFile | jq '.[] | select(.deviceId != null)' -c | wc -l | sed 's/ //g')
create_log "Count Client IDs with platform device" $v

v=$(cat $resFile | jq '.[] | select(.deviceId == null)' -c | wc -l | sed 's/ //g')
create_log "Count Client IDs without platform device" $v

v=$(cat $resFile | jq '.[] | select(.ctMeasurements != null and .ctMeasurements > 0)' -c | wc -l | sed 's/ //g')
create_log "Count Client IDs with measurements" $v

v=$(cat $resFile | jq '.[] | select(.ctMeasurements == null or .ctMeasurements == 0)' -c | wc -l | sed 's/ //g')
create_log "Count Client IDs without measurements" $v

cat output.tmp | c8y util show -o csv | column -t -s , >> audit-result.log
rm output.tmp
echo "" ; cat audit-result.log