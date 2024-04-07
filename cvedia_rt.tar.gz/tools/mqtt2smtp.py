import os
import sys
import argparse
import json
import random
import base64

from paho.mqtt import client as mqtt_client

import smtplib

from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart

parser = argparse.ArgumentParser(description="Consumes a MQTT queue and sends emails out")
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

# smtp
parser.add_argument(
    '-s', '--smtp', type=str, default=None, help='SMTP server, eg: smtp.gmail.com')
parser.add_argument(
    '-i', '--smtp_port', type=int, default=587, help='SMTP server port')
parser.add_argument(
    '-M', '--smtp_username', type=str, default=None, help='SMTP username')
parser.add_argument(
    '-w', '--smtp_password', type=str, default=None, help='SMTP password')
parser.add_argument(
    '-S', '--smtp_from', type=str, default='cvedia@cvedia.com', help='SMTP sender email')
parser.add_argument(
    '-T', '--smtp_to', type=str, default='cvedia@cvedia.com', help='SMTP receiver email')

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
        try:
            data = json.loads(json.loads(str(msg.payload.decode())))
        except:
            data = json.loads(str(msg.payload.decode()))
        
        # print(f"Received `{data}` from `{msg.topic}` topic")
        
        if args.smtp != None:
            if 'nvr_sn' not in data:
                data['nvr_sn'] = msg.topic
            if 'alarm_name' not in data:
                data['alarm_name'] = 'unknown'
            
            mail_content = '''NVR NAME:      {}
NVR S/N:       {}
ALARM NAME(NUM):    {} {}
'''.format(data['frame_id'], data['nvr_sn'], data['alarm_name'], data['frame_id'])
            
            message = MIMEMultipart()
            message['From'] = args.smtp_from
            message['To'] = args.smtp_to
            message['Subject'] = 'Alarm from NVR #{}'.format(data['nvr_sn'])
            
            #The body and the attachments for the mail
            message.attach(MIMEText(mail_content, 'plain'))
            message.attach(MIMEImage(base64.b64decode(data['image']), name='image.jpg'))
            
            #Create SMTP session for sending the mail
            session = smtplib.SMTP(args.smtp, args.smtp_port)
            session.starttls() # enable security
            session.login(args.smtp_from, args.smtp_password)
            
            text = message.as_string()
            session.sendmail(args.smtp_from, args.smtp_to, text)
            session.quit()

            print('-- Email sent to: {} subject: {}'.format(args.smtp_to, message['Subject']))

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
