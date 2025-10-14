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

kind create cluster --name dev --config setup/dev-cluster.yaml --kubeconfig dev.kubeconfig
export KUBECONFIG=dev.kubeconfig
flux install
#https://kind.sigs.k8s.io/docs/user/ingress
kubectl apply -f setup/deploy-ingress-nginx.yaml
#kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
cub space create --allow-exists platform-dev
cub worker create cluster-worker --space platform-dev --allow-exists
cub worker install cluster-worker --space platform-dev --env IN_CLUSTER_TARGET_NAME=dev-cluster --export --include-secret | kubectl apply -f -

kind create cluster --name prod --config setup/prod-cluster.yaml --kubeconfig prod.kubeconfig
export KUBECONFIG=prod.kubeconfig
flux install
kubectl apply -f setup/deploy-ingress-nginx.yaml
#kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
cub space create --allow-exists platform-prod
cub worker create cluster-worker --space platform-prod --allow-exists
cub worker install cluster-worker --space platform-prod --env IN_CLUSTER_TARGET_NAME=prod-cluster --export --include-secret | kubectl apply -f -

# NOTE: to upload the worker config (without the secret) to ConfigHub, use --unit
