# About

This project registers and bootstraps a configurable amount of Devices via MQTT. After each bootstrapping, the Clients are creating a Device and one Measurement. After all clients registered, there is an audit that checks if for each client ID:
- Device Credentials exist
- A Device with a proper device owner exists
- A measurement exists

# Configuration

Following environment variables are available to configure the script:
* C8Y_MQTTHOST (f.e. `mqtt.cumulocity.com`)
* C8Y_MQTTPORT (f.e. `8883`)

#  Usage

After setting the proper environment variables, start script with `./main.sh <number of devices to register>`. 

Following prerequisites need to be fulfilled:
* `go-c8y-cli` installed (https://goc8ycli.netlify.app/) and a session loaded to the target tenant
* python3/pip3 installed
* `jq` and `column` installed