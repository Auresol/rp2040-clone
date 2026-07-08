#!/usr/bin/env python3
"""
OpenLane parallel grid explorer for rvsoc_top.
Run from inside the OpenLane Docker container:
    python3 /openlane/designs/rvsoc/explore.py

Runs 2 parameter combinations in parallel (fits in 8 GB RAM).
Stops when the first run succeeds, or reports which configs got furthest.
"""

import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ── Knobs ─────────────────────────────────────────────────────────────────────

DESIGN       = "rvsoc"
PARALLEL     = 2        # max simultaneous runs (RAM constraint: ~3-4 GB each)
OPENLANE_DIR = Path("/openlane")
DESIGN_DIR   = OPENLANE_DIR / "designs" / DESIGN

# ── Base config (fixed across all runs) ───────────────────────────────────────

BASE = {
    "DESIGN_NAME":            "rvsoc_top",
    "VERILOG_FILES":          ["dir::src/*.v", "dir::src/*.sv"],
    "VERILOG_FILES_BLACKBOX": "dir::bb/sram_bank.sv",
    "VERILOG_INCLUDE_DIRS":   "dir::src",
    "CLOCK_PORT":             "clk",
    "CLOCK_NET":              "clk",
    "PDK":                    "sky130A",
    "STD_CELL_LIBRARY":       "sky130_fd_sc_hd",
    "ROUTING_CORES":          8,   # OpenROAD multi-thread
}

# ── Parameter grid ────────────────────────────────────────────────────────────
# Each dict overrides BASE. Ordered from most likely to succeed to least.

GRID = [
    # Conservative: low density, explicit die, relaxed clock
    {"CLOCK_PERIOD": 25.0, "FP_SIZING": "absolute", "DIE_AREA": "0 0 700 700", "PL_TARGET_DENSITY": 0.30},
    {"CLOCK_PERIOD": 25.0, "FP_SIZING": "absolute", "DIE_AREA": "0 0 600 600", "PL_TARGET_DENSITY": 0.35},

    # Moderate
    {"CLOCK_PERIOD": 20.0, "FP_SIZING": "absolute", "DIE_AREA": "0 0 700 700", "PL_TARGET_DENSITY": 0.35},
    {"CLOCK_PERIOD": 20.0, "FP_SIZING": "absolute", "DIE_AREA": "0 0 600 600", "PL_TARGET_DENSITY": 0.40},

    # Auto die sizing (let OpenLane decide based on util %)
    {"CLOCK_PERIOD": 25.0, "FP_CORE_UTIL": 20, "PL_TARGET_DENSITY": 0.30},
    {"CLOCK_PERIOD": 25.0, "FP_CORE_UTIL": 25, "PL_TARGET_DENSITY": 0.35},

    # Tighter — push for smaller die
    {"CLOCK_PERIOD": 20.0, "FP_CORE_UTIL": 30, "PL_TARGET_DENSITY": 0.40},
    {"CLOCK_PERIOD": 20.0, "FP_SIZING": "absolute", "DIE_AREA": "0 0 800 800", "PL_TARGET_DENSITY": 0.25},
]

# ── Step labels (for progress reporting) ──────────────────────────────────────

STEPS = {
    0:  "lint",
    1:  "synthesis",
    2:  "sta-pre",
    3:  "floorplan",
    4:  "io-place",
    5:  "global-place",
    6:  "detail-place",
    7:  "cts",
    8:  "routing",
    9:  "signoff",
    10: "gds",
}

def last_step(log: str) -> int:
    """Return the highest [STEP N] seen in the log."""
    steps = re.findall(r"\[STEP (\d+)\]", log)
    return max((int(s) for s in steps), default=0)

def detect_failure(log: str) -> str:
    tail = "\n".join(log.splitlines()[-80:])
    patterns = [
        (r"PPL-0024|IO pins.*exceeds",      "io_pins_overflow"),
        (r"\[ERROR\].*floorplan",            "floorplan"),
        (r"DPL-\d+|\[ERROR\].*placement",   "placement"),
        (r"\[ERROR\].*route|routing.*error", "routing"),
        (r"\[ERROR\].*synthesis",            "synthesis"),
        (r"\[ERROR\].*sta",                  "sta"),
    ]
    for pat, name in patterns:
        if re.search(pat, tail, re.IGNORECASE):
            return name
    return "unknown"

# ── Runner ────────────────────────────────────────────────────────────────────

def run_one(idx: int, overrides: dict) -> dict:
    """Build config, run flow, return result dict."""
    tag  = f"grid_{idx:02d}"
    cfg  = {**BASE, **overrides}
    cfg_path = DESIGN_DIR / f"config_{tag}.json"
    cfg_path.write_text(json.dumps(cfg, indent=4))

    die_str = cfg.get("DIE_AREA") or f"util={cfg.get('FP_CORE_UTIL', 'auto')}%"
    label = (f"PERIOD={cfg.get('CLOCK_PERIOD')}  "
             f"DIE={die_str}  "
             f"DENSITY={cfg.get('PL_TARGET_DENSITY')}")
    print(f"  [{tag}] START  {label}")

    cmd = [
        "flow.tcl",
        "-design",      DESIGN,
        "-tag",         tag,
        "-config_file", str(cfg_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=OPENLANE_DIR)

    log  = proc.stdout.decode("utf-8", errors="replace") + proc.stderr.decode("utf-8", errors="replace")

    success = "[SUCCESS]: Flow complete" in log
    step    = last_step(log)
    failure = "—" if success else detect_failure(log)

    status = "SUCCESS" if success else f"FAILED at step {step} ({STEPS.get(step,'?')}) [{failure}]"
    print(f"  [{tag}] {status}  {label}")

    return {
        "tag":     tag,
        "success": success,
        "step":    step,
        "failure": failure,
        "label":   label,
        "cfg":     cfg,
    }

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 70)
    print(f"OpenLane Parallel Grid Explorer — {DESIGN}")
    print(f"  {len(GRID)} configs, {PARALLEL} at a time")
    print("=" * 70)

    results   = []
    stop_flag = [False]   # set when a success is found

    # Submit in batches of PARALLEL
    with ThreadPoolExecutor(max_workers=PARALLEL) as pool:
        # Submit all upfront; executor naturally limits to PARALLEL at a time
        futures = {
            pool.submit(run_one, i, overrides): i
            for i, overrides in enumerate(GRID)
        }

        for fut in as_completed(futures):
            result = fut.result()
            results.append(result)

            if result["success"]:
                print(f"\n  ✓ First success: {result['tag']} — cancelling remaining")
                # Cancel pending (already-running ones finish naturally)
                for f in futures:
                    f.cancel()

    # ── Summary ───────────────────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("RESULTS SUMMARY")
    print("=" * 70)

    successes = [r for r in results if r["success"]]
    failures  = sorted([r for r in results if not r["success"]],
                       key=lambda r: r["step"], reverse=True)

    if successes:
        for r in successes:
            print(f"  SUCCESS  {r['tag']}  {r['label']}")
            gds = DESIGN_DIR / "runs" / r["tag"] / "results" / "final" / "gds" / "rvsoc_top.gds"
            print(f"    GDS     → {gds}")
            rpt = DESIGN_DIR / "runs" / r["tag"] / "reports"
            print(f"    Reports → {rpt}")
    else:
        print("  No successful runs. Best attempts (by steps completed):")
        for r in failures[:3]:
            print(f"    {r['tag']}  reached step {r['step']} ({STEPS.get(r['step'],'?')})  [{r['failure']}]  {r['label']}")
        print("\n  Suggestions:")
        top_failure = failures[0]["failure"] if failures else "unknown"
        if top_failure == "io_pins_overflow":
            print("    → All runs hit pin overflow. Try DIE_AREA 900x900 or larger.")
        elif top_failure == "placement":
            print("    → Placement failed. Try PL_TARGET_DENSITY 0.20 with a large die.")
        elif top_failure == "routing":
            print("    → Routing congestion. Try PL_TARGET_DENSITY 0.20.")
        else:
            print(f"    → Most common failure: {top_failure}. Check logs manually.")

if __name__ == "__main__":
    main()
