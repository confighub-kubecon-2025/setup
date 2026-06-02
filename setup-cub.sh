#!/bin/bash

# git clone the following repos
#
# Helm charts
# https://github.com/confighub-kubecon-2025/appchat
# https://github.com/confighub-kubecon-2025/appvote
# https://github.com/confighub-kubecon-2025/apptique
#
# run from .. (the kubecon directory), after setup/setup-clusters.sh has created
# the home space (triggers/filters), the platform-dev/platform-prod spaces, and
# the dev-cluster/prod-cluster targets.
#
# This version uses `cub variant upload` + `cub variant create`:
#   - Each application is uploaded once as a "base" variant from its rendered
#     manifests (one Unit per resource), in the confighubplaceholder namespace
#     and with no target.
#   - `cub variant create` clones a "dev" and a "prod" variant from each base,
#     each with `--namespace <app>` (set-namespace resolves the placeholder) and
#     `--environment dev|prod` (for target selection).
#   - Per-variant customizations (hostnames, env vars) are applied afterwards;
#     base-wide customizations (apptique images) are applied to the base before
#     cloning so both variants inherit them.
#
# Intra-space links (Service->Deployment selectors, namespace links, and
# ServiceAccount references) are inferred by `cub variant upload`. The previous
# hand-authored cross-component links (frontend->backend, etc.) are not inferable
# from the manifests; add them back with `cub link create` if the demo needs that
# topology in the graph.

set -e

homeSpaceID="$(cub space get home -o jq='.Space.SpaceID')"

PATTERN="template:{{.Labels.Component}}-{{.Labels.Variant}}"

# uploadBase <app> <manifest-file...> : upload the rendered manifests as the
# app's base variant and wire it to the home-space triggers so the dev/prod
# clones inherit them.
function uploadBase {
    local app="$1"; shift
    cub variant upload \
        --component "$app" --variant base \
        --space-pattern "$PATTERN" \
        --granularity per-resource \
        --namespace confighubplaceholder \
        --label "Application=${app}" \
        "$@"
    cub space update "${app}-base" --where-trigger "SpaceID = '${homeSpaceID}'"
}

# cloneVariants <app> : clone dev and prod variants from the app's base. Each
# variant gets its real namespace (set-namespace replaces confighubplaceholder)
# and an Environment label used to attach the cluster target.
function cloneVariants {
    local app="$1"
    cub variant create dev  "${app}-base" --space-pattern "$PATTERN" --environment dev  --namespace "$app"
    cub variant create prod "${app}-base" --space-pattern "$PATTERN" --environment prod --namespace "$app"
}

# clink <app> <from-unit> <to-unit> : create a cross-component (network)
# dependency link on the app's base space. These express that a consuming
# Deployment talks to a provider's Service; they are not inferable from the
# manifests (no Kubernetes reference between them). cub variant create clones
# them into the dev/prod variants.
function clink {
    cub link create --space "${1}-base" - "$2" "$3"
}

##########################
# appchat
##########################

uploadBase appchat appchat/base/postgres.yaml appchat/base/backend.yaml appchat/base/frontend.yaml

clink appchat deployment-frontend service-backend
clink appchat deployment-backend  service-postgres

cloneVariants appchat

# Customize dev and prod
cub function do --space appchat-dev --unit ingress-frontend-ingress --unit ingress-backend-ingress set-hostname dev.appchat.cubby.bz
cub function do --space appchat-dev --unit deployment-backend set-env-var backend CHAT_TITLE "AI Chat Dev"

cub function do --space appchat-prod --unit ingress-frontend-ingress --unit ingress-backend-ingress set-hostname www.appchat.cubby.bz
cub function do --space appchat-prod --unit deployment-backend set-env-var backend REGION NA
cub function do --space appchat-prod --unit deployment-backend set-env-var backend ROLE prod

##########################
# appvote
##########################

uploadBase appvote appvote/base/db.yaml appvote/base/redis.yaml appvote/base/result.yaml appvote/base/vote.yaml appvote/base/worker.yaml

clink appvote deployment-vote   service-redis
clink appvote deployment-worker service-redis
clink appvote deployment-result service-db
clink appvote deployment-worker service-db

cloneVariants appvote

# Customize dev and prod
cub function do --space appvote-dev --unit ingress-vote-ingress set-hostname dev-vote.appvote.cubby.bz
cub function do --space appvote-dev --unit ingress-result-ingress set-hostname dev-results.appvote.cubby.bz

cub function do --space appvote-prod --unit ingress-vote-ingress set-hostname www.appvote.cubby.bz
cub function do --space appvote-prod --unit ingress-result-ingress set-hostname results.appvote.cubby.bz

##########################
# apptique
##########################

# Upload all kubernetes-manifests except kustomization.yaml and loadgenerator.yaml.
apptique_files=()
for file in apptique/kubernetes-manifests/*.yaml ; do
    base="$(basename -s .yaml "$file")"
    if [[ "$base" != kustomization ]] && [[ "$base" != loadgenerator ]] ; then
        apptique_files+=("$file")
    fi
done
uploadBase apptique "${apptique_files[@]}"

# Pin every service to its pre-built image on the base, so dev and prod inherit
# it. The manifests carry bare image names (e.g. "adservice") on the "server"
# container; prepend the shared registry to those (that have none) and set the
# shared tag — two space-wide calls instead of one per service. Both are scoped
# to the "server" container so third-party images on other containers (the
# redis-cart "redis" container, busybox init containers) are left untouched.
cub function do --space apptique-base set-image-registry-by-registry "" "us-central1-docker.pkg.dev/google-samples/microservices-demo" server
cub function do --space apptique-base set-container-image-reference server ':v0.10.3'

clink apptique deployment-frontend              service-adservice
clink apptique deployment-frontend              service-recommendationservice
clink apptique deployment-frontend              service-productcatalogservice
clink apptique deployment-frontend              service-cartservice
clink apptique deployment-frontend              service-shippingservice
clink apptique deployment-frontend              service-currencyservice
clink apptique deployment-frontend              service-checkoutservice
clink apptique deployment-recommendationservice service-productcatalogservice
clink apptique deployment-checkoutservice       service-productcatalogservice
clink apptique deployment-checkoutservice       service-cartservice
clink apptique deployment-checkoutservice       service-shippingservice
clink apptique deployment-checkoutservice       service-currencyservice
clink apptique deployment-checkoutservice       service-paymentservice
clink apptique deployment-checkoutservice       service-emailservice

cloneVariants apptique

# Customize dev and prod
cub function do --space apptique-dev --unit ingress-frontend-ingress set-hostname dev.apptique.cubby.bz
cub function do --space apptique-prod --unit ingress-frontend-ingress set-hostname www.apptique.cubby.bz

##########################
# Attach targets
##########################

cub unit set-target --space "*" --where "Space.Labels.Environment = 'dev'" platform-dev/dev-cluster
cub unit set-target --space "*" --where "Space.Labels.Environment = 'prod'" platform-prod/prod-cluster

##########################
# Apply all the units
##########################

cub unit approve --space "*" --where "Labels.Application LIKE 'app%' AND TargetID IS NOT NULL"

cub unit apply --wait --space appchat-dev
cub unit apply --wait --space appvote-dev
cub unit apply --wait --space apptique-dev
cub unit apply --wait --space appchat-prod
cub unit apply --wait --space appvote-prod
cub unit apply --wait --space apptique-prod
cub tag create --space home post-initial-apply
cub unit tag --space "*" --where "Labels.Application LIKE 'app%' AND TargetID IS NOT NULL" --revision HeadRevisionNum home/post-initial-apply
cub unit refresh --space "*" --where "Labels.Application LIKE 'app%' AND TargetID IS NOT NULL"
cub tag create --space home post-refresh
cub unit tag --space "*" --where "Labels.Application LIKE 'app%' AND TargetID IS NOT NULL" --revision HeadRevisionNum home/post-refresh
