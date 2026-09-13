#!/usr/bin/env python3
"""gendoc.py — Generate HTML documentation for SoC modules.

Usage:
    python gendoc.py              Generate all modules
    python gendoc.py uart         Generate one module
    python gendoc.py uart spi     Generate specific modules

Outputs: docs/index.html + docs/doc_<module>.html per module
"""

import re
import json
import subprocess
import tempfile
import pathlib
import xml.etree.ElementTree as ET
from datetime import date

REPO = pathlib.Path(__file__).resolve().parents[1]
RTL  = REPO / "rtl/soc"
TB   = REPO / "sim/tb"
DOCS = REPO / "docs"

# Module groups: (group_name, [(module_name, sv_path_relative_to_RTL)])
GROUPS = [
    ("Peripheral", [
        ("uart",             "peripheral/uart.sv"),
        ("spi",              "peripheral/spi.sv"),
        ("gpio",             "peripheral/gpio.sv"),
        ("i2c",              "peripheral/i2c.sv"),
        ("dma",              "peripheral/dma.sv"),
        ("timer",            "peripheral/timer.sv"),
        ("watchdog",         "peripheral/watchdog.sv"),
        ("reset_controller", "peripheral/reset_controller.sv"),
        ("sysinfo",          "peripheral/sysinfo.sv"),
        ("pio_top",          "peripheral/pio/pio_top.sv"),
        ("pio_sm",           "peripheral/pio/pio_sm.sv"),
        ("pio_fifo",         "peripheral/pio/pio_fifo.sv"),
    ]),
    ("Fabric", [
        ("ahb_arbiter",    "fabric/ahb_arbiter.sv"),
        ("ahb_i_decoder",  "fabric/ahb_i_decoder.sv"),
        ("ahb_d_decoder",  "fabric/ahb_d_decoder.sv"),
    ]),
    ("Memory", [
        ("sram_top",  "memory/sram_top.sv"),
        ("sram_bank", "memory/sram_bank.sv"),
    ]),
]

ALL_MODULES = {name: path for _, modules in GROUPS for name, path in modules}


# ---------------------------------------------------------------------------
# Yosys fanout analysis

def yosys_key_signals(sv_path, module_name, top_n=10):
    """Run Yosys, compute fanout of user-named signals. Returns [(name, fanout)]."""
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            json_path = f.name
        subprocess.run(
            ['yosys', '-q', '-p',
             f'read_verilog -sv {sv_path}; hierarchy; proc; write_json {json_path}'],
            capture_output=True, timeout=60, check=True
        )
        with open(json_path) as f:
            data = json.load(f)

        m = data['modules'][module_name]
        user_nets = {k: v for k, v in m['netnames'].items() if v['hide_name'] == 0}

        bit_to_net = {}
        for name, net in user_nets.items():
            for bit in net['bits']:
                if isinstance(bit, int):
                    bit_to_net[bit] = name

        fanout = {k: 0 for k in user_nets}
        for cell in m['cells'].values():
            for port, direction in cell['port_directions'].items():
                if direction == 'input':
                    for bit in cell['connections'][port]:
                        if bit in bit_to_net:
                            fanout[bit_to_net[bit]] += 1

        # Exclude ports and AHB/clock plumbing — not semantically "key"
        exclude = set(m['ports'].keys()) | {
            'active', 'active_r', 'hwrite_r', 'reg_addr_r',
            'hready', 'hresp', 'clk', 'rst_n',
        }
        filtered = {k: v for k, v in fanout.items() if k not in exclude and v > 0}
        return sorted(filtered.items(), key=lambda x: x[1], reverse=True)[:top_n]

    except Exception as e:
        print(f'  Yosys skipped: {e}')
        return []


# ---------------------------------------------------------------------------
# SV parser

def parse_sv(sv_path):
    """Extract registers, localparams, assigns, always blocks from SV file."""
    lines = open(sv_path).readlines()

    result = {
        'header':       [],   # top-of-file comment block
        'regs':         [],   # (name, comment)
        'addr_params':  [],   # (name, word_addr, byte_offset, comment)
        'fsm_groups':   {},   # {prefix: [(name, value, comment)]}
        'other_params': [],   # (name, value, comment)
        'assigns':      [],   # (name, expr, comment)
        'always_blocks':[],   # (sensitivity, comment)
    }

    # Header: comment lines before `module`
    for line in lines:
        if re.match(r'\s*module\s', line):
            break
        if line.startswith('//'):
            result['header'].append(line[2:].strip())

    pending = []   # accumulated // comments before a construct
    i = 0
    while i < len(lines):
        raw  = lines[i]
        line = raw.strip()

        # Section divider resets context
        if re.match(r'//\s*-{10,}', line):
            pending = []
            i += 1
            continue

        # Comment line
        if line.startswith('//'):
            pending.append(line[2:].strip())
            i += 1
            continue

        # Blank line resets pending
        if not line:
            pending = []
            i += 1
            continue

        # --- reg declaration ---
        m = re.match(
            r'reg\s+(?:\[[\d:]+\]\s+)?(\w+)(?:\s*\[.*\])?\s*;\s*(?://\s*(.*))?', line)
        if m:
            name    = m.group(1)
            inline  = (m.group(2) or '').strip()
            comment = ' '.join(pending).strip() or inline
            result['regs'].append((name, comment))
            pending = []
            i += 1
            continue

        # --- localparam ADDR_* ---
        m = re.match(
            r'localparam\s+(?:\[[\d:]+\]\s+)?(ADDR_\w+)\s*=\s*([\w\'h]+);\s*(?://\s*(.*))?', line)
        if m:
            name     = m.group(1)
            word_hex = m.group(2)
            inline   = (m.group(3) or '').strip()
            comment  = ' '.join(pending).strip() or inline
            # Compute byte offset from word address
            try:
                word_addr = int(word_hex, 16) if 'h' in word_hex else int(word_hex, 0)
                byte_off  = f'0x{word_addr * 4:03X}'
            except Exception:
                byte_off = '?'
            result['addr_params'].append((name, word_hex, byte_off, comment))
            pending = []
            i += 1
            continue

        # --- localparam other (FSM states, constants) ---
        m = re.match(
            r'localparam\s+(?:\[[\d:]+\]\s+)?(\w+)\s*=\s*([\w\'hd_]+);\s*(?://\s*(.*))?', line)
        if m:
            name    = m.group(1)
            value   = m.group(2)
            inline  = (m.group(3) or '').strip()
            comment = ' '.join(pending).strip() or inline
            # Group FSM states by prefix (TX_, RX_)
            fsm_match = re.match(r'([A-Z]{2,})_', name)
            if fsm_match and fsm_match.group(1) not in ('FIFO', 'ADDR'):
                prefix = fsm_match.group(1)
                result['fsm_groups'].setdefault(prefix, []).append((name, value, comment))
            else:
                result['other_params'].append((name, value, comment))
            pending = []
            i += 1
            continue

        # --- assign statement ---
        m = re.match(r'assign\s+(\w+)\s*=\s*(.+);', line)
        if m:
            name    = m.group(1)
            expr    = m.group(2).strip()
            comment = ' '.join(pending).strip()
            result['assigns'].append((name, expr, comment))
            pending = []
            i += 1
            continue

        # --- wire with inline assignment ---
        m = re.match(
            r'wire\s+(?:\[[\d:]+\]\s+)?(\w+)\s*=\s*(.+?);\s*(?://\s*(.*))?', line)
        if m:
            name    = m.group(1)
            expr    = m.group(2).strip()
            inline  = (m.group(3) or '').strip()
            comment = ' '.join(pending).strip() or inline
            result['assigns'].append((name, expr, comment))
            pending = []
            i += 1
            continue

        # --- always block ---
        if re.match(r'always\s*[@(]|always\s+@', line):
            comment = ' '.join(pending).strip()
            result['always_blocks'].append((line, comment))
            pending = []
            i += 1
            continue

        # Anything else resets pending
        pending = []
        i += 1

    return result


# ---------------------------------------------------------------------------
# Test parser

def parse_tests(tb_path, results_xml=None):
    """Extract test names, docstrings (purpose + pass condition), status."""
    if not tb_path.exists():
        return []

    source = open(tb_path).read()

    # Load pass/fail from results.xml
    status = {}
    if results_xml and results_xml.exists():
        try:
            for tc in ET.parse(results_xml).iter('testcase'):
                name    = tc.get('name', '')
                skipped = tc.find('skipped') is not None
                failed  = tc.find('failure') is not None or tc.find('error') is not None
                status[name] = 'skip' if skipped else ('fail' if failed else 'pass')
        except Exception:
            pass

    tests = []
    pattern = re.compile(
        r'@cocotb\.test\([^)]*\)\s*\nasync def (\w+)\(dut\):\s*\n\s*"""(.*?)"""',
        re.DOTALL
    )
    for m in pattern.finditer(source):
        name = m.group(1)
        doc  = re.sub(r'\n\s+', '\n', m.group(2)).strip()
        # Split into purpose (first paragraph) and pass condition (rest)
        parts     = re.split(r'\n{2,}', doc, maxsplit=1)
        purpose   = parts[0].strip()
        condition = parts[1].strip() if len(parts) > 1 else ''
        tests.append((name, purpose, condition, status.get(name, 'unknown')))

    return tests


# ---------------------------------------------------------------------------
# Shared CSS

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
}
.sidebar h2 {
  color: var(--fg3); font-size: 0.75em; text-transform: uppercase;
  letter-spacing: 1.5px; padding: 12px 16px 4px; margin: 0;
  border: none;
}
.sidebar a {
  display: block; padding: 4px 16px 4px 24px; color: var(--fg2);
  text-decoration: none; font-size: 0.92em;
}
.sidebar a:hover { background: var(--bg3); color: var(--fg); }
.sidebar a.active { color: var(--accent); background: var(--bg2); border-left: 2px solid var(--accent); padding-left: 22px; }
.sidebar .title {
  padding: 12px 16px; font-size: 1.1em; color: var(--blue);
  font-weight: bold; border-bottom: 1px solid var(--border);
  margin-bottom: 4px;
}

/* --- Main content --- */
.main {
  margin-left: 240px; padding: 32px 40px; max-width: 900px; width: 100%;
}
h1  { color: var(--blue); margin-bottom: 4px; }
h2  { color: var(--accent); border-bottom: 1px solid var(--border); padding-bottom: 4px; }
h4  { color: var(--orange); margin: 12px 0 4px; }
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
.body { padding: 12px 18px; }

table { border-collapse: collapse; width: 100%; margin: 8px 0; }
th    { background: var(--bg2); color: var(--blue); text-align: left; padding: 6px 10px; }
td    { padding: 5px 10px; border-bottom: 1px solid var(--bg3); vertical-align: top; }
tr:hover td { background: var(--bg2); }

.badge {
  display: inline-block; padding: 1px 8px; border-radius: 3px;
  font-size: 0.82em; font-weight: bold; margin-left: 8px;
}
.pass    { background: #1e5c1e; color: #6fcc6f; }
.fail    { background: #5c1e1e; color: #f07070; }
.skip    { background: #3a3a3a; color: #888; }
.unknown { background: #2a2a2a; color: #666; }

.test  { border-left: 3px solid var(--border); padding: 7px 12px; margin: 7px 0; }
.test:hover { border-left-color: var(--accent); background: #232323; }
.test-name { margin-bottom: 3px; }
.test p  { color: var(--fg2); margin: 3px 0; font-size: 0.92em; }
.cond    { color: var(--fg3) !important; }
.cond strong { color: #888; }

.always { border-left: 3px solid var(--accent); padding: 5px 12px; margin: 6px 0; }
.always p { color: #777; margin: 3px 0; }

.key-pill {
  display: inline-block; background: #2a3a2a; color: #6fcc6f;
  border: 1px solid #3a5a3a; border-radius: 3px; padding: 2px 8px;
  margin: 3px; font-size: 0.9em;
}
.fanout { color: #555; font-size: 0.85em; margin-left: 4px; }

/* --- Index page --- */
.index-grid {
  display: grid; grid-template-columns: 1fr; gap: 8px; margin: 8px 0;
}
.mod-card {
  display: flex; align-items: center; gap: 12px;
  padding: 10px 14px; background: var(--bg2); border: 1px solid var(--border);
  border-radius: 5px; text-decoration: none; color: var(--fg);
}
.mod-card:hover { border-color: var(--accent); background: var(--bg3); }
.mod-card .name { color: var(--accent); font-weight: bold; min-width: 160px; }
.mod-card .desc { color: var(--fg2); font-size: 0.9em; }
.mod-count { color: var(--fg3); font-size: 0.85em; margin-left: auto; white-space: nowrap; }
"""


# ---------------------------------------------------------------------------
# HTML helpers

def badge(status):
    labels = {'pass': '+ pass', 'fail': 'x fail', 'skip': '~ skip', 'unknown': '?'}
    return f'<span class="badge {status}">{labels.get(status, status)}</span>'

def section(title, body, open_=False):
    o = ' open' if open_ else ''
    return f'<details{o}><summary>{title}</summary><div class="body">{body}</div></details>\n'

def table(headers, rows):
    ths = ''.join(f'<th>{h}</th>' for h in headers)
    trs = ''.join(
        '<tr>' + ''.join(f'<td>{c}</td>' for c in row) + '</tr>'
        for row in rows
    )
    return f'<table><tr>{ths}</tr>{trs}</table>'

def sidebar_html(active_module=None):
    """Generate the sidebar navigation."""
    links = ''
    for group_name, modules in GROUPS:
        links += f'<h2>{group_name}</h2>\n'
        for name, _ in modules:
            cls = ' class="active"' if name == active_module else ''
            links += f'<a href="doc_{name}.html"{cls}>{name}</a>\n'

    return f'''<nav class="sidebar">
<div class="title"><a href="index.html" style="color:inherit;text-decoration:none">rxpsm32</a></div>
{links}
</nav>'''


# ---------------------------------------------------------------------------
# Module page generator

def get_first_header_line(sv_path):
    """Extract the first comment line (module description) from SV file."""
    try:
        with open(sv_path) as f:
            for line in f:
                if line.startswith('//'):
                    text = line[2:].strip()
                    # Strip "module_name.sv — " prefix
                    m = re.match(r'\w+\.sv\s*[—–-]\s*(.*)', text)
                    return m.group(1) if m else text
                if re.match(r'\s*module\s', line):
                    break
    except Exception:
        pass
    return ''


def generate_module(module, sv_rel_path, run_yosys=True):
    """Generate HTML doc for a single module. Returns (out_path, test_count)."""
    sv_path  = RTL / sv_rel_path
    # Test file: try test_<module>.py
    tb_path  = TB / f'test_{module}.py'
    res_path = TB / 'results.xml'
    out_path = DOCS / f'doc_{module}.html'

    if not sv_path.exists():
        print(f'  Skipping {module}: {sv_path} not found')
        return None, 0

    print(f'  Parsing {sv_path.name}...')
    sv = parse_sv(sv_path)

    tests = parse_tests(tb_path, res_path)

    key_signals = []
    if run_yosys:
        key_signals = yosys_key_signals(sv_path, module)

    # --- Header description ---
    desc = get_first_header_line(sv_path)

    # --- Key signals section ---
    if key_signals:
        pills = ''.join(
            f'<span class="key-pill"><code>{name}</code>'
            f'<span class="fanout">({fanout})</span></span>'
            for name, fanout in key_signals
        )
        key_html = f'<p style="color:#666;margin-bottom:10px">Ranked by fanout — how many logic cells read this signal.</p>{pills}'
    else:
        key_html = '<p style="color:#666"><em>Yosys not available or skipped — fanout analysis not shown.</em></p>'

    # --- Registers section ---
    reg_html = table(
        ['Name', 'Description'],
        [(f'<code>{name}</code>', comment or '<em>-</em>') for name, comment in sv['regs']]
    ) if sv['regs'] else '<p style="color:#666"><em>No register declarations found.</em></p>'

    # --- Address decoder section ---
    addr_html = table(
        ['Register', 'Byte offset', 'Word addr', 'Description'],
        [(f'<code>{name}</code>', f'<code>{byte_off}</code>',
          f'<code>{word}</code>', comment or '<em>-</em>')
         for name, word, byte_off, comment in sv['addr_params']]
    ) if sv['addr_params'] else '<p style="color:#666"><em>No address parameters found.</em></p>'

    # --- FSM states section ---
    fsm_html = ''
    for prefix, states in sv['fsm_groups'].items():
        fsm_html += f'<h4>{prefix} states</h4>'
        fsm_html += table(
            ['Name', 'Value', 'Description'],
            [(f'<code>{n}</code>', f'<code>{v}</code>', c or '<em>-</em>')
             for n, v, c in states]
        )

    if sv['other_params']:
        fsm_html += '<h4>Constants</h4>'
        fsm_html += table(
            ['Name', 'Value', 'Description'],
            [(f'<code>{n}</code>', f'<code>{v}</code>', c or '<em>-</em>')
             for n, v, c in sv['other_params']]
        )

    if not fsm_html:
        fsm_html = '<p style="color:#666"><em>No FSM states or constants found.</em></p>'

    # --- Combinational logic section ---
    assign_html = table(
        ['Signal', 'Expression', 'Description'],
        [(f'<code>{name}</code>',
          f'<code title="{expr}">{expr[:70]}{"..." if len(expr) > 70 else ""}</code>',
          comment or '<em>-</em>')
         for name, expr, comment in sv['assigns']]
    ) if sv['assigns'] else '<p style="color:#666"><em>No assign statements found.</em></p>'

    # --- Always blocks section ---
    always_html = ''.join(
        f'<div class="always"><code>{sens}</code>'
        f'{"<p>" + c + "</p>" if c else ""}</div>'
        for sens, c in sv['always_blocks']
    ) if sv['always_blocks'] else '<p style="color:#666"><em>No always blocks found.</em></p>'

    # --- Tests section ---
    total   = len(tests)
    passed  = sum(1 for *_, st in tests if st == 'pass')
    failed  = sum(1 for *_, st in tests if st == 'fail')
    skipped = sum(1 for *_, st in tests if st == 'skip')
    unknown = sum(1 for *_, st in tests if st == 'unknown')

    if total > 0:
        summary = (f'<p style="color:#888">{total} tests &mdash; '
                   f'{passed} pass &nbsp; {failed} fail &nbsp; '
                   f'{skipped} skip &nbsp; {unknown} not run</p>')

        test_items = ''
        for name, purpose, condition, st in tests:
            cond = (f'<p class="cond"><strong>Pass:</strong> {condition}</p>'
                    if condition else '')
            test_items += (
                f'<div class="test">'
                f'<div class="test-name"><code>{name}</code>{badge(st)}</div>'
                f'<p>{purpose}</p>{cond}'
                f'</div>'
            )

        test_html = summary + test_items
    else:
        test_html = '<p style="color:#666"><em>No testbench found.</em></p>'

    # --- Header block (from SV comments) ---
    header_html = ''
    if sv['header']:
        header_html = '<pre style="color:#888;font-size:0.9em;line-height:1.5;margin:8px 0;white-space:pre-wrap">'
        header_html += '\n'.join(sv['header'])
        header_html += '</pre>'

    # --- Assemble full HTML ---
    test_label = f'Tests ({total})' if total > 0 else 'Tests'
    html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{module} — rxpsm32 docs</title>
<style>{CSS}</style>
</head>
<body>
{sidebar_html(module)}
<div class="main">
<h1>{module}.sv</h1>
<p style="color:#555">{desc} &nbsp;&middot;&nbsp; Generated {date.today()}</p>

{section("Module header", header_html, open_=True) if header_html else ""}
{section("Key signals", key_html)}
{section("Registers", reg_html, open_=True)}
{section("Address decoder", addr_html)}
{section("FSM states &amp; constants", fsm_html)}
{section("Combinational logic", assign_html)}
{section("Always blocks", always_html)}
{section(test_label, test_html)}
</div>
</body>
</html>'''

    out_path.write_text(html)
    return out_path, total


# ---------------------------------------------------------------------------
# Index page generator

def generate_index(module_info):
    """Generate index.html with cards for all modules, grouped."""
    out_path = DOCS / 'index.html'

    body = ''
    for group_name, modules in GROUPS:
        body += f'<h2>{group_name}</h2>\n<div class="index-grid">\n'
        for name, sv_rel in modules:
            sv_path = RTL / sv_rel
            desc = get_first_header_line(sv_path) if sv_path.exists() else ''
            test_count = module_info.get(name, 0)
            count_label = f'{test_count} tests' if test_count > 0 else 'no tests'
            exists = sv_path.exists()
            if exists:
                body += (
                    f'<a class="mod-card" href="doc_{name}.html">'
                    f'<span class="name">{name}</span>'
                    f'<span class="desc">{desc}</span>'
                    f'<span class="mod-count">{count_label}</span>'
                    f'</a>\n'
                )
            else:
                body += (
                    f'<div class="mod-card" style="opacity:0.4">'
                    f'<span class="name">{name}</span>'
                    f'<span class="desc">not yet implemented</span>'
                    f'</div>\n'
                )
        body += '</div>\n'

    html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>rxpsm32 — SoC documentation</title>
<style>{CSS}</style>
</head>
<body>
{sidebar_html()}
<div class="main">
<h1>rxpsm32 SoC</h1>
<p style="color:#555">RISC-V SoC documentation &nbsp;&middot;&nbsp; Generated {date.today()}</p>
{body}
</div>
</body>
</html>'''

    out_path.write_text(html)
    print(f'Index -> {out_path}')
    return out_path


# ---------------------------------------------------------------------------
# Main

def main():
    import sys

    DOCS.mkdir(exist_ok=True)

    if len(sys.argv) > 1:
        targets = sys.argv[1:]
    else:
        targets = list(ALL_MODULES.keys())

    # Check if yosys is available
    try:
        subprocess.run(['yosys', '--version'], capture_output=True, timeout=5)
        has_yosys = True
    except Exception:
        has_yosys = False
        print('Yosys not found — skipping fanout analysis')

    module_info = {}  # name -> test_count
    for name in targets:
        if name not in ALL_MODULES:
            print(f'Unknown module: {name}')
            print(f'Available: {", ".join(ALL_MODULES.keys())}')
            continue
        print(f'[{name}]')
        out, tc = generate_module(name, ALL_MODULES[name], run_yosys=has_yosys)
        if out:
            module_info[name] = tc
            print(f'  -> {out}')

    # Always regenerate index
    generate_index(module_info)


if __name__ == '__main__':
    main()
