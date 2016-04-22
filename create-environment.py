#!/usr/bin/env python
from __future__ import print_function
import pyrax
import os
import time
import json
import sys
from jinja2 import Template
import urlparse
import urllib

'''
Example Env vars:

export OS_USERNAME=YOUR_USERNAME
export OS_REGION=LON
export OS_API_KEY=fc8234234205234242ad8f4723426cfe
export NODE_PASSWORD=iojl3458lkjalsdfkj
'''

# Consume our environment vars
app_name = os.environ.get('NAMESPACE', 'win')
environment_name = os.environ.get('ENVIRONMENT', 'stg')
initial_policy = os.environ.get('INITIAL_POLICY', 'Set to 2')
node_username = os.environ.get('NODE_USERNAME', 'localadmin')
node_password = os.environ.get('NODE_PASSWORD', 'Q1w2e3r4')
image_name = os.environ.get('NODE_IMAGE_NAME', "Windows Server 2012 R2")
image_id = os.environ.get('NODE_IMAGE_ID', None) # Deprecated
flavor_id = os.environ.get('NODE_FLAVOR_ID', "general1-2")
domain_name = os.environ.get('DOMAIN_NAME', None)

# The base URL for our bootstrap.ps1 and setup.ps1 scripts
base_script_url = os.environ.get('BASE_SCRIPT_URL', "https://raw.githubusercontent.com/iskandar/windows-automation-demo"
                                                    "/bootstrap/scripts")
setup_url = os.environ.get('SETUP_URL', "https://raw.githubusercontent.com/iskandar/windows-automation-demo"
                                        "/configurations/dsc/setup.json")
api_token = os.environ.get('SETUP_API_TOKEN', "")

# Authenticate
pyrax.set_setting("identity_type", "rackspace")
pyrax.set_setting("region", os.environ.get('OS_REGION', "LON"))
pyrax.set_credentials(os.environ.get('OS_USERNAME'), os.environ.get('OS_API_KEY'))

# Set up some aliases
cs = pyrax.cloudservers
cnw = pyrax.cloud_networks
clb = pyrax.cloud_loadbalancers
au = pyrax.autoscale
dns = pyrax.cloud_dns
imgs = pyrax.images

# Derived names
asg_name = app_name + "-" + environment_name
lb_name = asg_name + '-lb'
node_name = asg_name
subdomain_name = asg_name

# Other params
wait = True
wait_timeout = 1800

# Get the image ID from the name
for image in imgs.list_all():
    if image.name == image_name:
        print("Using image", image.name, image.id)
        image_id = image.id
        break

if image_id is None:
    raise Exception("Cannot find OS image " + image_name)

# Prepare data for server 'personalities', which is the only way to inject files and bootstrap Windows Servers
# in the Rackspace Public Cloud (as of 2016-03)
# Warning: If the contents of these files are too long (1000 bytes each?), then no servers will be created!
personality_dir = "./bootstrap/personality"
dest_dir = "C:\\cloud-automation"
personalities = [
    {
        "source" : personality_dir + "/bootstrap.cmd",
        "destination": dest_dir + "\\bootstrap.cmd"
    },
    {
        "source" : personality_dir + "/bootstrap-config.json",
        "destination": dest_dir + "\\bootstrap-config.json"
    },
    {
        "source" : personality_dir + "/bootstrap-shim.txt",
        "destination": dest_dir + "\\bootstrap-shim.txt"
    },
    {
        "source" : personality_dir + "/setup.url",
        "destination": dest_dir + "\\setup.url"
    },
    {
        "source" : personality_dir + "/setup-shim.txt",
        "destination": dest_dir + "\\setup-shim.txt"
    },
]

# Use templating with our personality files
template_vars = {
    "base_script_url": base_script_url,
    "setup_url": setup_url,
    "api_token": api_token,
    "rackspace_username": os.environ.get('OS_USERNAME'),
    "app_name": app_name,
    "environment_name": environment_name,
    "asg_name": asg_name,
    "lb_name": lb_name,
    "domain_name": domain_name,
    "subdomain_name": subdomain_name,
    "node_base_name": node_name,
    "node_username": node_username,
    "node_password": node_password
}
print("", file=sys.stderr)
print("--- Params", file=sys.stderr)
print(json.dumps(template_vars), file=sys.stderr)
print("---", file=sys.stderr)

# Build personality list with content
personality_list = []
for p in personalities:
    with open(p["source"], 'r') as content_file:
        content = content_file.read()
    template = Template(content)
    personality_list.append({
        "path": p["destination"],
        "contents": template.render(template_vars),
    })

print("", file=sys.stderr)
print("--- Personalities", file=sys.stderr)
print(json.dumps(personality_list), file=sys.stderr)
print("---", file=sys.stderr)

# Create a load balancer with a Health monitor
health_monitor = {
    "type": "HTTP",
    "delay": 10,
    "timeout": 5,
    "attemptsBeforeDeactivation": 2,
    "path": "/",
    "statusRegex": "^[23][0-9][0-9]$", # We do NOT want to match 4xx responses
    "bodyRegex": ".*CHEF_WINDOWS_DEMO_APP.*" # Parse for a specific string to avoid default IIS page false positives
}

lb = clb.create(lb_name, port=80, protocol="HTTP",
                nodes=[], virtual_ips=[clb.VirtualIP(type="PUBLIC")],
                algorithm="ROUND_ROBIN", healthMonitor=health_monitor)

if domain_name is not None:
    # Set up a DNS subdomain
    dns_records = []
    filtered = (vip for vip in lb.virtual_ips if vip.type == 'PUBLIC' and vip.ip_version == 'IPV4')
    for vip in filtered:
        dns_records.append({
            "type": "A",
            "name": subdomain_name + "." + domain_name,
            "data": vip.address,
            "ttl": 300,
        })

    # Look for our base domain
    filtered = (dom for dom in dns.list() if dom.name == domain_name)
    for dom in filtered:
        # Delete existing DNS records if any exist
        print("", file=sys.stderr)
        rec_iter = dns.get_record_iterator(dom)
        for rec in rec_iter:
            for add_rec in dns_records:
                if rec.name == add_rec["name"]:
                    print("Deleting DNS Record", repr(rec), file=sys.stderr)
                    rec.delete()

        # Add our DNS records
        print("--- Adding DNS Records", file=sys.stderr)
        print(repr(dns_records), file=sys.stderr)
        print("---", file=sys.stderr)
        dom.add_records(dns_records)
        break

# Add Scaling Policies
policies = [
    { "name": "Up by 1", "change": 1, "desired_capacity": None, "is_percent": False },
    { "name": "Up by 50%", "change": 50, "desired_capacity": None, "is_percent": True },
    { "name": "Up by 100%", "change": 100, "desired_capacity": None, "is_percent": True },
    { "name": "Up by 200%", "change": 200, "desired_capacity": None, "is_percent": True },
    { "name": "Down by 1", "change": -1, "desired_capacity": None, "is_percent": False },
    { "name": "Down by 50%", "change": -50, "desired_capacity": None, "is_percent": True },
    { "name": "Set to 0", "change": None, "desired_capacity": 0, "is_percent": False },
    { "name": "Set to 1", "change": None, "desired_capacity": 1, "is_percent": False },
    { "name": "Set to 2", "change": None, "desired_capacity": 2, "is_percent": False },
    { "name": "Set to 4", "change": None, "desired_capacity": 4, "is_percent": False },
    { "name": "Set to 6", "change": None, "desired_capacity": 6, "is_percent": False },
    { "name": "Set to 8", "change": None, "desired_capacity": 8, "is_percent": False },
]
# print repr(policies)

metadata = {
    "environment": environment_name,
    "role": "web",
    "app": app_name,
}
sg = au.create(asg_name,
               cooldown=60,
               min_entities=0, max_entities=16,
               launch_config_type="launch_server",
               server_name=node_name,
               image=image_id,
               flavor=flavor_id,
               disk_config="MANUAL",
               metadata=metadata,
               personality=personality_list,
               networks=[{ "uuid": cnw.PUBLIC_NET_ID }, { "uuid": cnw.SERVICE_NET_ID }],
               load_balancers=(lb.id, 80))

for p in policies:
    policy = sg.add_policy(p["name"], 'webhook', 60, p["change"],
                           p["is_percent"], desired_capacity=p["desired_capacity"])
    webhook = policy.add_webhook(p["name"] + ' webhook')
    if p["name"] == initial_policy:
        print("Executing policy", initial_policy, policy.id)
        policy.execute()

if wait:
    end_time = time.time() + wait_timeout
    infinite = wait_timeout == 0
    while infinite or time.time() < end_time:
        state = sg.get_state()
        print("Scaling Group State: ", json.dumps(state), file=sys.stderr)

        if state["pending_capacity"] == 0:
            if state["active_capacity"] == 0:
                print("ASG pending_capacity went to zero, but no active nodes! Something has gone wrong")
                sys.exit(1)
            break
        time.sleep(10)

print(json.dumps({
    "id": sg.id,
    "name": asg_name,
    "metadata": metadata,
}))