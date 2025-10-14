#!/bin/bash

# Add the following to /etc/hosts
# 127.0.0.1	dev.appchat.cubby.bz
# 127.0.0.1	www.appchat.cubby.bz
# 127.0.0.1	dev-vote.appvote.cubby.bz
# 127.0.0.1	dev-results.appvote.cubby.bz
# 127.0.0.1	www.appvote.cubby.bz
# 127.0.0.1	results.appvote.cubby.bz
# 127.0.0.1	dev.apptique.cubby.bz
# 127.0.0.1	www.apptique.cubby.bz

# run from ..

# Triggers
cub trigger create --space default --allow-exists valid-k8s Mutation vet-schemas
cub trigger create --space default --allow-exists complete-k8s Mutation Kubernetes/YAML vet-placeholders
cub trigger create --space default --allow-exists context-k8s Mutation Kubernetes/YAML ensure-context true

# Filters
cub filter create --space default --allow-exists apply-not-completed Unit --where-field "LastAppliedRevisionNum != LiveRevisionNum"
cub filter create --space default --allow-exists unapplied-changes Unit --where-field "HeadRevisionNum > LiveRevisionNum AND TargetID IS NOT NULL"
cub filter create --space default --allow-exists not-approved Unit --where-field "HeadRevisionNum > LiveRevisionNum AND LEN(ApprovedBy) = 0"
cub filter create --space default --allow-exists has-apply-gates Unit --where-field "LEN(ApplyGates) > 0"
cub filter create --space default --allow-exists run-as-root Unit --where-field "ToolchainType = 'Kubernetes/YAML'" --resource-type "apps/v1/Deployment" --where-data "spec.template.spec.containers.*.|securityContext.runAsNonRoot != true"

# Dev cluster
kind create cluster --name dev --config setup/dev-cluster.yaml --kubeconfig dev.kubeconfig
export KUBECONFIG=dev.kubeconfig
flux install
#https://kind.sigs.k8s.io/docs/user/ingress
kubectl apply -f setup/deploy-ingress-nginx.yaml
#kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
cub space create --allow-exists platform-dev
cub worker create cluster-worker --space platform-dev --allow-exists
cub worker install cluster-worker --space platform-dev --env IN_CLUSTER_TARGET_NAME=dev-cluster --export --include-secret | kubectl apply -f -

# Prod cluster
kind create cluster --name prod --config setup/prod-cluster.yaml --kubeconfig prod.kubeconfig
export KUBECONFIG=prod.kubeconfig
flux install
kubectl apply -f setup/deploy-ingress-nginx.yaml
#kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
cub space create --allow-exists platform-prod
cub worker create cluster-worker --space platform-prod --allow-exists
cub worker install cluster-worker --space platform-prod --env IN_CLUSTER_TARGET_NAME=prod-cluster --export --include-secret | kubectl apply -f -

# NOTE: to upload the worker config (without the secret) to ConfigHub, use --unit
