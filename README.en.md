# Argo CD in practice

English · [Português](README.md)

The notes application already ran on Kubernetes. Now Git holds the state Argo CD should maintain: two API replicas, PostgreSQL and the application configuration.

The exercise starts by changing the replica count directly in the cluster. With `selfHeal` disabled, Argo detects the difference and leaves it in place. With it enabled, Argo restores the state stored in Git.

## Run it

Clone this repository beside [kubernetes-lab](https://github.com/tommmdl/kubernetes-lab). In that project, run `bash scripts/prepare.sh` followed by `bash scripts/lab.sh up`. It creates the `devops-notes` cluster, namespace and local database password.

Then run here:

```bash
bash notes/setup.sh
python3 notes/verify.py
bash notes/k.sh -n argocd get application notes
```

The scripts use the neighboring project's private kubeconfig. Set `KUBERNETES_LAB_DIR` for a different location. The application remains at http://localhost:8005.

For the dashboard, keep this running in another terminal:

```bash
bash notes/k.sh -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8006:443
```

Open https://localhost:8006 and sign in as `admin`. The local certificate is self-signed. Read the password only in your own terminal:

```bash
bash notes/k.sh -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## What the test checks

The test waits for the first sync to finish before introducing drift. With self-heal off, it keeps three replicas for 30 seconds. It enables self-heal and waits for two replicas again, then introduces a second drift while correction is enabled. It also checks that the volume and a test note survived. Finally, it removes its note and leaves self-heal enabled.

The executed result is stored in [evidence/notes-self-heal.json](evidence/notes-self-heal.json), together with the Git revision tested. Run it again to verify your own environment.

## How it fits together

`notes/application.yaml` watches `workloads/notes` in this repository. Its AppProject permits this repository, the `notes-lab` namespace and the resource types the app uses. Database configuration and PostgreSQL come first, a Sync Job prepares the table in wave 1, and the API follows in wave 2. The database password stays outside Git and is bootstrapped by Kubernetes lab.

The manifests come from kubernetes-lab commit `af603c1`, preserving image digests, names, selectors and storage. The Job runs `CREATE TABLE IF NOT EXISTS`; it is not a versioned migration system. Adoption keeps the existing database and volume. `prune` is disabled, so deleting a manifest does not automatically delete a resource.

After adoption, change this application's desired state here. Running the Kubernetes lab deployment or scaling exercises again can compete with Argo CD. Kubernetes replaces deleted Pods; Argo CD corrects differences between Git manifests and live resources.

To stop management while keeping the app running:

```bash
bash notes/k.sh -n argocd delete application notes
```

This Application has no cascading deletion finalizer. To remove the whole environment, run `bash scripts/lab.sh down` in Kubernetes lab. That also deletes database contents. Stopping port-forward only closes dashboard access.

## The original exercises are still here

This work started from the lab found on E:. GitHub had newer changes, so this integration builds on that version and preserves its history. Nginx examples remain in `base`, `overlays`, `apps` and `appsets`, with the [original guide](docs/nginx-lab.md), [Portuguese commands](COMANDOS.md) and [English commands](COMMANDS.md).

The existing `scripts/` and CI workflow test Nginx in a separate cluster named `lab`, using Argo CD v3.5.3. The notes integration uses `notes/`, cluster `devops-notes` and Argo CD v3.5.5. Recorded notes tests ran locally; CI validates the notes manifests but does not run this self-heal test.

This is a local learning environment, without notes application authentication or production infrastructure. The standard Argo CD installation has broad cluster permissions; the AppProject restricts this Application, not the whole installation. Setup and verification were carried out with assistant help.

References: [installation](https://argo-cd.readthedocs.io/en/stable/getting_started/) and [automated sync and self-heal](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).

## Follow requests

[tracing-lab](https://github.com/tommmdl/tracing-lab) adds an OpenTelemetry-instrumented image. The option lives in `workloads/notes-traced`, while basic manifests remain in `workloads/notes`. Build and load the image first, then use that project's `scripts/argocd.sh` to select the option. Reapplying `notes/application.yaml` selects the basic application again.

The image pins now include the first API and PostgreSQL remediation round. PostgreSQL stays on version 17 and Bookworm; only its gosu helper and Go dependencies change. The API updates Flask/liblzma and removes installation-only pip tooling from runtime. See the [full before/after reports](https://github.com/tommmdl/security-lab/blob/main/docs/remediation.en.md). Remaining findings still block the separate security gate.

Remediation validation: 23 Compose checks, a controlled restore of three notes from the original PostgreSQL image into the rebuilt image, and 19 local tracing checks. The running Argo CD application is Synced/Healthy and retains the same PVC. Full evidence and remaining issues are linked above.
