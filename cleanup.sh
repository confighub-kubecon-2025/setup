#!/bin/bash

# Be careful running this if you have anything else in your organization

# Deletes the kind cluster and Argo CD along with the ConfigHub config
# `cub cluster up` created: the cluster space (worker + OCI target), the
# argo-apps space, the argobot variant space, and every deployment space bound
# to the cluster's target. --force lets it delete the local cluster even when
# the matching space is already gone.
cub cluster down --name dev --delete-config --force
cub cluster down --name prod --delete-config --force

# What is left: the component base spaces (and the helm source spaces, if
# setup-cubhelm.sh was used), which have no target.
cub space delete --recursive --where "Slug LIKE 'app%'"
cub space delete --recursive home
