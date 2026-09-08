#!/usr/bin/env python3
"""Resolve the last runtime Dockerfile FROM into a catalog parent ref.

Expands ARG defaults used by FROM, skips scratch, and rewrites the registry
host to JF_DOCKER_REGISTRY so CI vets the JPD catalog — not a hardcoded
workflow image name.
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


ARG_RE = re.compile(r"^ARG\s+([A-Za-z_][A-Za-z0-9_]*)(?:=(.*))?$")
FROM_RE = re.compile(r"^FROM\s+", re.IGNORECASE)
VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")


def expand(value: str, args: dict[str, str], dockerfile: Path) -> str:
    prev = None
    while prev != value:
        prev = value

        def repl(match: re.Match[str]) -> str:
            name = match.group(1) or match.group(2)
            if name not in args:
                raise SystemExit(
                    f"FROM references unset ARG ${{{name}}} in {dockerfile}"
                )
            return args[name]

        value = VAR_RE.sub(repl, value)
    return value


def parse_from_refs(dockerfile: Path) -> list[str]:
    args: dict[str, str] = {}
    from_refs: list[str] = []
    for raw in dockerfile.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        arg_m = ARG_RE.match(line)
        if arg_m:
            name, default = arg_m.group(1), arg_m.group(2)
            if default is not None:
                args[name] = expand(default.strip().strip("\"'"), args, dockerfile)
            continue
        from_m = FROM_RE.match(line)
        if not from_m:
            continue
        rest = line[from_m.end() :]
        rest = re.sub(r"--platform(?:=|\s+)\S+\s*", "", rest, flags=re.IGNORECASE).strip()
        rest = re.split(r"\s+[Aa][Ss]\s+", rest, maxsplit=1)[0].strip()
        image = expand(rest, args, dockerfile)
        if image.lower() == "scratch":
            continue
        from_refs.append(image)
    return from_refs


def rewrite_to_registry(image_ref: str, registry: str) -> tuple[str, str, str, str]:
    """Return catalog_parent, package_name, package_version, expanded_from."""
    parsed = image_ref
    digest = ""
    if "@" in parsed:
        parsed, digest = parsed.split("@", 1)

    first, _, remainder = parsed.partition("/")
    if remainder and ("." in first or ":" in first or first == "localhost"):
        catalog_path = remainder
    else:
        catalog_path = parsed

    parent = f"{registry.rstrip('/')}/{catalog_path}"
    if digest:
        parent = f"{parent}@{digest}"

    if digest:
        name = catalog_path.rsplit("/", 1)[-1].rsplit(":", 1)[0]
        version = digest
    else:
        name_part = catalog_path.rsplit("/", 1)[-1]
        if ":" in name_part:
            version = name_part.rsplit(":", 1)[-1]
            name = name_part.rsplit(":", 1)[0]
        else:
            version = "latest"
            name = name_part
    return parent, name, version, parsed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dockerfile", default=os.environ.get("DOCKERFILE", ""))
    parser.add_argument(
        "--registry", default=os.environ.get("JF_DOCKER_REGISTRY", "")
    )
    parser.add_argument(
        "--github-env", default=os.environ.get("GITHUB_ENV", "")
    )
    ns = parser.parse_args()
    if not ns.dockerfile or not ns.registry:
        raise SystemExit("DOCKERFILE and JF_DOCKER_REGISTRY are required")

    dockerfile = Path(ns.dockerfile)
    from_refs = parse_from_refs(dockerfile)
    if not from_refs:
        raise SystemExit(f"No usable FROM in {dockerfile}")

    expanded = from_refs[-1]
    parent, name, version, parsed = rewrite_to_registry(expanded, ns.registry)
    print(f"Dockerfile {dockerfile}: last FROM expands to {expanded}")
    print(
        f"Catalog parent for build + SLSA vet: {parent} "
        f"(package {name} version {version})"
    )
    if ns.github_env:
        with open(ns.github_env, "a", encoding="utf-8") as fh:
            fh.write(f"PARENT_IMAGE={parent}\n")
            fh.write(f"PARENT_NAME={name}\n")
            fh.write(f"PARENT_TAG={version}\n")
            fh.write(f"DOCKERFILE_FROM={parsed}\n")


if __name__ == "__main__":
    main()
