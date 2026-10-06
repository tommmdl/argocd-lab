# argocd-lab

Minimal GitOps lab with ArgoCD and Kustomize, built to observe reconciliation behavior
in practice: what happens when a resource is changed directly in the cluster, with and
without self-heal, and what changes when the modification comes from Git.

## Structure

```
base/                  nginx Deployment and Service, with requests, limits and probes,
                       sync waves and PreSync/PostSync hook Jobs
overlays/dev/          namespace lab-dev, prefix dev-, 1 replica
overlays/prod/         namespace lab-prod, prefix prod-, 3 replicas, higher CPU request
apps/app-dev.yaml      ArgoCD Application, self-heal OFF
apps/app-prod.yaml     ArgoCD Application, self-heal ON
appsets/lab.yaml       ApplicationSet generating both Applications from one template
pratica/               supporting manifests: QoS classes, Pending pods, bad liveness probe
COMMANDS.md            full step-by-step walkthrough (English)
COMANDOS.md            same walkthrough in Portuguese
```

Both Applications have automated sync. The only difference between them is self-heal,
which isolates the variable and lets you compare the two behaviors side by side.

## What the lab demonstrates

**1. Drift without self-heal.** Manually changing replicas in `lab-dev` leaves the
Application `OutOfSync`, and ArgoCD does not fix it. It reports the drift, but does not act.

**2. Drift with self-heal.** The same change in `lab-prod` is reverted on its own within
seconds. The reaction is fast because ArgoCD watches the cluster resources, without
depending on the Git polling cycle.

**3. Change through Git.** A commit and push changing the prod overlay is applied and kept.

Same command, opposite result, depending on where the change comes from and on the
self-heal setting.

## ApplicationSet variant

The two files in `apps/` differ only in the environment name and the self-heal flag.
`appsets/lab.yaml` generates the same two Applications from a single template with a list
generator, so adding an environment becomes one more list entry instead of a copied file.
The generated specs were checked against the handwritten ones and are identical. It
replaces `apps/`, so use one or the other (step 8 of the walkthrough).

## Sync waves and hooks

Every sync runs in a fixed order:

```
PreSync   Job migrate      stands in for a database migration
wave 0    Service web
wave 1    Deployment web   applied only after wave 0 is healthy
PostSync  Job smoke-test   wget against the Service
```

If the migration fails, nothing else is applied. If the smoke test fails, the sync is
marked as failed, even though the new Deployment is already running. Both Jobs use
`hook-delete-policy: BeforeHookCreation`, so each run replaces the previous one instead of
piling up. The order can be read from the sync result (step 9 of the walkthrough).


## Reproducible setup and validation

Prerequisites: a running Docker daemon, Bash, curl, tar, Python 3 and make
(Linux, macOS or WSL). Pinned versions live in [scripts/versions.env](scripts/versions.env):
Argo CD **v3.5.3**, kind **v0.33.0**, Kubernetes/kubectl **v1.35.8**, and kubeconform
**v0.7.0**. The kind node image is pinned by digest. Setup always targets `kind-lab`.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r scripts/requirements.txt
make tools
make validate
make setup
export PATH="$PWD/.tools/bin:$PATH"
kubectl config use-context kind-lab
kubectl apply -f apps/
make wait-sync
make status
```

`make tools` installs binaries locally in `.tools/bin`, verifying their published
checksums. `make validate` needs no cluster: it renders dev/prod, validates the
workloads and practice examples against Kubernetes schemas, and validates Applications
and ApplicationSet against CRDs from the pinned Argo CD release. Missing schemas fail
the check. Schema validation does not cover controller behavior or scheduling.

GitHub Actions runs these same checks on pull requests and pushes to main. It also
creates a disposable kind cluster, checks the initial sync and hooks, and verifies
drift with self-heal disabled/enabled using both Applications and ApplicationSet.
The integration job deploys the exact commit under review, rather than main.

Setup uses server-side apply because the ApplicationSet CRD exceeds the client-side
annotation size limit. It reuses an existing lab cluster without upgrading its nodes.
Use a fresh cluster to reproduce the pinned node version.

See [COMMANDS.md](COMMANDS.md) for credentials, UI access, expected results and
experiments ([Portuguese version](COMANDOS.md)). Wait for the initial sync to finish
before changing replicas: a new Application syncs once even with self-heal disabled.

## Things that only showed up in practice

**Kustomize commonLabels.** It was deprecated in favor of `labels` with
`includeSelectors: false`. The reason is that `commonLabels` also injects the label into
the Deployment selector, and the selector is immutable. Adding a new label to something
already running in production makes the apply fail.

**CPU limit.** The Deployment sets a CPU request and a memory limit, but no CPU limit.
The request ensures predictable scheduling, the memory limit protects the node against
leaks, and a CPU limit causes throttling, which tends to hurt latency in
latency-sensitive services.

**Credential helper on WSL.** Without `credsStore` set, the Docker CLI on Linux looks for
a `docker-credential-*` binary in PATH. WSL appends the Windows PATH, and a Rancher
Desktop helper found there hangs every `docker pull`, including the kind node image.

**Booleans in ApplicationSet templates.** Go templates only render inside strings, so
`selfHeal: '{{ .selfHeal }}'` would produce the string `"false"`, which the Application
schema rejects. The per-environment flag goes in `templatePatch`, which is rendered first
and parsed as YAML afterwards, so the value comes out as a real boolean.

**The first automated sync ignores self-heal.** A freshly created Application has never
synced the current revision, so automated sync runs once even with self-heal off. Drifting
`lab-dev` right after creating it gets reverted, which looks exactly like self-heal. Wait
for the first sync to finish before testing drift.

**Self-heal does not run hooks.** A self-heal sync only touches the resources that
drifted, and hooks are skipped in a partial sync. Scaling `prod-web` by hand gets
reverted, but `migrate` and `smoke-test` do not run again. They run on full syncs, such
as a new commit or a manual sync.

**Hooks do not get the namePrefix inside commands.** Kustomize renames the Service to
`dev-web` or `prod-web`, but it only rewrites known reference fields, not a URL inside a
shell command. The smoke test reads its namespace through the downward API and derives
the Service name from it (`lab-dev` -> `dev-web`), which ties the overlay namespace and
prefix together.

## Cleanup

```bash
.tools/bin/kind delete cluster --name lab
```
