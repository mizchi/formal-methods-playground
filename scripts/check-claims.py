#!/usr/bin/env python3
"""The oracle for claims/catalog.json.

Chapter 5's continuous-verification pattern states the check this implements:

    previousClaim == currentClaim and checkResult == expectedResult

Until now the repo only held the first half of that by hand, in prose, in each
probe's README, and CI only asserted that the *green* runs exit 0. Seven of the
seventeen TLA+ configs -- most of them the load-bearing breaking variants --
were never run by CI at all, so a weakened invariant would have left the green
checks green and the breaking variants quietly not breaking.

This runs every claim in the catalog and decides whether the repo still says
what the book says it says. A mismatch is reported in the drift vocabulary of
chapter 8 (spec / code / model / harness drift), because which kind it is
decides which file you go and edit.

    ./scripts/check-claims.py                  run the whole catalog
    ./scripts/check-claims.py --tool tlc       run only the claims one tool backs
    ./scripts/check-claims.py --filter SEAT    run claims whose id matches
    ./scripts/check-claims.py --list           print the catalog, run nothing
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "claims" / "catalog.json"

RE_NO_ERROR = re.compile(r"^Model checking completed\. No error has been found\.", re.M)
RE_INVARIANT = re.compile(r"^Error: Invariant (\w+) is violated\.", re.M)
RE_TEMPORAL = re.compile(r"^Error: Temporal properties were violated\.", re.M)
RE_DISTINCT = re.compile(r"^\d+ states generated, (\d+) distinct states found", re.M)
RE_DEPTH = re.compile(r"^The depth of the complete state graph search is (\d+)\.", re.M)

GREEN, RED, DIM, BOLD, OFF = "\033[32m", "\033[31m", "\033[2m", "\033[1m", "\033[0m"
if not sys.stdout.isatty():
    GREEN = RED = DIM = BOLD = OFF = ""


class Mismatch(Exception):
    """A claim's machine result no longer matches the catalog."""

    def __init__(self, drift_class: str, detail: str, hint: str = "") -> None:
        super().__init__(detail)
        self.drift_class = drift_class
        self.detail = detail
        self.hint = hint


def run_tlc(claim: dict) -> str:
    spec = pathlib.Path(claim["spec"])
    config = pathlib.Path(claim["config"])
    proc = subprocess.run(
        ["tlc", "-config", config.name, spec.name],
        cwd=ROOT / spec.parent,
        capture_output=True,
        text=True,
    )
    return proc.stdout + proc.stderr


RUNNERS = {"tlc": run_tlc}


def observe(output: str) -> dict:
    """Project the tool's output onto the alphabet the catalog speaks."""
    result: dict = {}
    invariant = RE_INVARIANT.search(output)
    if invariant:
        result["outcome"] = "invariant-violated"
        result["invariant"] = invariant.group(1)
    elif RE_TEMPORAL.search(output):
        result["outcome"] = "property-violated"
    elif RE_NO_ERROR.search(output):
        result["outcome"] = "no-error"
    else:
        result["outcome"] = "unrecognised"

    distinct = RE_DISTINCT.search(output)
    if distinct:
        result["distinct_states"] = int(distinct.group(1))
    depth = RE_DEPTH.search(output)
    if depth:
        result["depth"] = int(depth.group(1))
    return result


def compare(claim: dict, expect: dict, actual: dict, output: str) -> None:
    role = claim.get("role", "green")

    if actual["outcome"] != expect["outcome"]:
        if actual["outcome"] == "unrecognised":
            raise Mismatch(
                "harness-drift",
                f"could not read an outcome out of the tool's output "
                f"(expected {expect['outcome']})",
                "the tool version or its output format changed; check the "
                "run by hand before touching the model",
            )
        if role == "breaking" and actual["outcome"] == "no-error":
            raise Mismatch(
                "model-drift or spec-drift",
                "the breaking variant stopped breaking: expected "
                f"{expect['outcome']}, got no error",
                "the property this variant is supposed to violate got weaker, "
                "or the model no longer reaches the bad state. The green claim "
                "it guards is now passing for no reason -- do not update the "
                "catalog until you know which.",
            )
        if role == "green":
            raise Mismatch(
                "code-drift or model-drift",
                f"a claim that used to hold no longer does: expected "
                f"{expect['outcome']}, got {actual['outcome']}",
                "decide whether the domain rule changed (update the claim) or "
                "the model broke (fix the model) before editing anything",
            )
        raise Mismatch(
            "model-drift",
            f"expected {expect['outcome']}, got {actual['outcome']}",
        )

    if "invariant" in expect and actual.get("invariant") != expect["invariant"]:
        raise Mismatch(
            "model-drift",
            f"a different invariant broke first: expected "
            f"{expect['invariant']}, got {actual.get('invariant')}",
            "the counterexample no longer demonstrates the claim it was "
            "written for, even though something still fails",
        )

    for fragment in expect.get("witness", []):
        if fragment not in output:
            raise Mismatch(
                "model-drift",
                f"the counterexample no longer shows {fragment!r}",
                "the violation still happens but the witness changed; the "
                "domain sentence in the README may no longer be true",
            )

    for field in ("distinct_states", "depth"):
        if field in expect and actual.get(field) != expect[field]:
            raise Mismatch(
                "harness-drift or model-drift",
                f"{field}: expected {expect[field]}, got {actual.get(field)}",
                f"the outcome is unchanged, so the claim still holds -- but the "
                f"model or the tool moved. Update {field} in the catalog in the "
                f"same commit as whatever moved it.",
            )


def check_documentation(claim: dict) -> list[str]:
    problems = []
    for doc in claim.get("documented_in", []):
        path = ROOT / doc
        if not path.exists():
            problems.append(f"{doc}: no such file")
            continue
        text = path.read_text(encoding="utf-8")
        for fragment in claim.get("doc_claims", []):
            if fragment not in text:
                problems.append(f"{doc}: does not contain {fragment!r}")
    return problems


def check_catalog_shape(claims: list[dict]) -> list[str]:
    """Checks about the catalog itself, not about any one run."""
    problems = []
    by_id = {}
    for claim in claims:
        cid = claim["claim_id"]
        if cid in by_id:
            problems.append(f"duplicate claim_id {cid}")
        by_id[cid] = claim

    for claim in claims:
        cid = claim["claim_id"]
        for field in ("guards", "guarded_by"):
            for ref in claim.get(field, []):
                if ref not in by_id:
                    problems.append(f"{cid}: {field} names unknown claim {ref}")

        # The repo's dual-check discipline, enforced: a green claim is either
        # guarded by a breaking variant, or says in writing why it is not.
        if claim.get("role", "green") == "green":
            if not claim.get("guarded_by") and not claim.get("unguarded_reason"):
                problems.append(
                    f"{cid}: green claim with no breaking variant and no "
                    f"unguarded_reason -- a green check nothing can falsify"
                )

        # guards / guarded_by must agree in both directions.
        for ref in claim.get("guards", []):
            if ref in by_id and cid not in by_id[ref].get("guarded_by", []):
                problems.append(f"{cid} guards {ref}, but {ref} does not list it")
        for ref in claim.get("guarded_by", []):
            if ref in by_id and cid not in by_id[ref].get("guards", []):
                problems.append(f"{cid} is guarded_by {ref}, but {ref} does not list it")

    # Every runnable config in the repo must be spoken for.
    catalogued = {c["config"] for c in claims}
    for cfg in sorted((ROOT / "languages" / "tla").glob("*.cfg")):
        rel = str(cfg.relative_to(ROOT))
        if rel not in catalogued:
            problems.append(f"{rel}: config with no claim in the catalog")

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filter", default="", help="only claims whose id contains this")
    parser.add_argument("--tool", default="", help="only claims checked by this tool")
    parser.add_argument("--list", action="store_true", help="print the catalog and exit")
    args = parser.parse_args()

    claims = json.loads(CATALOG.read_text(encoding="utf-8"))["claims"]

    if args.list:
        for claim in claims:
            role = claim.get("role", "green")
            print(f"{claim['claim_id']:<26} {claim.get('timing', '--'):<3} "
                  f"{role:<8} {claim['config']}")
        return 0

    failures: list[str] = []
    gaps = [c["claim_id"] for c in claims
            if c.get("role", "green") == "green" and not c.get("guarded_by")]

    for problem in check_catalog_shape(claims):
        failures.append(f"catalog: {problem}")
        print(f"{RED}catalog{OFF}: {problem}")

    selected = [
        c for c in claims
        if args.filter in c["claim_id"] and (not args.tool or c["tool"] == args.tool)
    ]
    for claim in selected:
        cid = claim["claim_id"]
        runner = RUNNERS.get(claim["tool"])
        if runner is None:
            failures.append(f"{cid}: no runner for tool {claim['tool']!r}")
            print(f"{RED}FAIL{OFF} {cid}: no runner for tool {claim['tool']!r}")
            continue

        output = runner(claim)
        actual = observe(output)
        try:
            compare(claim, claim["expect"], actual, output)
        except Mismatch as mismatch:
            failures.append(f"{cid}: {mismatch.detail}")
            print(f"{RED}DRIFT{OFF} {cid}  [{BOLD}{mismatch.drift_class}{OFF}]")
            print(f"      claim   : {claim['domain_claim']}")
            print(f"      check   : tlc -config {pathlib.Path(claim['config']).name} "
                  f"{pathlib.Path(claim['spec']).name}")
            print(f"      drift   : {mismatch.detail}")
            if mismatch.hint:
                print(f"      what to do: {mismatch.hint}")
            continue

        doc_problems = check_documentation(claim)
        if doc_problems:
            for problem in doc_problems:
                failures.append(f"{cid}: {problem}")
                print(f"{RED}DRIFT{OFF} {cid}  [{BOLD}doc-drift{OFF}]")
                print(f"      the machine agrees with the catalog, the prose does not")
                print(f"      drift   : {problem}")
            continue

        role = claim.get("role", "green")
        summary = actual["outcome"]
        if summary == "invariant-violated":
            summary = f"{actual['invariant']} violated"
        print(f"{GREEN}ok{OFF}    {cid:<26} {DIM}{role:<8}{OFF} {summary}")

    print()
    if gaps:
        print(f"{DIM}coverage: {len(gaps)} green claim(s) with no breaking variant, "
              f"each with a stated reason: {', '.join(gaps)}{OFF}")
    if failures:
        print(f"{RED}{len(failures)} drift(s) across {len(selected)} claim(s){OFF}")
        return 1
    print(f"{GREEN}{len(selected)} claim(s) hold as catalogued{OFF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
