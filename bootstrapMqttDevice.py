import logging
import sys
import time
import json
import paho.mqtt.client as mqtt
from datetime import datetime
import certifi

HOST = sys.argv[1]
PORT = int(sys.argv[2])
CLIENTID = sys.argv[3]
RESULTSETFILE = sys.argv[4]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - {} - %(message)s".format(CLIENTID),
)

credentialsReceivedTs = None
tenantId = None
deviceUserName = None
devicePassword = None
bootstrapConnectionSucceeded = False
deviceConnectionSucceeded = False
bootstrapped = False


def on_connect_bootstrap_credentials(client, userdata, flags, rc):
    global bootstrapConnectionSucceeded
    if rc == 0:
        logging.info("Connected to MQTT Broker (for bootstrapping)")
        bootstrapConnectionSucceeded = True
    else:
        logging.error("Failed to connect, return code %d\n", rc)
        bootstrapConnectionSucceeded = False


def on_connect_device_credentials(client, userdata, flags, rc):
    global deviceConnectionSucceeded
    if rc == 0:
        logging.info("Connected to MQTT Broker (using device credentials)")
        deviceConnectionSucceeded = True
    else:
        logging.info("Failed to connect, return code %d\n", rc)
        deviceConnectionSucceeded = False


def on_message(client, userdata, msg):
    logging.info(
        "Received message, topic: " + msg.topic + " payload: " + str(msg.payload)
    )
    global tenantId
    global devicePassword
    global deviceUserName
    global credentialsReceivedTs
    global bootstrapped
    payloadParts = msg.payload.decode("utf-8").split(",")
    if payloadParts[0] == "70":
        credentialsReceivedTs = datetime.now().isoformat()[:-3] + "Z"
        tenantId = payloadParts[1]
        deviceUserName = payloadParts[2]
        devicePassword = payloadParts[3]
        bootstrapped = True
        client.loop_stop()


def publish(topic, message, wait_for_ack=False):
    QoS = 2 if wait_for_ack else 0
    message_info = client.publish(topic, message, QoS)
    if wait_for_ack:
        logging.info(" > awaiting ACK for {}".format(message_info.mid))
        message_info.wait_for_publish()
        logging.info(" < received ACK for {}".format(message_info.mid))


def on_disconnect(client, userdata, rc):
    logging.info("Disconnection returned result:" + str(rc))


def on_subscribe(client, userdata, mid, granted_qos):
    pass


# Get Bootstrap credentials
client = mqtt.Client(CLIENTID)
client.tls_set(certifi.where())
client.username_pw_set(f"management/devicebootstrap", "Fhdt1bb1f")
client.on_connect = on_connect_bootstrap_credentials
client.on_disconnect = on_disconnect
client.on_message = on_message
client.on_subscribe = on_subscribe
client.connect(HOST, PORT)
client.loop_start()
client.subscribe("s/dcr")
while not bootstrapped:
    client.publish("s/ucr")
    logging.info("Sent empty message to s/ucr. Waiting to be registered ...")
    time.sleep(2)
logging.info("Exited bootstrap mode. Re-connecting with Device Credentials ...")
client.disconnect

# Create the device and send a sample measurement
client = mqtt.Client(CLIENTID)
client.tls_set(certifi.where())
client.username_pw_set(f"{tenantId}/{deviceUserName}", devicePassword)
client.on_connect = on_connect_device_credentials
client.on_disconnect = on_disconnect
client.connect(HOST, PORT)
client.loop_start()
deviceName = f"dev-mqtt-{CLIENTID}"
client.publish("s/us", f"100,{deviceName},mqttTest")
logging.info(f"Created Device {deviceName}.")
time.sleep(1)
client.publish("s/us", "200,c8y_Temperature,T,25")
logging.info("Created Measurement for Device")
client.loop_stop()

# Save results to file
with open(RESULTSETFILE, "a") as file:
    data_json = json.dumps(
        {
            "host": HOST,
            "port": PORT,
            "mqttClientId": CLIENTID,
            "tenantId": tenantId,
            "deviceUserName": deviceUserName,
            "devicePassword": devicePassword,
            "credentialsReceivedTs": credentialsReceivedTs,
            "bootstrapConnectionSucceeded": bootstrapConnectionSucceeded,
            "deviceConnectionSucceeded": deviceConnectionSucceeded,
        }
    )
    file.write(data_json + "\n")
logging.info(f"Appended result to {RESULTSETFILE}")
