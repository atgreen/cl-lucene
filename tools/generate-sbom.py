#!/usr/bin/env python3
"""Generate a CycloneDX SBOM for cl-lucene.

cl-lucene is a Common Lisp library, but its real runtime dependencies are Java
artifacts: the OpenLDK runtime that executes Lucene's bytecode, and the
org.apache.lucene Maven artifacts it puts on the classpath.  Those coordinates
live in runtime.lisp (*lucene-version* and *lucene-artifacts*); this script
reads them from there so the SBOM cannot drift from what the code actually
loads.

Usage: generate-sbom.py --version <cl-lucene-version> [--output FILE]

Output is CycloneDX 1.5 JSON.  Run with python3 -I so an attacker-planted
module beside an input file cannot be imported.
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
RUNTIME_LISP = REPO / "runtime.lisp"

LUCENE_GROUP = "org.apache.lucene"
LUCENE_LICENSE = "Apache-2.0"
# Lucene has no external runtime dependencies; every module links against
# lucene-core, and the highlighter additionally needs queries and memory
# (see the *lucene-artifacts* docstring in runtime.lisp).
EXTRA_INTERNAL_DEPS = {
    "lucene-highlighter": ["lucene-queries", "lucene-memory"],
}


def read_runtime_lisp():
    """Return (lucene_version, [artifact, ...]) parsed from runtime.lisp."""
    text = RUNTIME_LISP.read_text(encoding="utf-8")

    m = re.search(r'\*lucene-version\*\s+"([^"]+)"', text)
    if not m:
        sys.exit("could not find *lucene-version* in runtime.lisp")
    version = m.group(1)

    m = re.search(r"\*lucene-artifacts\*\s*'\((.*?)\)", text, re.DOTALL)
    if not m:
        sys.exit("could not find *lucene-artifacts* in runtime.lisp")
    artifacts = re.findall(r'"([^"]+)"', m.group(1))
    if not artifacts:
        sys.exit("*lucene-artifacts* list in runtime.lisp is empty")

    return version, artifacts


def lucene_purl(artifact, version):
    return f"pkg:maven/{LUCENE_GROUP}/{artifact}@{version}"


def build_sbom(cl_lucene_version, lucene_version, artifacts):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    root_ref = f"pkg:github/atgreen/cl-lucene@v{cl_lucene_version}"
    openldk_ref = "pkg:github/atgreen/openldk"

    root_component = {
        "type": "library",
        "bom-ref": root_ref,
        "name": "cl-lucene",
        "version": cl_lucene_version,
        "description": "A native Common Lisp API for Apache Lucene, running on OpenLDK.",
        "licenses": [{"license": {"id": "MIT"}}],
        "purl": root_ref,
        "externalReferences": [
            {"type": "vcs", "url": "https://github.com/atgreen/cl-lucene"}
        ],
    }

    openldk_component = {
        "type": "framework",
        "bom-ref": openldk_ref,
        "name": "openldk",
        "description": "A JVM that transpiles Java bytecode to Common Lisp.",
        # GPLv3 with the GNU Classpath linking exception.
        "licenses": [{"expression": "GPL-3.0-or-later WITH Classpath-exception-2.0"}],
        "purl": openldk_ref,
        "externalReferences": [
            {"type": "vcs", "url": "https://github.com/atgreen/openldk"}
        ],
    }

    lucene_components = []
    for artifact in artifacts:
        purl = lucene_purl(artifact, lucene_version)
        lucene_components.append(
            {
                "type": "library",
                "bom-ref": purl,
                "group": LUCENE_GROUP,
                "name": artifact,
                "version": lucene_version,
                "licenses": [{"license": {"id": LUCENE_LICENSE}}],
                "purl": purl,
                "externalReferences": [
                    {"type": "website", "url": "https://lucene.apache.org/"}
                ],
            }
        )

    # Dependency graph: cl-lucene pulls in OpenLDK and every Lucene artifact it
    # puts on the classpath; each Lucene module depends on lucene-core (which
    # depends on nothing), plus the extra internal edges above.
    core_ref = lucene_purl("lucene-core", lucene_version)
    dependencies = [
        {
            "ref": root_ref,
            "dependsOn": [openldk_ref]
            + [lucene_purl(a, lucene_version) for a in artifacts],
        },
        {"ref": openldk_ref, "dependsOn": []},
    ]
    for artifact in artifacts:
        ref = lucene_purl(artifact, lucene_version)
        if artifact == "lucene-core":
            depends_on = []
        else:
            depends_on = [core_ref] + [
                lucene_purl(a, lucene_version)
                for a in EXTRA_INTERNAL_DEPS.get(artifact, [])
            ]
        dependencies.append({"ref": ref, "dependsOn": depends_on})

    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "timestamp": now,
            "tools": [{"name": "cl-lucene generate-sbom.py"}],
            "component": root_component,
        },
        "components": [openldk_component] + lucene_components,
        "dependencies": dependencies,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate a CycloneDX SBOM for cl-lucene.")
    parser.add_argument("--version", required=True, help="the cl-lucene version being released")
    parser.add_argument("--output", help="write to this file instead of stdout")
    args = parser.parse_args()

    lucene_version, artifacts = read_runtime_lisp()
    sbom = build_sbom(args.version, lucene_version, artifacts)
    text = json.dumps(sbom, indent=2) + "\n"

    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
