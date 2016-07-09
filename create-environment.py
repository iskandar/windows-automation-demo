#!/usr/bin/env python

from __future__ import print_function
import pyrax
import os
import time
import json
import sys
from jinja2 import Template
from docopt import docopt

USAGE = """Create a demo environment

Usage:
  create-environment.py APP_NAME ENVIRONMENT
                        [--bootstrap_type=<t>]
                        [--initial_policy=<p>]
                        [--node_username=<u>]
                        [--node_password=<pw>]
                        [--image_name=<i>]
                        [--flavor_id=<f>]
                        [--domain_name=<d>]
                        [--base_script_url=<u>]
                        [--setup_url=<u>]
                        [--api_token=<t>]
                        [--aa_dsc_reg_url=<u>]
                        [--aa_dsc_reg_key=<k>]
                        [--aa_dsc_node_config_name=<n>]
  create-environment.py (-h | --help)
  create-environment.py --version

Arguments:
  APP_NAME              The application namespace. Should be unique within a Public Cloud Account.
  ENVIRONMENT           The name of the environment (e.g. stg, prd)

Options:
  -h --help                     Show this screen.
  --bootstrap_type=<t>          The server bootstrap type ('dsc' or 'chef') [default: dsc].
  --initial_policy=<p>          The initial scaling policy to trigger after creation [default: Set to 2].
  --node_username=<u>           The local admin username [default: localadmin].
  --node_password=<pw>          The local admin password [default: Q1w2e3r4].
  --image_name=<i>              The Rackspace Public Cloud server image name [default: Windows Server 2012 R2].
  --flavor_id=<f>               The Rackspace Public Cloud server flavor ID [default: general1-2].
  --domain_name=<d>             A base domain name to use for subdomains
  --base_script_url=<u>         The base URL for our bootstrap.ps1 and setup.ps1 scripts
                                [default: https://raw.githubusercontent.com/iskandar/windows-automation-demo/bootstrap/scripts].
  --setup_url=<u>               The URL for a setup.json manifest file
                                [default: https://raw.githubusercontent.com/iskandar/windows-automation-demo/configurations/dsc/setup.json].
  --api_token=<t>               An API token added to callback and script URLs.
  --aa_dsc_reg_url=<u>          An Azure Automation DSC Registration URL
  --aa_dsc_reg_key=<k>          An Azure Automation DSC Registration Key
  --aa_dsc_node_config_name=<n> An Azure Automation DSC Node Configuration Name

Environment variables:
  OS_REGION               A Rackspace Public Cloud region (default: LON)
  OS_USERNAME             A Rackspace Public Cloud username
  OS_API_KEY              A Rackspace Public Cloud API key
  NODE_PASSWORD           The Cloud Server local admin password (overrides any value specified with --node_password)
  SETUP_API_TOKEN         An API token added to callback and script URLs (overrides any value specified with --api_token)
  AA_DSC_REG_URL          An Azure Automation DSC Registration URL (overrides any value specified with --aa_dsc_reg_url)
  AA_DSC_REG_KEY          An Azure Automation DSC Registration Key (overrides any value specified with --aa_dsc_reg_key)
  AA_DSC_NODE_CONFIG_NAME An Azure Automation DSC Node Configuration Name (overrides any value specified with --aa_dsc_node_config_name)
"""

# Parse our CLI arguments
arguments = docopt(USAGE, version='1.0.0')

# Set convenience variables from arguments/environment
bootstrap_type = arguments['--bootstrap_type']
app_name = arguments['APP_NAME']
environment_name = arguments['ENVIRONMENT']

initial_policy = arguments['--initial_policy']
node_username = arguments['--node_username']
node_password = os.environ.get('NODE_PASSWORD', arguments['--node_password'])
image_name = arguments['--image_name']
flavor_id = arguments['--flavor_id']
domain_name = arguments['--domain_name']

# The base URL for our bootstrap.ps1 and setup.ps1 scripts
base_script_url = arguments['--base_script_url']
setup_url = arguments['--setup_url']
api_token = os.environ.get('SETUP_API_TOKEN', arguments['--api_token'])

# Azure Automation params
aa_dsc_reg_url = os.environ.get('AA_DSC_REG_URL', arguments['--aa_dsc_reg_url'])
aa_dsc_reg_key = os.environ.get('AA_DSC_REG_KEY', arguments['--aa_dsc_reg_key'])
aa_dsc_node_config_name = os.environ.get('AA_DSC_NODE_CONFIG_NAME', arguments['--aa_dsc_node_config_name'])

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
image_id = None
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
    "bootstrap_type": bootstrap_type,
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
    "node_password": node_password,
    "aa_dsc_reg_url": aa_dsc_reg_url,
    "aa_dsc_reg_key": aa_dsc_reg_key,
    "aa_dsc_node_config_name": aa_dsc_node_config_name
}
print("", file=sys.stderr)
print("--- Params", file=sys.stderr)
print(json.dumps(template_vars, indent=4, separators=(',', ': ')), file=sys.stderr)
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
print(json.dumps(personality_list, indent=4, separators=(',', ': ')), file=sys.stderr)
print("---", file=sys.stderr)

# Create a load balancer with a Health monitor
health_monitor = {
    "type": "HTTP",
    "delay": 10,
    "timeout": 5,
    "attemptsBeforeDeactivation": 2,
    "path": "/",
    "statusRegex": "^[23][0-9][0-9]$", # We do NOT want to match 4xx responses
    "bodyRegex": ".*WINDOWS_AUTOMATION_DEMO.*" # Parse for a specific string to avoid default IIS page false positives
}

lb = clb.create(lb_name, port=80, protocol="HTTP",
                nodes=[], virtual_ips=[clb.VirtualIP(type="PUBLIC")],
                algorithm="ROUND_ROBIN", healthMonitor=health_monitor)

if domain_name is not None and domain_name is not '':
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
    "bootstrap_type": bootstrap_type
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
               networks=[{"uuid": cnw.PUBLIC_NET_ID}, {"uuid": cnw.SERVICE_NET_ID}],
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
        print("Scaling Group State: ", json.dumps(state, indent=4, separators=(',', ': ')), file=sys.stderr)

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
}, indent=4, separators=(',', ': ')))
