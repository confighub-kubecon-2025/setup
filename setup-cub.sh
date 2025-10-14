#!/bin/bash

# git clone the following repos
#
# Helm charts
# https://github.com/confighub-kubecon-2025/appchat
# https://github.com/confighub-kubecon-2025/appvote
# https://github.com/confighub-kubecon-2025/apptique

CREATE_UNITS=1

# From Helm charts

cub space create --allow-exists appchat-helm-dev
cub space create --allow-exists appchat-helm-prod
cub space create --allow-exists appvote-helm-dev
cub space create --allow-exists appvote-helm--prod
cub space create --allow-exists apptique-helm-dev
cub space create --allow-exists apptique-helm-prod

if ! [[ -z "$CREATE_UNITS" ]] ; then
cub helm install --space appchat-helm-dev appchat appchat --values appchat/values.yaml --values appchat/values-dev.yaml 
cub helm install --space appchat-helm-prod appchat appchat --values appchat/values.yaml --values appchat/values-prod.yaml 
cub helm install --space appvote-helm-dev appvote appvote --values appvote/values.yaml --values appvote/values-dev.yaml
cub helm install --space appvote-helm-prod appvote appvote --values appvote/values.yaml --values appvote/values-prod.yaml
cub helm install --space apptique-helm-dev apptique apptique/helm-chart --values apptique/helm-chart/values.yaml --values apptique/helm-chart/values-dev.yaml
cub helm install --space apptique-helm-prod apptique apptique/helm-chart --values apptique/helm-chart/values.yaml --values apptique/helm-chart/values-prod.yaml
fi

# From components

cub space create --allow-exists appchat-dev
cub space create --allow-exists appchat-prod
cub space create --allow-exists appvote-dev
cub space create --allow-exists appvote-prod
cub space create --allow-exists apptique-dev
cub space create --allow-exists apptique-prod

if ! [[ -z "$CREATE_UNITS" ]] ; then
cub unit create --space appchat-dev --label Application=appchat database appchat/base/postgres.yaml
cub unit create --space appchat-dev --label Application=appchat backend appchat/base/backend.yaml
cub unit create --space appchat-dev --label Application=appchat frontend appchat/base/frontend.yaml
cub unit create --space appchat-prod --upstream-space appchat-dev --upstream-unit database database
cub unit create --space appchat-prod --upstream-space appchat-dev --upstream-unit backend backend
cub unit create --space appchat-prod --upstream-space appchat-dev --upstream-unit frontend frontend
cub function do --space appchat-dev --unit frontend --unit backend set-hostname dev.appchat.cubby.bz
cub function do --space appchat-dev --unit backend set-env-var backend CHAT_TITLE "AI Chat Dev"
cub function do --space appchat-prod --unit frontend --unit backend set-hostname www.appchat.cubby.bz
cub function do --space appchat-prod --unit backend set-env-var backend REGION NA
cub function do --space appchat-prod --unit backend set-env-var backend ROLE prod
cub function do --space appchat-dev ensure-namespaces
cub function do --space appchat-dev set-namespace appchat
cub function do --space appchat-prod ensure-namespaces
cub function do --space appchat-prod set-namespace appchat

for unit in db redis vote result worker ; do
cub unit create --space appvote-dev --label Application=appvote $unit appvote/base/${unit}.yaml
cub unit create --space appvote-prod --upstream-space appvote-dev --upstream-unit $unit $unit
done
cub function do --space appvote-dev --unit vote set-hostname dev-vote.appvote.cubby.bz
cub function do --space appvote-dev --unit result set-hostname dev-result.appvote.cubby.bz
cub function do --space appvote-prod --unit vote set-hostname vote.appvote.cubby.bz
cub function do --space appvote-prod --unit result set-hostname result.appvote.cubby.bz
cub function do --space appvote-dev ensure-namespaces
cub function do --space appvote-dev set-namespace appvote
cub function do --space appvote-prod ensure-namespaces
cub function do --space appvote-prod set-namespace appvote

for file in apptique/kubernetes-manifests/*.yaml ; do
unit="$(basename -s .yaml $file)"
if [[ "$unit" != kustomization ]] ; then
cub unit create --space apptique-dev --label Application=apptique $unit $file
cub unit create --space apptique-prod --upstream-space apptique-dev --upstream-unit $unit $unit
fi
done
cub function do --space apptique-dev --unit frontend set-hostname dev.apptique.cubby.bz
cub function do --space apptique-prod --unit frontend set-hostname www.apptique.cubby.bz
cub function do --space apptique-dev ensure-namespaces
cub function do --space apptique-dev set-namespace apptique
cub function do --space apptique-prod ensure-namespaces
cub function do --space apptique-prod set-namespace apptique
fi
