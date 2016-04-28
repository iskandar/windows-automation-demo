#!/usr/bin/env python
from __future__ import print_function
import pyrax
import os
import json
from docopt import docopt


USAGE = """Get some nodes from an application environment

Usage:
  get-nodes.py APP_NAME ENVIRONMENT ROLE
  get-nodes.py (-h | --help)
  get-nodes.py --version

Arguments:
  APP_NAME              The application namespace. Should be unique within a Public Cloud Account.
  ENVIRONMENT           The name of the environment (e.g. stg, prd)
  ROLE                  A role name (e.g. web)

Options:
  -h --help             Show this screen.

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
role_name = arguments['ROLE']

# Authenticate
pyrax.set_setting("identity_type", "rackspace")
pyrax.set_setting("region", os.environ.get('OS_REGION', "LON"))
pyrax.set_credentials(os.environ.get('OS_USERNAME'), os.environ.get('OS_API_KEY'))

# Set up some aliases
cs = pyrax.cloudservers

# Filter our nodes on app, environment, and role metadata
filtered = (node for node in cs.list() if
            "app" in node.metadata and
            node.metadata["app"] == app_name and
            "environment" in node.metadata and
            node.metadata["environment"] == environment_name and
            "role" in node.metadata and
            node.metadata["role"] == role_name)

# Build a JSON-friendly list of nodes
target_nodes = []
for node in filtered:
    target_nodes.append({
        "name": node.name,
        "id": node.id,
        "ip": node.accessIPv4,
        "metadata": node.metadata,
    })

print(json.dumps(target_nodes, indent=4, separators=(',', ': ')))
