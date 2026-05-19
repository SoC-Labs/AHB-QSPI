#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# AHB QSPI Subsystem - stress summary -> JUnit XML
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Convert the stress runner's qspi_stress_summary.json (one entry per
# phase + a _meta block) into a JUnit XML the GitLab pipeline can publish
# via artifacts.reports.junit, so the per-phase pass/fail history is
# visible in the pipeline/MR test tab and "when did this break" is one
# click. Runs on the CI runner (NOT the board) over the file the harness
# scp'd back into imp/fpga/stress/. Stdlib only.
#
# Usage:
#   stress_summary_to_junit.py <summary.json> [failures.jsonl] -o junit.xml
#
# If <summary.json> is absent (e.g. the run hung before writing it), a
# single synthetic failing testcase is emitted so the pipeline still
# shows red rather than an empty/!missing test report.
#-----------------------------------------------------------------------------

import argparse
import json
import os
import sys
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape


def _load_failures(path):
    """Map phase -> list of failure dicts from the append-only jsonl."""
    out = {}
    if not path or not os.path.isfile(path):
        return out
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            out.setdefault(rec.get("test") or rec.get("phase") or "?",
                           []).append(rec)
    return out


def main():
    ap = argparse.ArgumentParser(description="stress summary -> JUnit XML")
    ap.add_argument("summary", help="qspi_stress_summary.json")
    ap.add_argument("failures", nargs="?", default=None,
                    help="qspi_stress_failures.jsonl (optional, for detail)")
    ap.add_argument("-o", "--out", default="-",
                    help="output path ('-' = stdout)")
    ap.add_argument("--suite-name", default="qspi_hw_stress")
    args = ap.parse_args()

    suite = ET.Element("testsuite", name=args.suite_name)

    if not os.path.isfile(args.summary):
        # No summary => the run never completed (hang/crash/SSH drop).
        # Emit one hard failure so the gate is unambiguous.
        tc = ET.SubElement(suite, "testcase",
                            classname=args.suite_name, name="run_completed")
        ET.SubElement(tc, "failure",
                      message="no summary written").text = (
            f"{args.summary} not found — the stress run did not finish "
            f"(board hang, crash, or SSH drop). Treated as a failure.")
        suite.set("tests", "1")
        suite.set("failures", "1")
        _write(suite, args.out)
        return 0

    with open(args.summary) as f:
        summary = json.load(f)

    fails_by_phase = _load_failures(args.failures)

    n_tests = n_fail = 0
    total_time = 0.0
    for phase, info in summary.items():
        if phase == "_meta" or not isinstance(info, dict):
            continue
        n_tests += 1
        elapsed = float(info.get("elapsed_s", 0.0) or 0.0)
        total_time += elapsed
        nf = int(info.get("failures", 0) or 0)
        tc = ET.SubElement(suite, "testcase",
                           classname=args.suite_name, name=phase,
                           time=f"{elapsed:.2f}")
        if nf:
            n_fail += 1
            detail = json.dumps(fails_by_phase.get(phase, info.get("stats", {})),
                                indent=2, default=str)
            ET.SubElement(
                tc, "failure",
                message=f"{nf} failure(s) in phase '{phase}'",
            ).text = escape(detail)

    meta = summary.get("_meta", {})
    suite.set("tests", str(n_tests))
    suite.set("failures", str(n_fail))
    suite.set("time", f"{total_time:.2f}")
    if "total_failures" in meta:
        suite.set("errors", "0")

    _write(suite, args.out)
    return 0


def _write(suite, out):
    suites = ET.Element("testsuites")
    suites.append(suite)
    xml = ET.tostring(suites, encoding="unicode")
    if out == "-":
        sys.stdout.write(xml + "\n")
    else:
        with open(out, "w") as f:
            f.write(xml + "\n")


if __name__ == "__main__":
    sys.exit(main())
