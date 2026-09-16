#!/usr/bin/env python3
"""Merge OpenLane base config with an overlay JSON, write to config.json."""
import json
import sys

if len(sys.argv) < 4:
    print(f"Usage: {sys.argv[0]} <base.json> <overlay.json> <output.json>", file=sys.stderr)
    sys.exit(1)

base_path, overlay_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(base_path) as f:
    base = json.load(f)
with open(overlay_path) as f:
    overlay = json.load(f)

# Drop description-only keys from overlay
merged = {**base, **{k: v for k, v in overlay.items() if not k.startswith("_")}}

with open(output_path, "w") as f:
    json.dump(merged, f, indent=4)
    f.write("\n")

print(f"Merged {base_path} + {overlay_path} -> {output_path}")
