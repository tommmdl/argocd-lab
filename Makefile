SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help tools setup validate status wait-sync
help:
	@printf '%s\n' 'make tools      Install pinned kubectl, kind and kubeconform locally' 'make setup      Create the kind lab and install pinned Argo CD' 'make validate   Render overlays and validate workloads + Argo CD resources' 'make status     Show Application and workload status' 'make wait-sync  Wait for successful initial sync in dev and prod'
tools:
	bash scripts/install-tools.sh
setup:
	bash scripts/setup.sh
validate:
	bash scripts/validate.sh
status:
	bash scripts/status.sh
wait-sync:
	bash scripts/wait-sync.sh
