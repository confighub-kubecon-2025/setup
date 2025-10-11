#!/bin/bash

# git clone the following repos
#
# Helm charts
# https://github.com/confighub-kubecon-2025/appchat
# https://github.com/confighub-kubecon-2025/appvote
# https://github.com/confighub-kubecon-2025/apptique
#
# Plain YAML
# https://github.com/confighubai/cubbychat
# https://github.com/dockersamples/example-voting-app

# From Helm charts

cub space create appchat-helm-dev
cub space create appchat-helm-prod
cub space create appvote-helm-dev
cub space create appvote-helm--prod
cub space create apptique-helm-dev
cub space create apptique-helm-prod

if ! [[ -z "$CREATE_UNITS" ]] ; then
cub helm install --space appchat-helm-dev appchat appchat --values appchat/values.yaml --values appchat/values-dev.yaml 
cub helm install --space appchat-helm-prod appchat appchat --values appchat/values.yaml --values appchat/values-prod.yaml 
cub helm install --space appvote-helm-dev appvote appvote --values appvote/values.yaml --values appvote/values-dev.yaml
cub helm install --space appvote-helm-prod appvote appvote --values appvote/values.yaml --values appvote/values-prod.yaml
cub helm install --space apptique-helm-dev apptique apptique/helm-chart --values apptique/helm-chart/values.yaml --values apptique/helm-chart/values-dev.yaml
cub helm install --space apptique-helm-prod apptique apptique/helm-chart --values apptique/helm-chart/values.yaml --values apptique/helm-chart/values-prod.yaml
fi

# From components

cub space create appchat-dev
cub space create appchat-prod
cub space create appvote-dev
cub space create appvote-prod
cub space create apptique-dev
cub space create apptique-prod

if ! [[ -z "$CREATE_UNITS" ]] ; then
cub unit create --space appchat-dev --label Application=appchat database cubbychat/database/postgres.yaml
cub unit create --space appchat-dev --label Application=appchat backend cubbychat/backend/backend-no-ai.yaml
cub unit create --space appchat-dev --label Application=appchat frontend cubbychat/frontend/frontend.yaml
# TODO: Use a bulk clone
cub unit create --space appchat-prod --upstream-space appchat-dev --upstream-unit database database
cub unit create --space appchat-prod --upstream-space appchat-dev --upstream-unit backend backend
cub unit create --space appchat-prod --upstream-space appchat-dev --upstream-unit frontend frontend
cub function do --space appchat-dev --unit frontend --unit backend set-hostname dev.appchat.cubby.bz
cub function do --space appchat-dev --unit backend set-env-var CHAT_TITLE "AI Chat Dev"
cub function do --space appchat-prod --unit frontend --unit backend set-hostname www.appchat.cubby.bz
cub function do --space appchat-prod --unit backend set-env-var REGION NA
cub function do --space appchat-prod --unit backend set-env-var ROLE prod

for unit in db redis vote result ; do
echo --- | cat example-voting-app/k8s-specifications/${unit}-deployment.yaml - example-voting-app/k8s-specifications/${unit}-service.yaml | cub unit create --space appvote-dev --label Application=appvote $unit -
cub unit create --space appvote-prod --upstream-space appvote-dev --upstream-unit $unit $unit
done
cub unit create --space appvote-dev --label Application=appvote worker example-voting-app/k8s-specifications/worker-deployment.yaml
cub unit create --space appvote-prod --upstream-space appvote-dev --upstream-unit worker worker
# TODO: customize

for file in apptique/kubernetes-manifests/*.yaml ; do
unit="$(basename -s .yaml $file)"
cub unit create --space apptique-dev --label Application=apptique $unit $file
cub unit create --space apptique-prod --upstream-space apptique-dev --upstream-unit $unit $unit
done
fi
