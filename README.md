# Demo setup

Prerequisites:

- ConfigHub account ([signup](https://auth.confighub.com/sign-up))
- cub ([install](https://docs.confighub.com/get-started/setup/#install-the-cli))
- kubectl
- kind
- docker (kind's node runtime)
- the cub-helm plugin, `cub plugin install confighub/cub-helm` (if using setup-cubhelm.sh)
- flux (if using setup-flux.sh)
- helm (if using setup-helm.sh)

Setup:

```
git clone https://github.com/confighub-kubecon-2025/setup
git clone https://github.com/confighub-kubecon-2025/appchat
git clone https://github.com/confighub-kubecon-2025/appvote
git clone https://github.com/confighub-kubecon-2025/apptique
setup/setup-clusters.sh
# Wait for nginx to start
sleep 30
setup/setup-cub.sh
```

`setup-clusters.sh` runs `cub cluster up` for each cluster, which creates the
kind cluster, installs Argo CD, and creates the ConfigHub space holding a
server-hosted OCI worker and an OCI target (`dev/target`, `prod/target`).
Nothing runs in the cluster on ConfigHub's behalf: Argo CD pulls each space's
Release from ConfigHub's OCI registry.

`setup-cub.sh` then clones a dev and a prod deployment from each application's
base, bound to those targets, and publishes a Release for each.

## Ports

`cub cluster up` reserves a ten-port window on the kind node from whatever is
free in 30000-30099, so the ports differ per cluster and per run rather than
being the fixed values a hand-written kind config would give. The first port in
the window is Argo CD's; `setup-clusters.sh` puts ingress-nginx on the next two
and prints all of them. To see them again:

```
cub cluster list
```

(The setup-flux.sh and setup-helm.sh paths do not use `cub cluster up`; they
create the kind clusters from dev-cluster.yaml/prod-cluster.yaml and keep the
fixed 11080/12080 ingress ports.)

Add the following hosts to /etc/hosts:

```
127.0.0.1 dev.appchat.cubby.bz
127.0.0.1 www.appchat.cubby.bz
127.0.0.1 dev-vote.appvote.cubby.bz
127.0.0.1 dev-results.appvote.cubby.bz
127.0.0.1 www.appvote.cubby.bz
127.0.0.1 results.appvote.cubby.bz
127.0.0.1 dev.apptique.cubby.bz
127.0.0.1 www.apptique.cubby.bz
```

You should then be able to access the instances at the ingress port of the
corresponding cluster (`DEV_PORT` and `PROD_PORT` below):

- Dev
  - http://dev.appchat.cubby.bz:DEV_PORT/
  - http://dev-vote.appvote.cubby.bz:DEV_PORT/
  - http://dev-results.appvote.cubby.bz:DEV_PORT/
  - http://dev.apptique.cubby.bz:DEV_PORT/
- Prod
  - http://www.appchat.cubby.bz:PROD_PORT/
  - http://www.appvote.cubby.bz:PROD_PORT/
  - http://results.appvote.cubby.bz:PROD_PORT/
  - http://www.apptique.cubby.bz:PROD_PORT/

Argo CD is at `http://localhost:<argo-port>`; open it with the admin password on
your clipboard using `cub cluster open dev`.

## Things to try

Some operations you can try on these applications in ConfigHub:

- Navigate from a unit to the UI: `cub k8s source --kubeconfig ~/.confighub/clusters/prod.kubeconfig Deployment backend -n appchat`
- Change resources: `cub function invoke --space appchat-prod --unit backend set-container-resources backend floor 100m 200Mi 2`
- Change an environment variable: `cub function invoke --space appchat-prod --unit backend set-env-var backend EXPERIMENTAL_FEATURE false`
- Set security context to best-practice values: `cub function invoke --space appchat-prod --unit backend -- set-pod-defaults –security-context=true`
- Make any of those changes live: `cub release publish appchat-prod`
- Undo the last change to a unit: `cub unit update --patch --restore -1 --space appchat-prod backend`, then publish again
- Break glass, and watch Argo CD put it back: `kubectl --kubeconfig ~/.confighub/clusters/prod.kubeconfig edit deploy -n apptique paymentservice`.
  The Applications are created with `selfHeal: true`, so the cluster is reconciled back to
  the published Release rather than the edit being pulled into ConfigHub.

Alternative ways to run the applications:

- To import helm charts, use setup-cubhelm.sh instead.
- To run with Flux, use setup-flux.sh instead.
- To run with just Helm, use setup-helm.sh instead.

## Teardown

```
setup/cleanup.sh
```
