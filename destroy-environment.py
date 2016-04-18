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
'''

# Consume our environment vars
app_name = os.environ.get('NAMESPACE', 'win')
environment_name = os.environ.get('ENVIRONMENT', 'stg')
domain_name = os.environ.get('DOMAIN_NAME', None)

# Authenticate
pyrax.set_setting("identity_type", "rackspace")
pyrax.set_setting("region", os.environ.get('OS_REGION', "LON"))
pyrax.set_credentials(os.environ.get('OS_USERNAME'), os.environ.get('OS_API_KEY'))

# Set up some aliases
clb = pyrax.cloud_loadbalancers
au = pyrax.autoscale
dns = pyrax.cloud_dns

# Derived names
asg_name = app_name + "-" + environment_name
lb_name = asg_name + '-lb'
subdomain_name = asg_name

# Try to find the ASG by naming convention.
# This is brittle and we should be rummaging in the launch_configuration metadata
filtered = (node for node in au.list() if
            node.name == asg_name)

for sg in filtered:
    print("Deleting ASG", repr(sg))
    sg.update(min_entities=0, max_entities=0)
    sg.delete()

# Find the LB by naming convention
filtered = (node for node in clb.list() if
            node.name == lb_name)

for lb in filtered:
    print("Deleting LB", repr(lb))
    lb.delete()

if domain_name is not None:
    filtered = (dom for dom in dns.list() if dom.name == domain_name)
    for dom in filtered:
        # Delete existing DNS records if any exist
        rec_iter = dns.get_record_iterator(dom)
        for rec in rec_iter:
            if rec.name == subdomain_name + '.' + domain_name:
                print("Deleting DNS Record", repr(rec))
                rec.delete()

print("Done")