"""Extract JSON schemas from the same Argo CD CRDs used by setup."""
import json
import pathlib
import sys
import subprocess

import yaml

version, destination = sys.argv[1:]
output = pathlib.Path(destination)
output.mkdir(parents=True, exist_ok=True)


def strict_objects(value):
    if isinstance(value, dict):
        for child in list(value.values()):
            strict_objects(child)
        if value.get("type") == "object" and "properties" in value:
            if not value.get("x-kubernetes-preserve-unknown-fields"):
                value.setdefault("additionalProperties", False)
    elif isinstance(value, list):
        for child in value:
            strict_objects(child)


for name in ("application", "applicationset"):
    url = (f"https://raw.githubusercontent.com/argoproj/argo-cd/{version}"
           f"/manifests/crds/{name}-crd.yaml")
    content = subprocess.check_output([
        "curl", "--connect-timeout", "15", "--max-time", "180",
        "--retry", "2", "-fsSL", url,
    ])
    crd = yaml.safe_load(content)
    for api in crd["spec"]["versions"]:
        if api["served"]:
            schema = api["schema"]["openAPIV3Schema"]
            strict_objects(schema)
            # Kubernetes supplies standard ObjectMeta validation separately.
            schema["properties"]["metadata"] = {"type": "object"}
            path = output / f"{name}_{api['name']}.json"
            path.write_text(json.dumps(schema) + "\n")
