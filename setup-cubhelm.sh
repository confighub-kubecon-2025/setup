#!/bin/bash

# git clone the following repos
#
# Helm charts
# https://github.com/confighub-kubecon-2025/appchat
# https://github.com/confighub-kubecon-2025/appvote
# https://github.com/confighub-kubecon-2025/apptique

# run from .., after setup/setup-clusters.sh

# Alternative to setup-cub.sh: import each application from its Helm chart
# rather than from its rendered manifests. Everything downstream of the import
# is the same -- base, deployments, release -- so the two scripts create
# separate components ("<app>-helm") and can be run side by side.
#
# `cub helm` is a cub plugin. Install it once with:
#
#   cub plugin install confighub/cub-helm
#
# `cub helm install <release> <chart>` renders the chart client-side and writes
# the result to the component's base space (<component>-base), plus a
# <component>-helm space recording the chart reference and values so that
# `cub helm upgrade` can re-render from it. Naming the components
# "<app>-helm" keeps the deployment spaces at the appchat-helm-dev /
# appchat-helm-prod of the original script; the chart-source space is then
# appchat-helm-helm. Charts that need cluster access to render (lookup,
# .Capabilities) or Helm's hook lifecycle are out of scope.
#
# The per-environment values files (values-dev.yaml / values-prod.yaml) are not
# passed here: the base is what every deployment shares, and per-deployment
# differences belong in the deployments, as in setup-cub.sh. Install a second
# component with --component if two environments genuinely need different
# renders of the chart.

set -e

# importChart <component> <chart-dir> <values-file> : render the chart into
# <component>-base and clone dev and prod deployments from it. --namespace is
# omitted on install, so the chart renders with the confighubplaceholder
# namespace that `cub variant create --namespace` fills in per deployment.
function importChart {
    local component="$1" chart="$2" values="$3"
    local app="${component%-helm}"

    cub helm install --component "$component" "$app" "$chart" --values "$values"

    cub variant create dev  "${component}-base" --environment dev  --namespace "$app" --region us --target dev/target
    cub variant create prod "${component}-base" --environment prod --namespace "$app" --region us --target prod/target
}

importChart appchat-helm  appchat             appchat/values.yaml
importChart appvote-helm  appvote             appvote/values.yaml
importChart apptique-helm apptique/helm-chart apptique/helm-chart/values.yaml

for space in appchat-helm-dev appvote-helm-dev apptique-helm-dev \
             appchat-helm-prod appvote-helm-prod apptique-helm-prod ; do
    cub unit approve --space "$space" --where "TargetID IS NOT NULL"
    cub release publish "$space"
done
