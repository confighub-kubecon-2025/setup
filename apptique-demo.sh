#!/usr/bin/env bash
#
# ConfigHub over the apptique Helm chart, as a demo you drive with the spacebar.
#
#   ./apptique-demo.sh                 every section, in order
#   ./apptique-demo.sh guard blame     just those sections
#   ./apptique-demo.sh --list          what the sections are
#
# Keys while a command is waiting: space runs it, s skips it, f stops the
# typing effect, ! opens a subshell, q quits. See demo-lib.sh.
#
# Wants: cub (authenticated), docker, kind, kubectl, helm, the kyverno CLI
# (brew install kyverno), and -- for the guard section -- the kyverno worker built
# from examples/custom-workers/kyverno, on PATH as "kyverno-worker" or named by
# $KYVERNO_WORKER. k8s-mf is optional; the blame section compares against it if it
# is on PATH. Nothing here builds anything: a demo is not the place to find out
# that a compile fails.
#
# The slow setup here is the two kind clusters and the upload of the chart's 35
# rendered resources, so DEMO_SETUP=INIT does all three before the narration
# starts rather than in the middle of it, and those sections explain what was
# done instead of doing it. For a live demo, where minutes of kind output is
# dead air. Unset, or anything else, runs everything in its own order.

source "$(dirname "${BASH_SOURCE[0]}")/demo-lib.sh"

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="$DEMO_DIR/apptique/helm-chart"
POLICY="$DEMO_DIR/policies/disallow-latest-tag-vap.yaml"
# The kyverno worker, prebuilt. Build it once with:
# git clone https://github.com/confighub/examples
# cd examples/custom-workers/kyverno && go build -o ~/bin/kyverno-worker .
KYVERNO_WORKER="${KYVERNO_WORKER:-kyverno-worker}"

# The chart and its version, as the thing that produced the configuration rather
# than as "stdin". This is what --source-description records on every Unit, and
# what "cub unit blame" prints when a field traces back to the chart.
CHART_VERSION="$(awk '/^version:/ {print $2; exit}' "$CHART/Chart.yaml" 2>/dev/null)"
CHART_SOURCE="helm template apptique ./apptique/helm-chart (onlineboutique ${CHART_VERSION:-unknown})"

REGISTRY=us-central1-docker.pkg.dev/google-samples/microservices-demo
IMAGE_REPO=$REGISTRY/frontend
# The guard section breaks a different workload from the one blame asks about, so
# the frontend's image still traces back to the change made on the base.
CART_REPO=$REGISTRY/cartservice

SECTIONS="cluster install policy release change approve guard blame prod undo cleanup"

usage() {
    cat <<EOF
usage: apptique-demo.sh [section ...]

sections, in demo order:
  cluster   bring up the dev and prod kind clusters, wired to ConfigHub
  install   seed the base from the apptique Helm chart's rendered output
  policy    the platform space: approval, and a ValidatingAdmissionPolicy run before release
  release   the dev deployment: clone, approve, release, running pods
  change    change the base, promote to dev -- the daily loop
  approve   review and approval: a change blocked until someone approves it
  guard     shift left: the cluster's own admission policy, enforced before release
  blame     who set this field, when and why -- chart, base, or this variant
  prod      a production deployment stamped from the same base
  undo      an urgent prod change, undone by restoring a released revision
  cleanup   tear down the clusters, the worker, and the spaces

with no arguments, runs everything except cleanup.
EOF
}

# ---------------------------------------------------------------- sections

section_cluster() {
    heading "Set up the clusters"

    if cluster_is_up dev; then
        desc "ConfigHub manages configuration for live infrastructure, so we start with"
        desc "some. The dev cluster is already up: cub cluster up --name dev built a local"
        desc "kind cluster, installed Argo CD into it, and created the ConfigHub spaces"
        desc "and target that address it."
    else
        desc "One command builds a local kind cluster, installs Argo CD into it, and"
        desc "creates the ConfigHub spaces and target that address it."
        run "cub cluster up --name dev"
    fi

    desc "Argo CD is running. Nothing has been deployed to it yet."
    run "source ~/.confighub/clusters/dev.env"
    run "kubectl get pods -n argocd"

    desc "ConfigHub never pushes into the cluster. The cluster pulls from it."
}

section_install() {
    heading "Install the component from its Helm chart"

    desc "apptique is an existing Helm chart. ConfigHub does not template at runtime:"
    desc "we render the chart once and store the result as data, one Unit per resource."
    desc "From here on the data is what is edited, queried, validated, and promoted."

    if base_is_populated; then
        desc "This was already done -- 35 resources take a couple of minutes to land:"
        desc "  helm template apptique $CHART | cub variant upload ..."
    else
        run "helm template apptique $CHART --namespace confighubplaceholder | \\
    cub variant upload --component apptique --variant base \\
      --granularity per-resource --namespace confighubplaceholder \\
      --source-description \"$CHART_SOURCE\" -"
    fi

    desc "One Unit per resource. Ordinary Kubernetes YAML with literal values, and a"
    desc "namespace placeholder: the base does not know where it will run yet."
    run "cub unit data --space apptique-base deployment-frontend | head -20"

    desc "Note the comment helm left: \"Source: stdin\". That is all the input stream"
    desc "could tell us. What produced the configuration is a different question, and"
    desc "--source-description is how we answered it -- so every Unit records the chart"
    desc "and its version rather than the pipe it arrived down."
    run "cub unit list --space apptique-base | head -8"

    desc "That recorded source is what lets the blame section say a field came from the"
    desc "chart rather than from us."
}

section_policy() {
    heading "Policy, before anything is deployed"

    desc "Rules live in a platform space of their own, so every deployment inherits"
    desc "them rather than each team re-stating them."
    run "cub space create apptique-platform --label Layer=Platform"

    desc "The first rule: changes need a reviewer. vet-approvedby gates any revision"
    desc "with fewer than one approval, and a gated revision cannot be released."
    run "cub trigger create --space apptique-platform require-approval Mutation Kubernetes/YAML vet-approvedby 1"
    run "cub trigger list --space apptique-platform"

    desc "The base opts in by pointing its trigger selector at the platform space."
    run "cub space update apptique-base --where-trigger \"SpaceID = '\$(space_id apptique-platform)'\""

    desc "That is the only place it has to be said. A variant created from this base"
    desc "inherits the selector and the rules it resolves to, so every deployment answers"
    desc "to the platform's rules without opting in one at a time."
}

section_release() {
    heading "Go live"
    use_cluster dev

    desc "A deployment is a clone of the base, adapted to a concrete place to run:"
    desc "every Unit cloned and linked back to the base, the dev target attached, and"
    desc "the namespace placeholder filled in."
    run "cub variant create dev apptique-base --target dev/target --namespace apptique"

    desc "It inherited the base's trigger selector, so it is already reviewed -- nothing"
    desc "to opt in."
    run "cub space get apptique-dev -o jq='.Space.WhereTrigger'"

    desc "Nothing is running yet. Publishing is deliberate, and now also reviewed -- so"
    desc "approve the deployment first."
    run "cub variant approve apptique-dev"

    desc "Now publish. ConfigHub writes the release to its OCI endpoint; Argo pulls it."
    run "cub release publish apptique-dev"

    desc "Argo notices the release on its next sync and applies it. Waiting for the"
    desc "resources to appear first: until Argo syncs, there is nothing to wait on."
    run "kubectl -n apptique wait --for=create deployment/frontend --timeout=300s"
    run "kubectl -n apptique rollout status deployment/frontend --timeout=300s"
    run "kubectl get pods -n apptique"

    desc "Nothing was pushed at the cluster: ConfigHub published, the cluster pulled."
}

section_change() {
    heading "Make a change"

    desc "Configuration is data, so you change fields with functions rather than by"
    desc "editing YAML. Change the base, not the deployment."
    run "cub function set --space apptique-base --unit deployment-frontend set-container-image server $IMAGE_REPO:v0.10.4 --change-desc \"Pin frontend to v0.10.4 for the security patch\""

    desc "ConfigHub knows dev is now behind its base."
    run "cub unit list --space apptique-dev --where \"UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum\""

    desc "Promotion is per-deployment and deliberate. Preview it field by field first."
    run "cub variant promote apptique-dev --dry-run -o mutations"
    run "cub variant promote apptique-dev"
}

section_approve() {
    heading "Review and approval"
    use_cluster dev

    desc "The change landed in dev, but it is not releasable: the platform's approval"
    desc "rule attached a gate to the revision it created."
    run "cub unit list --space apptique-dev --where \"LEN(ApplyGates) > 0\""

    desc "A gate is not advisory. Releasing is refused while one is on."
    run "cub release publish apptique-dev"

    desc "So a reviewer looks at what actually changed -- the fields, not a diff of"
    desc "rendered YAML."
    run "cub unit diff --space apptique-dev deployment-frontend --from=-1 -o mutations"

    desc "and approves the variant. Approval is per revision: this one, and no later"
    desc "one, so the next change is gated again without anyone re-arming anything."
    desc "Approving waits for the triggers to finish re-evaluating, so the release that"
    desc "follows is not racing them."
    run "cub variant approve apptique-dev"
    run "cub release publish apptique-dev"
    run "kubectl get pods -n apptique"
}

section_guard() {
    heading "Shift the admission policy left"

    desc "Approval catches what a reviewer notices. The next rule catches what they do"
    desc "not -- and it is a rule the cluster already has. This is a real Kubernetes"
    desc "ValidatingAdmissionPolicy, the same file you would install in the cluster."
    run "cat $POLICY"

    desc "Kubernetes evaluates that at admission: after a bad config has been committed,"
    desc "merged, and shipped. We are going to evaluate it against the data instead, at"
    desc "the moment of the change."

    desc "The CEL is evaluated by the kyverno CLI, hosted by a small custom worker that"
    desc "registers vet-kyverno alongside the built-in functions. It lives in the platform"
    desc "space with the rules it serves, so one worker answers for every deployment."
    start_policy_worker

    desc "The policy matches Deployments, so scope the Trigger to Deployments. Without"
    desc "this it runs against every Unit in the space -- Services and ServiceAccounts"
    desc "included -- which is both wasteful and a source of gates on Units the policy"
    desc "has nothing to say about."
    run "cub filter create --space apptique-platform deployments Unit --resource-type 'apps/v1/Deployment'"
    run "cub trigger create --space apptique-platform no-latest-tag Mutation Kubernetes/YAML vet-kyverno \"\$(cat $POLICY)\" --worker apptique-platform/platform-policy --unit-filter apptique-platform/deployments"

    desc "A space lists the Triggers matching its selector when that selector is set, not"
    desc "on every change, so dev is still holding the list from before this rule existed"
    desc "and has to look again. Prod needs nothing: it does not exist yet, and a variant"
    desc "resolves its selector as it is created, so it will pick this rule up for free."
    run "cub space update apptique-dev --refresh-triggers"
    run "cub trigger list --space apptique-platform"

    desc "So: the change nobody should be able to ship. Somebody wants the newest build"
    desc "and reaches for the floating tag."
    run "cub function set --space apptique-dev --unit deployment-cartservice set-container-image server $CART_REPO:latest --change-desc \"Track latest so we always get the newest build\""

    desc "The change is stored -- ConfigHub records what you did -- but the policy ran"
    desc "against the data as it was written, and gated the revision it created."
    run "cub unit get --space apptique-dev deployment-cartservice"

    desc "So it cannot be released. That is the point: the cluster's own rule, enforced"
    desc "before anything reaches the cluster, against the change that broke it."
    run "cub release publish apptique-dev"

    desc "Nothing was deployed, so nothing has to be rolled back. Fix the tag."
    run "cub function set --space apptique-dev --unit deployment-cartservice set-container-image server $CART_REPO:v0.10.3 --change-desc \"Pin the tag: policy forbids :latest\""

    desc "The policy gate is gone. Approval is still required, which is the two rules"
    desc "doing their separate jobs."
    run "cub unit get --space apptique-dev deployment-cartservice"
    run "cub variant approve apptique-dev"
    run "cub release publish apptique-dev"
}

section_blame() {
    heading "Who set this field, when, and why"
    use_cluster dev

    desc "By now this one Deployment has fields from three different places: the Helm"
    desc "chart, our change to the base, and the deployment's own customization."
    desc "cub unit blame flattens the resource to fields and says where each came from."
    run "cub unit blame --space apptique-dev deployment-frontend | head -30"

    desc "Three different answers in one table. The image traces to our change on the"
    desc "base; the probes and security context to the chart; the namespace to this"
    desc "deployment. Ask about one field:"
    run "cub unit blame --space apptique-dev deployment-frontend --path 'containers.?name=server.image' --verbose"

    desc "It followed the value out of the deployment, into the base, and stopped at the"
    desc "change that set it. Ask about a field nobody has touched and it goes one hop"
    desc "further, to the chart itself."
    run "cub unit blame --space apptique-dev deployment-frontend --path 'securityContext.runAsUser' --verbose"

    desc "That is the audit trail the cluster cannot give you. What the cluster does"
    desc "know is which controller last wrote each field -- server-side apply's own"
    desc "record, which answers a different question about the same resource."
    if command -v k8s-mf >/dev/null 2>&1; then
        run "k8s-mf categories deployment frontend -n apptique | head -20"
    else
        desc "(k8s-mf is not on PATH; it lives in confighub3/bin after 'make build-k8s-mf'.)"
        run "kubectl get deployment frontend -n apptique --show-managed-fields -o yaml | head -30"
    fi

    desc "The cluster says argocd applied it. ConfigHub says which human changed which"
    desc "field, in which revision, and why."
}

section_prod() {
    heading "Add a production deployment"

    desc "The point of the base/deployment split is that the second one is cheap."
    if cluster_is_up prod; then
        desc "The prod cluster is already up, from the same one command."
    else
        run "cub cluster up --name prod"
    fi

    desc "Same clone as dev, with a production label and a delete gate on the Units."
    run "cub variant create prod apptique-base --target prod/target --namespace apptique --environment Prod --unit-delete-gate critical"

    desc "It inherits both rules from the base -- approval and the admission policy --"
    desc "with no worker, Trigger, or opt-in of its own. The rules were written once."
    run "cub space get apptique-prod -o jq='.Space.WhereTrigger'"

    run "cub variant approve apptique-prod"
    run "cub release publish apptique-prod"
    run "source ~/.confighub/clusters/prod.env"
    run "kubectl -n apptique wait --for=create deployment/frontend --timeout=300s"
    run "kubectl -n apptique rollout status deployment/frontend --timeout=300s"
    run "kubectl get pods -n apptique"

    desc "One component, three variants: a base and two deployments."
    run "cub space list --where \"Labels.Component = 'apptique'\""
}

section_undo() {
    heading "Make and undo a change"

    desc "An urgent operational change -- scale up for a traffic spike. With config in"
    desc "git this is where people break glass: suspend reconciliation, edit the cluster,"
    desc "reconcile the drift away later, and leave no record. Here it is an ordinary"
    desc "change to one environment, and only that one."
    run "cub function set --space apptique-prod --unit deployment-frontend --protect set-replicas 5 -o mutations --change-desc \"Temporary capacity boost for the traffic spike\""
    run "cub variant approve apptique-prod"
    run "cub release publish apptique-prod"
    run "source ~/.confighub/clusters/prod.env"
    run "kubectl get pods -n apptique"

    desc "The boost was meant to be temporary. set-replicas would put it back, but for a"
    desc "larger change you want to undo rather than retype. Every change writes a"
    desc "revision, and publishing tags the revisions it shipped."
    run "cub revision list --space apptique-prod deployment-frontend"

    desc "So the release before the boost names the state to restore."
    run "cub unit update --patch --space apptique-prod deployment-frontend --restore Tag:release-1 -o mutations --change-desc \"Revert the capacity boost\""
    run "cub variant approve apptique-prod"
    run "cub release publish apptique-prod"

    desc "Restore goes forward, not back: a new revision carrying the old data and its"
    desc "protection settings. Undoing a change costs what making one costs."
    run "cub revision list --space apptique-prod deployment-frontend"
}

section_cleanup() {
    heading "Cleanup"

    stop_policy_worker

    desc "cub cluster down removes the kind cluster; --delete-config also deletes the"
    desc "cluster's spaces and every deployment bound to its target."
    run "cub cluster down --name dev --delete-config"

    desc "Prod's Units carry a delete gate, so a recursive delete refuses them. That is"
    desc "the gate doing its job. Force past it deliberately."
    run "cub space delete apptique-prod --recursive-force"
    run "cub cluster down --name prod --delete-config"

    desc "And the spaces not tied to any cluster."
    run "cub space delete apptique-base --recursive"
    run "cub space delete apptique-platform --recursive"
}

# ---------------------------------------------------------------- helpers

# cluster_is_up reports whether the demo's kind cluster of this name exists, so a
# section can describe a cluster it did not have to build. "cub cluster up" is not
# idempotent -- it fails on a cluster that is already there -- and re-running one
# section against a standing environment is the normal way to rehearse.
cluster_is_up() {
    kind get clusters 2>/dev/null | grep -qx "$1"
}

# base_is_populated reports whether the component's base already holds the chart's
# resources, so the install section can describe an upload it did not have to run.
# Keyed on what is there rather than on DEMO_SETUP: the narration should say what is
# true, and a section run on its own has no idea what a previous run did.
base_is_populated() {
    cub unit list --space apptique-base --select Slug -o json 2>/dev/null | grep -q '"Slug"'
}

# use_cluster points kubectl and k8s-mf at one of the demo's clusters. Sections
# that read a cluster call it rather than relying on an earlier section having
# sourced the environment, so a section runs on its own -- and, more importantly,
# so a current-context left in the default kubeconfig cannot quietly send the read
# at some entirely different cluster.
use_cluster() {
    _cluster_env="$HOME/.confighub/clusters/$1.env"
    if [ ! -f "$_cluster_env" ]; then
        printf '%scluster "%s" is not up -- run the cluster section first%s\n' \
            "$_c_warn" "$1" "$_c_off" >&2
        return 1
    fi
    silent "source \"$_cluster_env\""
}

# space_id prints a Space's UUID. The demo needs it inline because WhereTrigger
# selects Triggers by SpaceID rather than by slug.
space_id() {
    cub space get "$1" -o jq='.Space.SpaceID' 2>/dev/null | tr -d '"'
}

# start_policy_worker runs the kyverno worker in the background and remembers its
# pid, so a demo that reaches cleanup stops it and one that does not can be
# stopped by hand. It lives in the platform Space alongside the Triggers whose
# function it hosts; a Trigger reaches Units in any Space that selects it, so one
# worker serves every deployment.
#
# Two things it has to get right, both of which fail as a confusing error later
# rather than here:
#
#   - "cub worker run --executable" takes a path and does not search PATH, so a
#     worker named by bare name is resolved before it is passed on;
#   - creating a Trigger that names a worker requires the worker's *functions* to
#     be registered, which happens after it connects. Waiting for the worker to
#     report Ready is therefore not enough: it is Ready while it still has no
#     functions, and the Trigger create then fails with "No functions found for
#     worker". So this waits for the function the Trigger actually names.
start_policy_worker() {
    _worker_path="$KYVERNO_WORKER"
    case "$_worker_path" in
        */*) ;;
        *) _worker_path="$(command -v "$KYVERNO_WORKER" 2>/dev/null)" ;;
    esac

    _demo_prompt
    printf '%s%s%s\n' "$_c_cmd" \
        "cub worker run --space apptique-platform --executable ${_worker_path:-$KYVERNO_WORKER} platform-policy &" "$_c_off"
    [ -n "$DEMO_DRYRUN" ] && return 0

    if [ -z "$_worker_path" ] || [ ! -x "$_worker_path" ]; then
        printf '%scannot run the kyverno worker: %s is not an executable path%s\n' \
            "$_c_warn" "$KYVERNO_WORKER" "$_c_off" >&2
        return 1
    fi

    cub worker run --space apptique-platform --executable "$_worker_path" platform-policy \
        > "$DEMO_DIR/.kyverno-worker.log" 2>&1 &
    POLICY_WORKER_PID=$!
    echo "$POLICY_WORKER_PID" > "$DEMO_DIR/.kyverno-worker.pid"

    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if cub worker list-function --space apptique-platform platform-policy 2>/dev/null \
             | grep -q vet-kyverno; then
            cub worker list --space apptique-platform
            return 0
        fi
        sleep 2
    done

    printf '%sthe worker did not register vet-kyverno; see %s%s\n' \
        "$_c_warn" "$DEMO_DIR/.kyverno-worker.log" "$_c_off" >&2
    return 1
}

stop_policy_worker() {
    [ -n "$DEMO_DRYRUN" ] && return 0
    if [ -f "$DEMO_DIR/.kyverno-worker.pid" ]; then
        kill "$(cat "$DEMO_DIR/.kyverno-worker.pid")" 2>/dev/null
        rm -f "$DEMO_DIR/.kyverno-worker.pid"
    fi
}

# setup_init does the slow work -- two kind clusters and the chart upload -- before
# the narration starts. Each takes minutes, which the demo's own order would spend
# in front of the audience.
setup_init() {
    heading "Setting up"

    desc "DEMO_SETUP=INIT: building both kind clusters and uploading the chart now,"
    desc "before the demo, so it does not stop for them later. This takes a few minutes."
    cluster_is_up dev  || run_now "cub cluster up --name dev"
    cluster_is_up prod || run_now "cub cluster up --name prod"
    run_now "helm template apptique $CHART --namespace confighubplaceholder | \\
    cub variant upload --component apptique --variant base \\
      --granularity per-resource --namespace confighubplaceholder \\
      --source-description \"$CHART_SOURCE\" -"
}

# check_prereqs fails before the narration starts rather than in front of an
# audience. The kyverno worker is only wanted by the guard section, so a demo that
# does not run it is not held up by a missing one.
check_prereqs() {
    missing=""
    for tool in cub docker kind kubectl helm; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    case " $1 " in
        *" guard "*)
            command -v kyverno >/dev/null 2>&1 || missing="$missing kyverno"
            if ! command -v "$KYVERNO_WORKER" >/dev/null 2>&1 && [ ! -x "$KYVERNO_WORKER" ]; then
                missing="$missing $KYVERNO_WORKER"
            fi
            ;;
    esac
    [ -z "$missing" ] && return 0

    printf '%smissing prerequisites:%s%s\n' "$_c_warn" "$missing" "$_c_off" >&2
    case "$missing" in
        *kyverno-worker*|*"$KYVERNO_WORKER"*)
            printf 'build the worker once, and put it on PATH:\n' >&2
            printf '  cd examples/custom-workers/kyverno && go build -o ~/bin/kyverno-worker .\n' >&2
            printf 'or point $KYVERNO_WORKER at it.\n' >&2
            ;;
    esac
    exit 1
}

main() {
    case "${1-}" in
        -h|--help|-l|--list) usage; exit 0 ;;
    esac

    # Naming sections means working against an environment that already exists, so
    # the up-front setup is not wanted -- it is there to hoist the slow parts of a
    # whole run out of the narration.
    selected="$*"
    requested="$selected"
    if [ -z "$requested" ]; then
        requested="cluster install policy release change approve guard blame prod undo"
    fi

    for name in $requested; do
        case " $SECTIONS " in
            *" $name "*) ;;
            *) echo "unknown section: $name" >&2; usage >&2; exit 1 ;;
        esac
    done

    check_prereqs "$requested"

    if [ "$DEMO_SETUP" = "INIT" ] && [ -z "$selected" ]; then
        setup_init
    fi

    for name in $requested; do
        "section_$name"
    done

    demo_end
    printf '\n%sDone. Sections: %s%s\n' "$_c_dim" "$SECTIONS" "$_c_off"
}

main "$@"
