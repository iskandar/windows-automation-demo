#!/usr/bin/env python
from __future__ import print_function
import pyrax
import os
import json
import copy
import urllib
import urllib2

# Authenticate
pyrax.set_setting("identity_type", "rackspace")
pyrax.set_setting("region", os.environ.get('OS_REGION', "LON"))
pyrax.set_credentials(os.environ.get('OS_USERNAME'), os.environ.get('OS_API_KEY'))

# Set up some aliases
cs = pyrax.cloudservers

# Consume our environment vars
app_name = os.environ.get('NAMESPACE', 'win')
environment_name = os.environ.get('ENVIRONMENT', 'dev')
role_name = os.environ.get('ROLE', 'web')
parent_build_number = os.environ.get('BUILD_NUMBER', None)

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

print(json.dumps(target_nodes))
