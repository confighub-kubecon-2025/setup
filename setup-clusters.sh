#!/bin/bash

# run from ..

# setupCluster <name> : bring up a kind cluster wired into ConfigHub, then
# install ingress-nginx into it.
#
# `cub cluster up` creates the kind cluster, installs Argo CD, and provisions
# the ConfigHub side: the <name> space holding a server-hosted OCI worker and
# the <name>/target OCI target, plus a <name>-argo-apps space holding the root
# "app of apps". Nothing runs in the cluster on ConfigHub's behalf -- Argo pulls
# each space's Release from ConfigHub's OCI registry -- so there is no worker
# process to install.
#
# `cub cluster up` reserves a 10-port window on the kind node
# (hostPort == containerPort). The first port is Argo CD's; the rest are free
# NodePorts, so ingress-nginx gets the next two. That is why the app URLs carry
# a per-cluster port rather than the fixed 11080/12080 of a hand-written kind
# config: the window is picked at cluster-creation time from what is free.
function setupCluster {
    local name="$1"

    cub cluster up --name "$name" || return 1

    local argoPort httpPort httpsPort
    argoPort="$(cub space get "$name" -o jq='.Space.Annotations["confighub.com/cluster-argo-port"]')"
    if [[ -z "$argoPort" ]] ; then
        echo "could not read the Argo CD port from space ${name}" >&2
        return 1
    fi
    httpPort=$((argoPort + 1))
    httpsPort=$((argoPort + 2))

    export KUBECONFIG="${CUB_CONFIG:-$HOME/.confighub}/clusters/${name}.kubeconfig"

    #https://kind.sigs.k8s.io/docs/user/ingress
    kubectl apply -f setup/deploy-ingress-nginx.yaml
    #kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml

    # The manifest's controller Service is a LoadBalancer, which never gets an
    # address on kind. Republish it on the two NodePorts the cluster's window
    # maps through to the host.
    kubectl --namespace ingress-nginx patch service ingress-nginx-controller --type merge --patch \
        "{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"targetPort\":\"http\",\"nodePort\":${httpPort}},{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\",\"targetPort\":\"https\",\"nodePort\":${httpsPort}}]}}"

    echo "${name}: ingress on http://localhost:${httpPort} (https ${httpsPort}), Argo CD on http://localhost:${argoPort}"
}

cub space create --allow-exists home

# Triggers
cub trigger create --space home --allow-exists valid-k8s Mutation Kubernetes/YAML vet-schemas
cub trigger create --space home --allow-exists complete-k8s Mutation Kubernetes/YAML vet-placeholders
# Disable this trigger initially so that it doesn't block the initial release
cub trigger create --space home --allow-exists --disable ensure-nonroot Mutation Kubernetes/YAML vet-celexpr "r.kind != 'Deployment' || (r.spec.template.spec.securityContext.runAsNonRoot == true && r.spec.template.spec.containers.all(container, !has(container.securityContext.runAsNonRoot) || container.securityContext.runAsNonRoot == true)) || r.spec.template.spec.containers.all(container, has(container.securityContext.runAsNonRoot) && container.securityContext.runAsNonRoot == true)"

# Filters
cub filter create --space home --allow-exists unapplied-changes Unit --where-field "HeadRevisionNum > LastReleasedRevisionNum AND TargetID IS NOT NULL"
cub filter create --space home --allow-exists not-approved Unit --where-field "HeadRevisionNum > LastReleasedRevisionNum AND LEN(ApprovedBy) = 0"
cub filter create --space home --allow-exists has-apply-gates Unit --where-field "LEN(ApplyGates) > 0"
cub filter create --space home --allow-exists run-as-root Unit --where-field "ToolchainType = 'Kubernetes/YAML'" --resource-type "apps/v1/Deployment" --where-data "spec.template.spec.|securityContext.runAsNonRoot != true AND spec.template.spec.containers.*.|securityContext.runAsNonRoot != true"
cub filter create --space home --allow-exists kubernetes Unit --where-field "ToolchainType = 'Kubernetes/YAML'"

# Dev cluster
setupCluster dev

# Prod cluster
setupCluster prod
