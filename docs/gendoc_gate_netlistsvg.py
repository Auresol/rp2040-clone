#!/usr/bin/env python3
"""gendoc_gate.py — Generate gate-level schematic HTML docs using Yosys + netlistsvg.

Usage:
    python3 docs/gendoc_gate.py              Generate all modules
    python3 docs/gendoc_gate.py uart         Generate only specific modules
    python3 docs/gendoc_gate.py uart gpio    Generate multiple specific modules

Outputs: docs/gates.html

Requirements:
    - yosys       (synthesis to JSON netlist)
    - netlistsvg  (JSON netlist → SVG schematic)
    - Node.js     (netlistsvg is an npm package)

Install netlistsvg:
    npm install -g netlistsvg
"""

import json
import subprocess
import tempfile
import pathlib
import sys
from html import escape
from datetime import date

REPO = pathlib.Path(__file__).resolve().parents[1]
RTL  = REPO / "rtl/soc"
DOCS = REPO / "docs"

# Modules available for gate-level docs
# (module_name, sv_path_relative_to_RTL, yosys_top_module)
MODULES = [
    ("uart",             "peripheral/uart.sv",              "uart"),
    ("spi",              "peripheral/spi.sv",               "spi"),
    ("gpio",             "peripheral/gpio.sv",              "gpio"),
    ("i2c",              "peripheral/i2c.sv",               "i2c"),
    ("dma",              "peripheral/dma.sv",               "dma"),
    ("timer",            "peripheral/timer.sv",             "timer"),
    ("watchdog",         "peripheral/watchdog.sv",          "watchdog"),
    ("reset_controller", "peripheral/reset_controller.sv",  "reset_controller"),
    ("sysinfo",          "peripheral/sysinfo.sv",           "sysinfo"),
]

ALL_MODULE_NAMES = [name for name, _, _ in MODULES]


def check_tools():
    """Check that yosys and netlistsvg are available."""
    missing = []
    for tool in ['yosys', 'netlistsvg']:
        try:
            subprocess.run([tool, '--version' if tool == 'yosys' else '--help'],
                           capture_output=True, timeout=10)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            missing.append(tool)
    return missing


def synth_to_rtl_json(sv_path, top_module):
    """Run Yosys with minimal passes for RTL-level (high-level) view."""
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
        json_path = f.name

    script = f"""
read_verilog -sv {sv_path}
hierarchy -top {top_module}
proc
opt
write_json {json_path}
"""
    result = subprocess.run(
        ['yosys', '-q', '-p', script],
        capture_output=True, text=True, timeout=120
    )

    if result.returncode != 0:
        raise RuntimeError(f"Yosys failed:\n{result.stderr}")

    with open(json_path) as f:
        data = json.load(f)

    pathlib.Path(json_path).unlink(missing_ok=True)
    return data


SVG_DIR = DOCS / "svg"


def json_to_svg(netlist_json, name):
    """Run netlistsvg on a JSON netlist dict, save to docs/svg/{name}.svg."""
    SVG_DIR.mkdir(exist_ok=True)

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False, mode='w') as jf:
        json.dump(netlist_json, jf)
        json_path = jf.name

    svg_path = SVG_DIR / f'{name}.svg'

    result = subprocess.run(
        ['netlistsvg', json_path, '-o', str(svg_path)],
        capture_output=True, text=True, timeout=120
    )

    pathlib.Path(json_path).unlink(missing_ok=True)

    if result.returncode != 0:
        raise RuntimeError(f"netlistsvg failed:\n{result.stderr}")

    # Patch SVG: add white background rect after opening <svg> tag
    svg_text = svg_path.read_text()
    svg_text = svg_text.replace(
        '<style>svg {',
        '<rect width="100%" height="100%" fill="white"/>\n  <style>svg {',
        1
    )
    svg_path.write_text(svg_text)

    return f'svg/{name}.svg'


def get_stats(netlist_json, top_module):
    """Extract cell counts from Yosys JSON netlist."""
    mod = netlist_json['modules'].get(top_module, {})
    cells = mod.get('cells', {})

    counts = {}
    for cell in cells.values():
        ctype = cell['type']
        counts[ctype] = counts.get(ctype, 0) + 1

    total = len(cells)
    return total, sorted(counts.items(), key=lambda x: x[1], reverse=True)


def get_first_header_line(sv_path):
    """Extract module description from SV file header comment."""
    try:
        with open(sv_path) as f:
            for line in f:
                if line.startswith('//'):
                    import re
                    text = line[2:].strip()
                    m = re.match(r'\w+\.sv\s*[—–-]\s*(.*)', text)
                    return m.group(1) if m else text
                if line.lstrip().startswith('module'):
                    break
    except Exception:
        pass
    return ''


def build_module_html(name, sv_rel, top_module):
    """Build HTML fragment for one module. Returns HTML string or None."""
    sv_path = RTL / sv_rel
    if not sv_path.exists():
        print(f'  Skipping {name}: {sv_path} not found')
        return None

    desc = get_first_header_line(sv_path)

    print(f'  [{name}] Synthesizing RTL-level...')
    try:
        rtl_json = synth_to_rtl_json(sv_path, top_module)
        svg_rel = json_to_svg(rtl_json, name)
        rtl_total, rtl_counts = get_stats(rtl_json, top_module)
    except Exception as e:
        print(f'    Failed: {e}')
        return None

    # Stats table
    def stats_table(total, counts):
        if not counts:
            return '<p style="color:#666"><em>No data</em></p>'
        rows = ''.join(
            f'<tr><td><code>{ctype}</code></td><td>{count}</td></tr>'
            for ctype, count in counts[:20]
        )
        return (f'<p style="color:#888">Total cells: <strong>{total}</strong></p>'
                f'<table><tr><th>Cell type</th><th>Count</th></tr>{rows}</table>')

    html = f'''<div class="module-section" id="{name}">
<h1>{name}.sv</h1>
<p style="color:#555">{escape(desc)}</p>
<details open>
<summary>RTL-level schematic</summary>
<div class="body">
<div class="schematic-viewport" data-svg="{svg_rel}">
  <div class="zoom-controls">
    <button onclick="zoomFit(this)">Fit</button>
    <button onclick="zoomIn(this)">+</button>
    <button onclick="zoomOut(this)">&minus;</button>
    <button onclick="zoom100(this)">1:1</button>
  </div>
  <div class="svg-container">
    <img src="{svg_rel}" draggable="false">
  </div>
</div>
<div class="stats">
{stats_table(rtl_total, rtl_counts)}
</div>
</div>
</details>
</div>
'''
    return html


# ---------------------------------------------------------------------------
# CSS (matching gendoc.py sidebar style)

CSS = """
:root {
  --bg: #1e1e1e; --bg2: #252526; --bg3: #2a2a2a;
  --fg: #d4d4d4; --fg2: #aaa; --fg3: #666;
  --accent: #4ec9b0; --blue: #9cdcfe; --orange: #ce9178;
  --border: #333;
}
* { box-sizing: border-box; }
body {
  font-family: 'Consolas', 'Menlo', monospace;
  background: var(--bg); color: var(--fg); font-size: 14px;
  margin: 0; padding: 0; display: flex; min-height: 100vh;
}

/* --- Sidebar --- */
.sidebar {
  width: 240px; min-width: 240px; background: #181818;
  border-right: 1px solid var(--border); padding: 16px 0;
  position: fixed; top: 0; bottom: 0; overflow-y: auto;
  z-index: 10;
}
.sidebar h2 {
  color: var(--fg3); font-size: 0.75em; text-transform: uppercase;
  letter-spacing: 1.5px; padding: 12px 16px 4px; margin: 0;
  border: none;
}
.sidebar a {
  display: block; padding: 4px 16px 4px 24px; color: var(--fg2);
  text-decoration: none; font-size: 0.92em; transition: background 0.1s;
}
.sidebar a:hover { background: var(--bg3); color: var(--fg); }
.sidebar a.active {
  color: var(--accent); background: var(--bg2);
  border-left: 2px solid var(--accent); padding-left: 22px;
}
.sidebar .title {
  padding: 12px 16px; font-size: 1.1em; color: var(--blue);
  font-weight: bold; border-bottom: 1px solid var(--border);
  margin-bottom: 4px;
}
.sidebar .doc-links {
  border-top: 1px solid var(--border);
  margin-top: 8px; padding-top: 8px;
}
.sidebar .doc-links a {
  color: var(--fg3); font-size: 0.85em;
}

/* --- Main content — full width --- */
.main {
  margin-left: 240px; padding: 16px 24px; width: calc(100% - 240px);
}

.module-section {
  padding-top: 12px; margin-bottom: 24px;
  border-top: 1px solid var(--border);
  scroll-margin-top: 16px;
}
.module-section:first-child { border-top: none; }

h1  { color: var(--blue); margin-bottom: 4px; }
h2  { color: var(--accent); border-bottom: 1px solid var(--border); padding-bottom: 4px; }
p   { margin: 6px 0; }
code { color: var(--orange); }
a   { color: var(--accent); }

details { margin: 10px 0; border: 1px solid var(--border); border-radius: 5px; }
summary {
  padding: 9px 14px; cursor: pointer; font-size: 1.05em;
  color: var(--accent); background: var(--bg2); border-radius: 5px;
  user-select: none; list-style: none;
}
summary:hover { background: var(--bg3); }
.body { padding: 0; }

table { border-collapse: collapse; width: auto; margin: 8px 12px; }
th    { background: var(--bg2); color: var(--blue); text-align: left; padding: 6px 10px; }
td    { padding: 5px 10px; border-bottom: 1px solid var(--bg3); vertical-align: top; }
tr:hover td { background: var(--bg2); }

/* Schematic viewport — pan & zoom via JS */
.schematic-viewport {
  position: relative;
  background: #fff; border-radius: 4px;
  overflow: hidden; cursor: grab;
  height: calc(100vh - 160px);
  width: 100%;
}
.schematic-viewport:active { cursor: grabbing; }
.schematic-viewport .svg-container {
  transform-origin: 0 0;
  position: absolute; top: 0; left: 0;
}
.schematic-viewport .svg-container img {
  display: block;
}

/* Zoom controls */
.zoom-controls {
  position: absolute; top: 8px; right: 8px; z-index: 5;
  display: flex; gap: 4px;
}
.zoom-controls button {
  background: var(--bg2); color: var(--fg); border: 1px solid var(--border);
  border-radius: 4px; padding: 4px 10px; cursor: pointer;
  font-family: inherit; font-size: 0.9em;
}
.zoom-controls button:hover { background: var(--bg3); }

.stats { padding: 8px 12px; }

.gen-info {
  color: var(--fg3); font-size: 0.85em; margin-top: 32px;
  border-top: 1px solid var(--border); padding-top: 8px;
}
"""

SCRIPT = """
<script>
// --- Sidebar active link ---
(function() {
  const links = document.querySelectorAll('.sidebar a[href^="#"]');
  const sections = [];
  links.forEach(a => {
    const id = a.getAttribute('href').slice(1);
    const el = document.getElementById(id);
    if (el) sections.push({el, a});
  });
  if (!sections.length) return;
  function update() {
    let current = sections[0];
    for (const s of sections) {
      if (s.el.getBoundingClientRect().top <= 80) current = s;
    }
    links.forEach(a => a.classList.remove('active'));
    current.a.classList.add('active');
  }
  window.addEventListener('scroll', update, {passive: true});
  update();
})();

// --- Pan & zoom for schematic viewports ---
document.querySelectorAll('.schematic-viewport').forEach(vp => {
  const container = vp.querySelector('.svg-container');
  const img = container.querySelector('img');
  let scale = 1, panX = 0, panY = 0;
  let dragging = false, startX, startY, startPanX, startPanY;

  function apply() {
    container.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
  }

  // Fit to viewport on load
  img.addEventListener('load', () => fitToBox(vp));

  // Mouse wheel zoom
  vp.addEventListener('wheel', e => {
    e.preventDefault();
    const rect = vp.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    const newScale = Math.max(0.02, Math.min(20, scale * factor));
    // Zoom toward cursor
    panX = mx - (mx - panX) * (newScale / scale);
    panY = my - (my - panY) * (newScale / scale);
    scale = newScale;
    apply();
  }, {passive: false});

  // Pan with mouse drag
  vp.addEventListener('mousedown', e => {
    if (e.button !== 0) return;
    dragging = true;
    startX = e.clientX; startY = e.clientY;
    startPanX = panX; startPanY = panY;
  });
  window.addEventListener('mousemove', e => {
    if (!dragging) return;
    panX = startPanX + (e.clientX - startX);
    panY = startPanY + (e.clientY - startY);
    apply();
  });
  window.addEventListener('mouseup', () => { dragging = false; });

  // Store state on the viewport element for button access
  vp._pz = { getScale: () => scale, setView: (s, x, y) => { scale = s; panX = x; panY = y; apply(); } };
});

function getVP(btn) { return btn.closest('.schematic-viewport'); }

function fitToBox(vp) {
  const img = vp.querySelector('img');
  const rect = vp.getBoundingClientRect();
  const sx = rect.width / img.naturalWidth;
  const sy = rect.height / img.naturalHeight;
  const s = Math.min(sx, sy) * 0.95;
  const px = (rect.width - img.naturalWidth * s) / 2;
  const py = (rect.height - img.naturalHeight * s) / 2;
  vp._pz.setView(s, px, py);
}

function zoomFit(btn) { fitToBox(getVP(btn)); }
function zoomIn(btn) {
  const vp = getVP(btn); const s = vp._pz.getScale();
  const rect = vp.getBoundingClientRect();
  const cx = rect.width / 2, cy = rect.height / 2;
  // Zoom toward center
  const container = vp.querySelector('.svg-container');
  const t = new DOMMatrix(getComputedStyle(container).transform);
  const newS = s * 1.4;
  vp._pz.setView(newS, cx - (cx - t.e) * (newS / s), cy - (cy - t.f) * (newS / s));
}
function zoomOut(btn) {
  const vp = getVP(btn); const s = vp._pz.getScale();
  const rect = vp.getBoundingClientRect();
  const cx = rect.width / 2, cy = rect.height / 2;
  const container = vp.querySelector('.svg-container');
  const t = new DOMMatrix(getComputedStyle(container).transform);
  const newS = s / 1.4;
  vp._pz.setView(newS, cx - (cx - t.e) * (newS / s), cy - (cy - t.f) * (newS / s));
}
function zoom100(btn) {
  const vp = getVP(btn);
  const rect = vp.getBoundingClientRect();
  vp._pz.setView(1, 0, 0);
}
</script>
"""


def main():
    DOCS.mkdir(exist_ok=True)

    # Parse CLI args for module filter
    requested = sys.argv[1:] if len(sys.argv) > 1 else None
    if requested:
        unknown = [m for m in requested if m not in ALL_MODULE_NAMES]
        if unknown:
            print(f"Unknown modules: {', '.join(unknown)}")
            print(f"Available: {', '.join(ALL_MODULE_NAMES)}")
            sys.exit(1)

    # Check tools
    missing = check_tools()
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        print("Install with:")
        if 'yosys' in missing:
            print("  nix-shell -p yosys  (or apt install yosys)")
        if 'netlistsvg' in missing:
            print("  npm install -g netlistsvg")
        sys.exit(1)

    # Filter modules
    modules = MODULES
    if requested:
        modules = [(n, p, t) for n, p, t in MODULES if n in requested]

    # Build sidebar
    sidebar_links = '<h2>Modules</h2>\n'
    for name, sv_rel, _ in modules:
        sv_path = RTL / sv_rel
        if sv_path.exists():
            sidebar_links += f'<a href="#{name}">{name}</a>\n'
        else:
            sidebar_links += f'<a href="#{name}" style="opacity:0.35">{name}</a>\n'

    sidebar = f'''<nav class="sidebar">
<div class="title">Gate-level docs</div>
{sidebar_links}
<div class="doc-links">
<h2>Other docs</h2>
<a href="rxpsm32.html">SoC docs</a>
</div>
</nav>'''

    # Build module sections
    sections = ''
    for name, sv_rel, top in modules:
        html = build_module_html(name, sv_rel, top)
        if html:
            sections += html

    out_path = DOCS / 'gates.html'
    full_html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>rxpsm32 — Gate-level schematics</title>
<style>{CSS}</style>
</head>
<body>
{sidebar}
<div class="main">
<h2 style="margin-top:0">RTL schematics</h2>
<p style="color:#666">Synthesized with Yosys, rendered with netlistsvg.
High-level view showing muxes, adders, flip-flops, and memories.</p>
{sections}
<p class="gen-info">Generated {date.today()} by gendoc_gate.py</p>
</div>
{SCRIPT}
</body>
</html>'''

    out_path.write_text(full_html)
    print(f'\nDone -> {out_path}')


if __name__ == '__main__':
    main()
