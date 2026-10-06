#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) echo 'Use Linux, macOS or WSL.' >&2; exit 1 ;; esac
case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) echo 'Unsupported architecture.' >&2; exit 1 ;; esac
mkdir -p "$ROOT/.tools/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
check() {
  python3 - "$1" "$2" <<'PY'
import hashlib, pathlib, sys
path, expected = sys.argv[1:]
actual = hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"Checksum mismatch for {path}")
PY
}
curl --connect-timeout 15 --max-time 180 --retry 2 -fsSL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$os/$arch/kubectl" -o "$tmp/kubectl"
curl --connect-timeout 15 --max-time 180 --retry 2 -fsSL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$os/$arch/kubectl.sha256" -o "$tmp/kubectl.sha256"
check "$tmp/kubectl" "$(cat "$tmp/kubectl.sha256")"
kind_url="https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$os-$arch"
curl --connect-timeout 15 --max-time 180 --retry 2 -fsSL "$kind_url" -o "$tmp/kind"
curl --connect-timeout 15 --max-time 180 --retry 2 -fsSL "$kind_url.sha256sum" -o "$tmp/kind.sha256"
check "$tmp/kind" "$(awk '{print $1}' "$tmp/kind.sha256")"
asset="kubeconform-$os-$arch.tar.gz"
release="https://github.com/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION"
curl --connect-timeout 15 --max-time 180 --retry 2 -fsSL "$release/$asset" -o "$tmp/$asset"
curl --connect-timeout 15 --max-time 180 --retry 2 -fsSL "$release/CHECKSUMS" -o "$tmp/CHECKSUMS"
expected=$(awk -v asset="$asset" '$2 == asset {print $1}' "$tmp/CHECKSUMS")
check "$tmp/$asset" "$expected"
tar -xzf "$tmp/$asset" -C "$tmp" kubeconform
for tool in kubectl kind kubeconform; do
  install -m 755 "$tmp/$tool" "$ROOT/.tools/bin/$tool"
done
printf 'Installed pinned tools in %s/.tools/bin\n' "$ROOT"
