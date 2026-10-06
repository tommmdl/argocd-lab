#!/usr/bin/env bash
# Run only on a disposable lab: this intentionally scales workloads and
# replaces the handwritten Applications with an ApplicationSet.
source "$(dirname "$0")/common.sh"
cd "$ROOT"
: "${LAB_REPO_URL:?Set LAB_REPO_URL to a public Git repository containing this lab}"
: "${LAB_REVISION:?Set LAB_REVISION to the commit to test}"
export LAB_REPO_URL LAB_REVISION
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp" <<'PY'
import os, pathlib, sys, yaml
out = pathlib.Path(sys.argv[1])
for source in ("apps/app-dev.yaml", "apps/app-prod.yaml", "appsets/lab.yaml"):
    resource = yaml.safe_load(pathlib.Path(source).read_text())
    spec = resource["spec"]
    if resource["kind"] == "ApplicationSet":
        spec = spec["template"]["spec"]
    spec["source"]["repoURL"] = os.environ["LAB_REPO_URL"]
    spec["source"]["targetRevision"] = os.environ["LAB_REVISION"]
    (out / pathlib.Path(source).name).write_text(yaml.safe_dump(resource))
PY
check_drift() {
  lab_kubectl -n lab-dev scale deployment/dev-web --replicas=5
  lab_kubectl -n argocd wait application/lab-dev \
    --for=jsonpath='{.status.sync.status}'=OutOfSync --timeout=120s
  sleep 15
  test "$(lab_kubectl -n lab-dev get deployment dev-web -o jsonpath='{.spec.replicas}')" = 5
  lab_kubectl -n lab-prod scale deployment/prod-web --replicas=9
  lab_kubectl -n lab-prod wait deployment/prod-web \
    --for=jsonpath='{.spec.replicas}'=3 --timeout=120s
  for env in dev prod; do
    lab_kubectl -n "lab-$env" wait --for=condition=Complete --timeout=120s \
      "job/$env-migrate" "job/$env-smoke-test"
  done
  # Restore dev to its Git state before replacing the Applications.
  lab_kubectl -n lab-dev scale deployment/dev-web --replicas=1
  bash scripts/wait-sync.sh
}
lab_kubectl apply -f "$tmp/app-dev.yaml" -f "$tmp/app-prod.yaml"
bash scripts/wait-sync.sh
check_drift
lab_kubectl -n argocd delete application lab-dev lab-prod
lab_kubectl apply -f "$tmp/lab.yaml"
bash scripts/wait-sync.sh
check_drift
printf 'Initial sync, hooks and drift checks passed for Applications and ApplicationSet.\n'
