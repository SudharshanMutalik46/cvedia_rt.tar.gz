import os
import sys
import argparse
import json
import random
import base64
import requests
import time

parser = argparse.ArgumentParser(description="Clones an existing instance with customizable inputs / outputs")

# cvedia-rt
parser.add_argument('-a', '--api', type=str, default='http://127.0.0.1:8080', help='CVEDIA-RT REST API address')
parser.add_argument('-s', '--solution', type=str, required=True, help='Solution scope')
parser.add_argument('-b', '--base_instance', type=str, required=True, help='Base instance')
parser.add_argument('-n', '--new_instance', type=str, required=True, help='New instance name')
parser.add_argument('-i', '--input', type=str, default=None, help='New instance input uri')
parser.add_argument('-o', '--output', type=str, default=None, help='New instance output uri')
parser.add_argument('-K', '--sink', type=str, default=None, help='New instance output sink name')
parser.add_argument('-S', '--start', default=False, action='store_true', help='Start new instance after cloning')
parser.add_argument('-H', '--handler', type=str, default='Output', help='Output handler name within the new instance')
parser.add_argument('-v', '--verbose', default=False, action='store_true', help='Enable verbose mode')

args = parser.parse_args()

def req(uri, method, check, **kwargs):
    url = f'{args.api}{uri}'
    response = requests.request(
        method,
        url,
        verify=False,
        **kwargs
    )
    
    if check == False:
        return response
    
    if response.status_code > 299:
        print(f'Error code: {response.status_code} response: {response.text}')
        sys.exit(1)
    
    output = response.json()
    
    if args.verbose:
        print(f'-- API Request to: {url} response: {json.dumps(output)}')
        
    return output

def check_instance(solution, instance):
    res = req('/api/instance/get', 'GET', True)
    check = False
    for r in res:
        try:
            if r['instance_name'] == args.base_instance and r['solution'] == args.solution:
                check = True
                break
        except:
            pass
    
    return check    

def check_instance_to(solution, instance, mode, retries = 30):
    check = False
    while retries > 0:
        res = req('/api/instance/get', 'GET', False)
        if res.status_code <= 299:
            data = res.json()
            
            for r in data:
                try:
                    if r['instance_name'] == instance and r['solution'] == solution:
                        if mode == 'exists':
                            check = True
                            break
                        elif mode == 'running':
                            if int(r['state']) == 4:
                                check = True
                                break
                            elif int(r['state']) == 2:
                                print('-- Instance started but is in error state, please check CVEDIA-RT logs.')
                                sys.exit(1)
                except:
                    pass
        
        if check:
            break
        
        retries -= 1
        time.sleep(1)
    
    return check

def run():
    print('-- Checking if base instance exists...')
    
    if not check_instance(args.solution, args.base_instance):
        print(f'-- Unable to find instance: {args.base_instance} in solution: {args.solution}')
        sys.exit(1)
    
    print('-- Cloning base instance...')
    req('/api/instance/add', 'POST', True, json={
        "instance_name": args.new_instance,
        "base_on_instance": args.base_instance,
        "solution": args.solution
    })
    
    time.sleep(1)
    req('/api/solution/reload', 'GET', False)
    
    if not check_instance_to(args.solution, args.new_instance, 'exists'):
        print('-- Timed out waiting for new instance to be created')
        sys.exit(1)
    
    if args.input is not None or args.output is not None or args.sink is not None:
        print('-- Starting new instance...')
        req('/api/instance/start', 'POST', True, json={
            "instance_name": args.new_instance,
            "solution": args.solution
        })
        
        print('-- Waiting for instance to start...')
        if not check_instance_to(args.solution, args.new_instance, 'running', 120):
            print('-- Timed out waiting for new instance to be started')
            sys.exit(1)
        
        if args.input is not None:
            print('-- Configuring input...')
            req('/api/instance/set_state', 'POST', True, json={
                "instance_name": args.new_instance,
                "solution": args.solution,
                "path": "Input/uri",
                "value": args.input
            })
        
        if args.output is not None:
            print('-- Configuring output...')
            req('/api/instance/set_state', 'POST', True, json={
                "instance_name": args.new_instance,
                "solution": args.solution,
                "path": "Output/handlers",
                "value": {
                    f"{args.handler}": {
                        "enabled": True,
                        "uri": args.output
                    }
                }
            })
        
        if args.sink is not None:
            print('-- Configuring output sink...')
            req('/api/instance/set_state', 'POST', True, json={
                "instance_name": args.new_instance,
                "solution": args.solution,
                "path": f"Output/handlers/{args.handler}/sink",
                "value": args.sink
            })
    
        print('-- Saving...')
        req('/api/instance/save_state', 'POST', True, json={
            "instance_name": args.new_instance,
            "solution": args.solution
        })
        
        print('-- Stopping new instance...')
        req('/api/instance/stop', 'POST', True, json={
            "instance_name": args.new_instance,
            "solution": args.solution
        })
    
    if args.start:
        print('-- Starting new instance...')
        req('/api/instance/start', 'POST', True, json={
            "instance_name": args.new_instance,
            "solution": args.solution
        })
        
        print('-- Waiting for instance to start...')
        if not check_instance_to(args.solution, args.new_instance, 'running', 120):
            print('-- Timed out waiting for new instance to be started')
            sys.exit(1)
        
        print('-- Final running instance state:', json.dumps(req('/api/instance/get_state', 'GET', True, params={
            "instance_name": args.new_instance,
            "solution": args.solution
        })))
    
    print(f'-- Completed, created new instance: {args.new_instance} from: {args.base_instance} in solution: {args.solution}')

if __name__ == '__main__':
    run()
