#!/usr/bin/env python3
"""Replace one architecture inside a published OCI image index.

`docker buildx imagetools create` only ever appends, so re-running a backfill on
a tag that already carries the architecture leaves two entries for it -- and the
stale one sorts first, which is the one clients resolve. This rewrites the index
instead: it drops the old entries for the architecture (the image manifest and
its attestation) and splices in the entries from a freshly pushed index, leaving
every other architecture, and their attestations, byte-identical.
"""
import argparse
import base64
import json
import sys
import urllib.request

INDEX_TYPES = (
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
)
ATTESTATION_SUBJECT = "vnd.docker.reference.digest"


def request(url, token=None, method="GET", body=None, content_type=None, accept=None):
    req = urllib.request.Request(url, method=method, data=body)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if accept:
        req.add_header("Accept", accept)
    if content_type:
        req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req) as resp:
        return resp.read(), dict(resp.headers)


def get_token(registry, repository, username, password):
    basic = base64.b64encode(f"{username}:{password}".encode()).decode()
    url = f"https://{registry}/token?service={registry}&scope=repository:{repository}:pull,push"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Basic {basic}")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["token"]


def fetch_index(registry, repository, reference, token):
    url = f"https://{registry}/v2/{repository}/manifests/{reference}"
    raw, _ = request(url, token, accept=", ".join(INDEX_TYPES))
    return json.loads(raw)


def entries_for(index, arch):
    """The image manifest for `arch` plus any attestation manifest describing it."""
    images = [m for m in index["manifests"] if m.get("platform", {}).get("architecture") == arch]
    subjects = {m["digest"] for m in images}
    attestations = [
        m for m in index["manifests"]
        if m.get("annotations", {}).get(ATTESTATION_SUBJECT) in subjects
    ]
    return images + attestations


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", default="ghcr.io")
    ap.add_argument("--repository", required=True, help="e.g. dnse-tech/spilo-17")
    ap.add_argument("--tag", required=True, help="tag whose index is rewritten in place")
    ap.add_argument("--source", required=True, help="digest of the freshly pushed index")
    ap.add_argument("--arch", default="s390x")
    ap.add_argument("--username", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = get_token(args.registry, args.repository, args.username, args.password)
    target = fetch_index(args.registry, args.repository, args.tag, token)
    source = fetch_index(args.registry, args.repository, args.source, token)

    incoming = entries_for(source, args.arch)
    if not incoming:
        sys.exit(f"no {args.arch} manifest inside {args.source}")

    dropped = entries_for(target, args.arch)
    dropped_digests = {m["digest"] for m in dropped}
    kept = [m for m in target["manifests"] if m["digest"] not in dropped_digests]

    target["manifests"] = kept + incoming

    def describe(m):
        arch = m.get("platform", {}).get("architecture")
        subject = m.get("annotations", {}).get(ATTESTATION_SUBJECT)
        return f"{arch or 'attestation'} {m['digest'][:19]}" + (f" of {subject[:19]}" if subject else "")

    print("removed:  " + ", ".join(describe(m) for m in dropped) if dropped else "removed:  (none)")
    print("added:    " + ", ".join(describe(m) for m in incoming))
    print("result:   " + ", ".join(describe(m) for m in target["manifests"]))

    if args.dry_run:
        print("dry run, not pushed")
        return

    body = json.dumps(target, separators=(",", ":")).encode()
    url = f"https://{args.registry}/v2/{args.repository}/manifests/{args.tag}"
    _, headers = request(url, token, method="PUT", body=body,
                         content_type=target.get("mediaType", INDEX_TYPES[0]))
    print("pushed:   " + headers.get("Docker-Content-Digest", "?"))


if __name__ == "__main__":
    main()
