import os
import sys
import argparse
import json
import random
import base64

from paho.mqtt import client as mqtt_client

parser = argparse.ArgumentParser(description="Consumes a MQTT queue and prints its messages")
# mqtt
parser.add_argument(
    '-m', '--mqtt', type=str, default='127.0.0.1',
    help='MQTT server ip')
parser.add_argument(
    '-p', '--port', type=int, default=1883,
    help='MQTT server port')
parser.add_argument(
    '-t', '--topic', type=str, action='append', nargs='+', help='MQTT topic(s)')
parser.add_argument(
    '-u', '--username', type=str, default=None, help='MQTT username')
parser.add_argument(
    '-P', '--password', type=str, default=None, help='MQTT password')

args = parser.parse_args()

# generate client ID with pub prefix randomly
client_id = f'python-mqtt-{random.randint(0, 99999999999)}'

def connect_mqtt() -> mqtt_client:
    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            print("Connected to MQTT Broker @ {}".format(args.mqtt))
        else:
            print("Failed to connect, return code %d\n", rc)

    client = mqtt_client.Client(client_id)
    if args.username != None:
        client.username_pw_set(args.username, args.password)
    client.on_connect = on_connect
    client.connect(args.mqtt, args.port)
    return client


def subscribe(client: mqtt_client):
    def on_message(client, userdata, msg):
        #data = json.loads(json.loads(str(msg.payload.decode())))
        data = json.loads(str(msg.payload.decode()))
        print(f"Received `{data}` from `{msg.topic}` topic")
        
    for tl in args.topic:
        for tn in tl:
            print(f"Subscribing to {tn}...")
            client.subscribe(tn)
    
    client.on_message = on_message


def run():
    client = connect_mqtt()
    subscribe(client)
    client.loop_forever()

if __name__ == '__main__':
    run()
