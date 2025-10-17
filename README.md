# Demo setup

Prerequisites:

- cub
- kubectl
- kind
- flux
- helm (if using setup-helm.sh)

Setup:

```
git clone https://github.com/confighub-kubecon-2025/setup
git clone https://github.com/confighub-kubecon-2025/appchat
git clone https://github.com/confighub-kubecon-2025/appvote
git clone https://github.com/confighub-kubecon-2025/apptique
setup/setup-clusters.sh
sleep 30
setup/setup-cub.sh
```

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

You should then be able to access the instances at:

- Dev
  - http://dev.appchat.cubby.bz:11080/
  - http://dev-vote.appvote.cubby.bz:11080/
  - http://dev-results.appvote.cubby.bz:11080/
  - http://dev.apptique.cubby.bz:11080/
- Prod
  - http://www.appchat.cubby.bz:12080/
  - http://www.appvote.cubby.bz:12080/
  - http://results.appvote.cubby.bz:12080/
  - http://www.apptique.cubby.bz:12080/

Alternative ways to run the applications:

- To import helm charts, use setup-cubhelm.sh instead.
- To run with Flux, use setup-flux.sh instead.
- To run with just Helm, use setup-helm.sh instead.
