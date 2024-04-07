import os
import sys
import argparse
import json
import random
import base64
import requests

from datetime import datetime
from paho.mqtt import client as mqtt_client

def flatList(l):
    if l == None:
        return l
    r = []
    if isinstance(l, str):
        return [l]
    for sublist in l:
        if isinstance(sublist, str):
            r.append(sublist)
        else:
            for item in sublist:
                r.append(item)
    return r

def connect_mqtt() -> mqtt_client:
    def on_connect(client, userdata, flags, rc):
        if rc != 0:
            print("Failed to connect, return code %d\n", rc)

    client = mqtt_client.Client(client_id)
    if args.mqtt_username != None:
        client.username_pw_set(args.mqtt_username, args.mqtt_password)
    client.on_connect = on_connect
    client.connect(args.mqtt, args.port)
    return client


def subscribe(client: mqtt_client):
    def on_message(client, userdata, msg):
        try:
            if isinstance(msg.payload, dict):
                data = msg.payload
            else:
                data = json.loads(str(msg.payload.decode()))
        except:
              print(f'Error parsing payload: {msg.payload}')
              return
        
        ref_ts = int( datetime.now().timestamp() * 1000 )
        # translate mqtt message to nx witness event
        for i in data['events']:
            # https://localhost:7001/#/api-tool/rest-v1-devices-deviceid-bookmarks-post?version=current%20api
            obj = {
                "name": i['type'],
                "description": i['label'],
                "startTimeMs": ref_ts - 10000,
                "creationTimeMs": ref_ts,
                "durationMs": 30000,
                "tags": [ i['type'] ]
            }
            
            #print(f'-- event: {obj}')
            
            device = msg.topic
            
            if args.devices != None:
                k = 0
                for tn in args.topic:
                    if msg.topic == tn:
                        break
                    k += 1
                
                if k < len(args.devices):
                    device = args.devices[k]
            
            res = requests.post(
                '{}/rest/v1/devices/{}/bookmarks'.format(args.server, device),
                json=obj,
                headers={ 'Authorization': f'Bearer {args.auth}' },
                verify=False
            )
            
            obj = {
                "timestamp": datetime.utcnow().isoformat() + 'Z',
                "caption": i['type'],
                "description": i['label'],
                "eventType": "userDefinedEvent",
                "eventResourceId": '{' + device + '}',
                #"source": "demo",
                "metadata": json.dumps({ "cameraRefs": [ '{' + device + '}' ] })
            }
            
            #print(f'-- event: {obj}')
            
            res = requests.post(
                '{}/api/createEvent'.format(args.server),
                json=obj,
                headers={ 'Authorization': f'Bearer {args.auth}' },
                verify=False
            )
            
            print(f'-- {datetime.now().isoformat()} Event source: {msg.topic} device: {device} caption: {i["type"]} return code: {res.status_code} text: {res.text}')
        
        # print(f"Received `{data}` from `{msg.topic}` topic")
    
    for tn in args.topic:
        # print(f"Subscribing to {tn}...")
        client.subscribe(tn)
    
    client.on_message = on_message

def check_status(request, verbose):
    if request.status_code == requests.codes.ok:
        if verbose:
            print("Request successful\n{0}".format(request.text))
        return True
    print(request.url + " Request error {0}\n{1}".format(request.status_code, request.text))
    return False


def request_api(url, uri, method, **kwargs):
    server_url = f'{url}{uri}'
    response = requests.request(
        method,
        server_url,
        **kwargs
    )
    if not check_status(response, False):
        exit(1)
    if method == 'DELETE':
        return response
    return response.json()

def create_header(bearer_token):
    header = {"Authorization": f"Bearer {bearer_token}"}
    return header

def print_system_info(response):
    if 'reply' in response:
        system_info = response['reply']
        number_of_servers = len(system_info)
        system_name = system_info[0]['systemName']
    else:
        system_info = response
        number_of_servers = len(system_info)
        system_name = system_info[0]['systemName']
    print(f'System {system_name} contains {number_of_servers} server(s):')
    print(system_info)

def create_local_payload(user, password):
    payload = {
        'username': user,
        'password': password,
        'setCookie': False
    }
    return payload

def is_local_user(api_response):
    if api_response['username'] == 'admin':
        return True
    elif api_response['type'] == 'cloud':
        return False


def get_cloud_system_id(api_response):
    cloud_system_id = api_response['cloudId']
    return cloud_system_id

def is_expired(api_response):
    if int(api_response['expiresInS']) < 1:
        return True
    else:
        return False

def run():
    if args.auth == None and (args.username == None or args.password == None):
        print(f"Must specify either NX Witeness bearer auth or username and password")
        sys.exit(1)
    
    if args.auth == None:
        # print(f"Acquiring bearer token...")
        
        # STEP 1
        cloud_state = request_api(args.server, f'/rest/v1/login/users/{args.username}', 'GET', verify=False)
        if not is_local_user(cloud_state):
            print(args.username + ' is not a local user.')
            sys.exit(1)

        # STEP 2
        payload = create_local_payload(args.username, args.password)
        primary_session = request_api(args.server, '/rest/v1/login/sessions', 'POST', verify=False, json=payload)
        primary_token = primary_session['token']

        secondary_session = request_api(args.server, '/rest/v1/login/sessions', 'POST', verify=False, json=payload)
        secondary_token = secondary_session['token']

        # STEP 3
        primary_token_info = request_api(args.server, f'/rest/v1/login/sessions/{primary_token}', 'GET', verify=False)
        if is_expired(primary_token_info):
            print('Expired token')
            exit(1)

        secondary_token_info = request_api(args.server, f'/rest/v1/login/sessions/{secondary_token}', 'GET', verify=False)
        if is_expired(secondary_token_info):
            print('Expired token')
            exit(1)

        # STEP 4
        get_method_header = create_header(primary_token)
        system_info = request_api(args.server, f'/rest/v1/servers/*/info', 'GET', verify=False,
                                headers=get_method_header)
        # print_system_info(system_info)
        # print(f'Bearer token: {primary_token}')
        print(f'Sucessfully acquired bearer authentication token from {args.server}')
        args.auth = primary_token
    
    client = connect_mqtt()
    subscribe(client)
    client.loop_forever()

### MAIN ######################################################################

requests.packages.urllib3.disable_warnings() 
parser = argparse.ArgumentParser(description="Consumes a CVEDIA-RT MQTT queue and sends bookmarks / events out to a NX Witness instance via REST API")
# mqtt
parser.add_argument('-m', '--mqtt', type=str, default='127.0.0.1', help='MQTT server ip')
parser.add_argument('-p', '--port', type=int, default=1883, help='MQTT server port')
parser.add_argument('-t', '--topic', type=str, action='append', nargs='+', help='CVEDIA-RT MQTT topic(s)')
parser.add_argument('--mqtt_username', type=str, default=None, help='MQTT username')
parser.add_argument('--mqtt_password', type=str, default=None, help='MQTT password')

# nx witness
parser.add_argument('-d', '--devices', type=str, action='append', nargs='+', help='NX Witness device(s) ids, if not set will use topics as device names.')
parser.add_argument('-u', '--username', type=str, default=None, help='NX Witness username')
parser.add_argument('-P', '--password', type=str, default=None, help='NX Witness password')
parser.add_argument('-a', '--auth', type=str, default=None, help='Instead of username and password use a authorization bearer token')
parser.add_argument('-s', '--server', type=str, default="https://127.0.0.1:7001", help='NX Witness server, eg https://127.0.0.1:7001')

args = parser.parse_args()

args.topic = flatList(args.topic)
args.devices = flatList(args.devices)

# generate client ID with pub prefix randomly
client_id = f'python-mqtt-{random.randint(0, 100)}'

if __name__ == '__main__':
    run()
