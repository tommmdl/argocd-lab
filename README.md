# argocd-lab

Minimal GitOps lab with ArgoCD and Kustomize, built to observe reconciliation behavior
in practice: what happens when a resource is changed directly in the cluster, with and
without self-heal, and what changes when the modification comes from Git.

## Structure

```
base/                  nginx Deployment and Service, with requests, limits and probes
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

## How to run

Prerequisites: Docker, kind, kubectl.

```bash
kind create cluster --name lab
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

`--server-side` is required: the ApplicationSet CRD exceeds the 262144-byte limit of the
`last-applied-configuration` annotation used by client-side apply.

Initial password and UI:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Then apply the Applications and follow [COMMANDS.md](COMMANDS.md) for the drift
experiments ([Portuguese version](COMANDOS.md)).

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

## Cleanup

```bash
kind delete cluster --name lab
```
