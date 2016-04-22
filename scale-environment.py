#!/usr/bin/env python

from __future__ import print_function
import pyrax
import os
from docopt import docopt

USAGE = """Scale a demo environment

Usage:
  scale-environment.py APP_NAME ENVIRONMENT [--policy_name=<p>]
  scale-environment.py (-h | --help)
  scale-environment.py --version

Arguments:
  APP_NAME              The application namespace. Should be unique within a Public Cloud Account.
  ENVIRONMENT           The name of the environment (e.g. stg, prd)

Options:
  -h --help             Show this screen.
  --policy_name=<p>     The scaling policy to trigger [default: Set to 2].

Environment variables:
  OS_REGION             A Rackspace Public Cloud region [default: LON]
  OS_USERNAME           A Rackspace Public Cloud username
  OS_API_KEY            A Rackspace Public Cloud API key
"""

# Parse our CLI arguments
arguments = docopt(USAGE, version='1.0.0')

# Set convenience variables from arguments/environment
app_name = arguments['APP_NAME']
environment_name = arguments['ENVIRONMENT']
policy_name = arguments['--policy_name']

# Authenticate
pyrax.set_setting("identity_type", "rackspace")
pyrax.set_setting("region", os.environ.get('OS_REGION', "LON"))
pyrax.set_credentials(os.environ.get('OS_USERNAME'), os.environ.get('OS_API_KEY'))

# Set up some aliases
au = pyrax.autoscale

# Try to find the ASG by naming convention.
# This is brittle and we should be rummaging in the launch_configuration metadata
filtered = (node for node in au.list() if
            node.name == app_name + '-' + environment_name)

sg = None
for asg in filtered:
    sg = asg
    break

policy_gen = (policy for policy in sg.list_policies() if
    policy.name == policy_name)

for policy in policy_gen:
    print("Executing Policy: ", policy.name, policy.id)
    policy.execute()
