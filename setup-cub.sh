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
#   - Ingress hostnames are driven by a per-app "Subdomain" AppConfig/YAML Unit
#     and a TransformPaths Link (set-hostname = <Subdomain>.<Component>.cubby.bz,
#     Component from the Space label). Each variant just sets its Subdomain field
#     and AutoUpdate re-derives the hostname. Other per-variant customizations
#     (env vars) and base-wide ones (apptique images) are applied directly.
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
        "$@"
    cub space update "${app}-base" --where-trigger "SpaceID = '${homeSpaceID}'"
}

# cloneVariants <app> : clone dev and prod variants from the app's base. Each
# variant gets its real namespace (set-namespace replaces confighubplaceholder)
# and an Environment label used to attach the cluster target.
function cloneVariants {
    local app="$1"
    cub variant create dev  "${app}-base" --space-pattern "$PATTERN" --environment dev  --namespace "$app" --region us --target platform-dev/dev-cluster
    cub variant create prod "${app}-base" --space-pattern "$PATTERN" --environment prod --namespace "$app" --region us --target platform-prod/prod-cluster
}

# clink <app> <from-unit> <to-unit> : create a cross-component (network)
# dependency link on the app's base space. These express that a consuming
# Deployment talks to a provider's Service; they are not inferable from the
# manifests (no Kubernetes reference between them). cub variant create clones
# them into the dev/prod variants.
function clink {
    cub link create --space "${1}-base" - "$2" "$3"
}

# subdomainLinks <app> <subdomain-name> <ingress-unit>... : in <app>-base, create
# an AppConfig/YAML "Subdomain" Unit (configName <subdomain-name>, schema
# IngressConfig) holding a placeholder subdomain, then a TransformPaths Link from
# each given ingress Unit. Each Link derives the ingress hostname as
# "<Subdomain>.<Component>.cubby.bz" — the Subdomain from the Unit, the Component
# from the Space label — via set-hostname, and AutoUpdates whenever the Subdomain
# field changes (including in the cloned dev/prod variants).
function subdomainLinks {
    local app="$1" name="$2"; shift 2
    cat <<EOF | cub unit create --space "${app}-base" --toolchain AppConfig/YAML "$name" -
configHub:
  configName: ${name}
  configSchema: IngressConfig
Subdomain: confighubplaceholder
EOF
    local ingress
    for ingress in "$@" ; do
        cat <<EOF | cub link create --space "${app}-base" - "$ingress" "$name" --update-type TransformPaths --auto-update --from-stdin
UpstreamPaths:
  - Name: Subdomain
    Path: Subdomain
    Resource:
      ResourceName: ${name}
      ResourceType: IngressConfig
DownstreamSetters:
  - Parameters: [Subdomain]
    FunctionInvocation:
      FunctionName: set-hostname
      Arguments:
        - Value: "{{.Params.Subdomain}}.{{.SpaceLabels.Component}}.cubby.bz"
          Evaluator: template
EOF
    done
}

# setSubdomain <space> <subdomain-unit> <value> : set the Subdomain field on the
# AppConfig/YAML Unit; its TransformPaths Link AutoUpdates the ingress hostname.
function setSubdomain {
    cub function set --space "$1" --unit "$2" --toolchain AppConfig/YAML set-string-path IngressConfig Subdomain "$3"
}

##########################
# Shared ingress-hostname schema (referenced by every app's Subdomain Unit)
##########################

cat <<'EOF' | cub unit create --space home --toolchain AppConfig/JSON ingress-config-schema -
{
  "configHub": { "configName": "IngressConfig", "configSchema": "JSONSchema" },
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "IngressConfig",
  "type": "object",
  "properties": { "Subdomain": { "type": "string" } },
  "required": ["Subdomain"]
}
EOF

##########################
# appchat
##########################

uploadBase appchat appchat/base/postgres.yaml appchat/base/backend.yaml appchat/base/frontend.yaml

clink appchat deployment-frontend service-backend
clink appchat deployment-backend  service-postgres

# Both ingresses share one Subdomain (dev/www).
subdomainLinks appchat app-ingress ingress-frontend-ingress ingress-backend-ingress

cloneVariants appchat

# Customize dev and prod
setSubdomain appchat-dev app-ingress dev
cub function set --space appchat-dev --unit deployment-backend set-env-var backend CHAT_TITLE "AI Chat Dev"

setSubdomain appchat-prod app-ingress www
cub function set --space appchat-prod --unit deployment-backend set-env-var backend REGION us
cub function set --space appchat-prod --unit deployment-backend set-env-var backend ROLE prod

##########################
# appvote
##########################

uploadBase appvote appvote/base/db.yaml appvote/base/redis.yaml appvote/base/result.yaml appvote/base/vote.yaml appvote/base/worker.yaml

clink appvote deployment-vote   service-redis
clink appvote deployment-worker service-redis
clink appvote deployment-result service-db
clink appvote deployment-worker service-db

# vote and result have distinct subdomains, so each gets its own Subdomain Unit.
subdomainLinks appvote vote-ingress   ingress-vote-ingress
subdomainLinks appvote result-ingress ingress-result-ingress

cloneVariants appvote

# Customize dev and prod
setSubdomain appvote-dev  vote-ingress   dev-vote
setSubdomain appvote-dev  result-ingress dev-results

setSubdomain appvote-prod vote-ingress   www
setSubdomain appvote-prod result-ingress results

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
cub function set --space apptique-base set-image-registry-by-registry "" "us-central1-docker.pkg.dev/google-samples/microservices-demo" server
cub function set --space apptique-base set-container-image-reference server ':v0.10.3'

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

# Single frontend ingress.
subdomainLinks apptique app-ingress ingress-frontend-ingress

cloneVariants apptique

# Customize dev and prod
setSubdomain apptique-dev  app-ingress dev
setSubdomain apptique-prod app-ingress www

##########################
# Apply all the units
##########################

cub unit approve --space "*" --where "Labels.Component LIKE 'app%' AND TargetID IS NOT NULL"

cub unit apply --wait --space appchat-dev
cub unit apply --wait --space appvote-dev
cub unit apply --wait --space apptique-dev
cub unit apply --wait --space appchat-prod
cub unit apply --wait --space appvote-prod
cub unit apply --wait --space apptique-prod
cub tag create --space home post-initial-apply
cub unit tag --space "*" --where "Labels.Component LIKE 'app%' AND TargetID IS NOT NULL" --revision HeadRevisionNum home/post-initial-apply
cub unit refresh --space "*" --where "Labels.Component LIKE 'app%' AND TargetID IS NOT NULL"
cub tag create --space home post-refresh
cub unit tag --space "*" --where "Labels.Component LIKE 'app%' AND TargetID IS NOT NULL" --revision HeadRevisionNum home/post-refresh
