#!/usr/bin/env python3
"""gendoc.py — Generate single-page HTML documentation for the rxpsm32 SoC.

Usage:
    python gendoc.py              Generate all modules
    python gendoc.py uart         Generate only specific modules
    python gendoc.py uart spi     Generate multiple specific modules

Outputs: docs/rxpsm32.html
"""

import re
import json
import subprocess
import tempfile
import pathlib
import xml.etree.ElementTree as ET
from datetime import date
from html import escape

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
        'header':       [],
        'regs':         [],
        'addr_params':  [],
        'fsm_groups':   {},
        'other_params': [],
        'assigns':      [],
        'always_blocks':[],
    }

    for line in lines:
        if re.match(r'\s*module\s', line):
            break
        if line.startswith('//'):
            result['header'].append(line[2:].strip())

    pending = []
    i = 0
    while i < len(lines):
        raw  = lines[i]
        line = raw.strip()

        if re.match(r'//\s*-{10,}', line):
            pending = []
            i += 1
            continue

        if line.startswith('//'):
            pending.append(line[2:].strip())
            i += 1
            continue

        if not line:
            pending = []
            i += 1
            continue

        m = re.match(
            r'reg\s+(?:\[[\d:]+\]\s+)?(\w+)(?:\s*\[.*\])?\s*;\s*(?://\s*(.*))?', line)
        if m:
            name    = m.group(1)
            inline  = (m.group(2) or '').strip()
            comment = ' '.join(pending).strip() or inline
            result['regs'].append((name, comment))
            pending = []; i += 1; continue

        m = re.match(
            r'localparam\s+(?:\[[\d:]+\]\s+)?(ADDR_\w+)\s*=\s*([\w\'h]+);\s*(?://\s*(.*))?', line)
        if m:
            name     = m.group(1)
            word_hex = m.group(2)
            inline   = (m.group(3) or '').strip()
            comment  = ' '.join(pending).strip() or inline
            try:
                word_addr = int(word_hex, 16) if 'h' in word_hex else int(word_hex, 0)
                byte_off  = f'0x{word_addr * 4:03X}'
            except Exception:
                byte_off = '?'
            result['addr_params'].append((name, word_hex, byte_off, comment))
            pending = []; i += 1; continue

        m = re.match(
            r'localparam\s+(?:\[[\d:]+\]\s+)?(\w+)\s*=\s*([\w\'hd_]+);\s*(?://\s*(.*))?', line)
        if m:
            name    = m.group(1)
            value   = m.group(2)
            inline  = (m.group(3) or '').strip()
            comment = ' '.join(pending).strip() or inline
            fsm_match = re.match(r'([A-Z]{2,})_', name)
            if fsm_match and fsm_match.group(1) not in ('FIFO', 'ADDR'):
                prefix = fsm_match.group(1)
                result['fsm_groups'].setdefault(prefix, []).append((name, value, comment))
            else:
                result['other_params'].append((name, value, comment))
            pending = []; i += 1; continue

        m = re.match(r'assign\s+(\w+)\s*=\s*(.+);', line)
        if m:
            result['assigns'].append((m.group(1), m.group(2).strip(), ' '.join(pending).strip()))
            pending = []; i += 1; continue

        m = re.match(
            r'wire\s+(?:\[[\d:]+\]\s+)?(\w+)\s*=\s*(.+?);\s*(?://\s*(.*))?', line)
        if m:
            inline  = (m.group(3) or '').strip()
            comment = ' '.join(pending).strip() or inline
            result['assigns'].append((m.group(1), m.group(2).strip(), comment))
            pending = []; i += 1; continue

        if re.match(r'always\s*[@(]|always\s+@', line):
            result['always_blocks'].append((line, ' '.join(pending).strip()))
            pending = []; i += 1; continue

        pending = []
        i += 1

    return result


# ---------------------------------------------------------------------------
# Test parser

def parse_tests(tb_path, results_xml=None):
    """Extract test names, docstrings, status."""
    if not tb_path.exists():
        return []

    source = open(tb_path).read()

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
        parts     = re.split(r'\n{2,}', doc, maxsplit=1)
        purpose   = parts[0].strip()
        condition = parts[1].strip() if len(parts) > 1 else ''
        tests.append((name, purpose, condition, status.get(name, 'unknown')))

    return tests


# ---------------------------------------------------------------------------
# HTML helpers

def get_first_header_line(sv_path):
    """Extract the first comment line (module description) from SV file."""
    try:
        with open(sv_path) as f:
            for line in f:
                if line.startswith('//'):
                    text = line[2:].strip()
                    m = re.match(r'\w+\.sv\s*[—–-]\s*(.*)', text)
                    return m.group(1) if m else text
                if re.match(r'\s*module\s', line):
                    break
    except Exception:
        pass
    return ''

def badge(st):
    labels = {'pass': '+ pass', 'fail': 'x fail', 'skip': '~ skip', 'unknown': '?'}
    return f'<span class="badge {st}">{labels.get(st, st)}</span>'

def det(title, body, open_=False):
    o = ' open' if open_ else ''
    return f'<details{o}><summary>{title}</summary><div class="body">{body}</div></details>\n'

def tbl(headers, rows):
    ths = ''.join(f'<th>{h}</th>' for h in headers)
    trs = ''.join(
        '<tr>' + ''.join(f'<td>{c}</td>' for c in row) + '</tr>'
        for row in rows
    )
    return f'<table><tr>{ths}</tr>{trs}</table>'


# ---------------------------------------------------------------------------
# CSS

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
  margin-bottom: 4px; cursor: pointer;
}

/* --- Main content --- */
.main {
  margin-left: 240px; padding: 32px 40px; max-width: 900px; width: 100%;
}

/* Module sections */
.module-section {
  padding-top: 20px; margin-bottom: 48px;
  border-top: 1px solid var(--border);
}
.module-section:first-child { border-top: none; }

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

/* scroll offset for fixed sidebar */
.module-section { scroll-margin-top: 16px; }

/* Mermaid diagram */
.mermaid { background: var(--bg2); border-radius: 4px; padding: 16px; margin: 8px 0; }
.mermaid svg { max-width: 100%; height: auto; }
"""

SCRIPT = """
<script>
// Highlight active sidebar link on scroll
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
</script>
"""


# ---------------------------------------------------------------------------
# Mermaid block diagram extractor

def extract_block_diagram(sv_path):
    """Parse SV source and generate a Mermaid block diagram string.

    Extracts: I/O ports, FIFOs, FSMs, register groups, sub-module instances,
    and infers data flow edges between them.
    """
    source = open(sv_path).read()
    lines = source.split('\n')

    # --- Extract module ports ---
    inputs = []
    outputs = []
    in_module = False
    for line in lines:
        stripped = line.strip()
        if re.match(r'module\s+\w+', stripped):
            in_module = True
        if in_module:
            # Skip clk, rst, AHB boilerplate
            if re.match(r'(input|output)\s+wire\s+.*\b(clk|rst_n|haddr|hwrite|htrans|hsize|hwdata|hrdata|hready|hresp)\b', stripped):
                continue
            m = re.match(r'input\s+wire\s+(?:\[[\d:]+\]\s+)?(\w+)', stripped)
            if m:
                inputs.append(m.group(1))
            m = re.match(r'output\s+(?:wire|reg)\s+(?:\[[\d:]+\]\s+)?(\w+)', stripped)
            if m:
                outputs.append(m.group(1))
            if stripped.startswith(');'):
                break

    # --- Extract FIFOs (reg arrays with _mem suffix, or _wptr/_rptr pairs) ---
    fifos = []
    fifo_names = set()
    # Method 1: explicit mem arrays like "reg [7:0] tx_mem [0:7]" or "[0:DEPTH-1]"
    for line in lines:
        m = re.match(r'\s*reg\s+\[[\d:]+\]\s+(\w+_mem)\s*\[0:(.+?)\]\s*;', line)
        if m:
            name = m.group(1)
            bound_str = m.group(2).strip()
            # Try to resolve depth
            try:
                depth = int(bound_str) + 1
            except ValueError:
                depth = 0  # parameterized — unknown
            prefix = name.replace('_mem', '').upper()
            fifos.append((prefix, depth))
            fifo_names.add(name.replace('_mem', ''))
    # Method 2: detect _wptr/_rptr pairs without _mem array
    wptr_prefixes = set()
    for line in lines:
        m = re.match(r'\s*reg\s+\[[\d:]+\]\s+(\w+)_wptr\b', line)
        if m:
            wptr_prefixes.add(m.group(1))
    for line in lines:
        m = re.match(r'\s*reg\s+\[[\d:]+\]\s+(\w+)_rptr\b', line)
        if m and m.group(1) in wptr_prefixes and m.group(1) not in fifo_names:
            prefix = m.group(1).upper()
            fifos.append((prefix, 0))
            fifo_names.add(m.group(1))

    # Try to resolve FIFO depths from localparam
    depth_params = {}
    for line in lines:
        m = re.match(r'\s*localparam\s+(?:\[[\d:]+\]\s+)?(\w+)\s*=\s*(\d+)', line)
        if m:
            depth_params[m.group(1)] = int(m.group(2))
    for i, (prefix, depth) in enumerate(fifos):
        if depth == 0:
            # Look for FIFO_DEPTH or similar
            for pname, pval in depth_params.items():
                if 'DEPTH' in pname or 'SIZE' in pname:
                    fifos[i] = (prefix, pval)
                    break

    # --- Extract FSMs (localparam groups with _IDLE/_START etc.) ---
    fsm_prefixes = set()
    fsm_states = {}
    for line in lines:
        m = re.match(r'\s*localparam\s+\[[\d:]+\]\s+([A-Z]+)_(\w+)\s*=', line)
        if m:
            prefix = m.group(1)
            state = m.group(2)
            if prefix not in ('ADDR', 'FIFO', 'SEL'):
                fsm_prefixes.add(prefix)
                fsm_states.setdefault(prefix, []).append(state)

    # --- Extract sub-module instances ---
    submodules = []
    for line in lines:
        m = re.match(r'\s*(\w+)\s+(?:#\s*\([^)]*\)\s+)?(\w+)\s*\(', line)
        if m:
            mod_type = m.group(1)
            inst_name = m.group(2)
            # Skip keywords and parameter declarations
            if mod_type not in ('module', 'assign', 'always', 'if', 'else', 'case',
                                'wire', 'reg', 'input', 'output', 'localparam',
                                'generate', 'for', 'function', 'begin', 'end'):
                submodules.append((mod_type, inst_name))

    # --- Extract register groups from comments ---
    reg_groups = []
    for line in lines:
        m = re.match(r'\s*//\s*[-=]+\s*$', line)
        if m:
            continue
        m = re.match(r'\s*//\s+([\w\s]+)(?:registers?|handler|logic|machine)', line, re.I)
        if m:
            name = m.group(1).strip()
            if name and len(name) < 40:
                reg_groups.append(name)

    # --- Extract config register names ---
    config_regs = []
    in_config = False
    for line in lines:
        if re.search(r'config|control|setting', line, re.I) and line.strip().startswith('//'):
            in_config = True
            continue
        if in_config:
            m = re.match(r'\s*reg\s+(?:\[[\d:]+\]\s+)?(\w+)\s*;', line)
            if m:
                config_regs.append(m.group(1))
            elif line.strip().startswith('//') and re.match(r'\s*//\s*[-=]+', line):
                in_config = False

    # --- Build mermaid diagram ---
    nodes = []
    edges = []
    node_ids = set()

    def add_node(nid, label, shape='rect'):
        if nid not in node_ids:
            node_ids.add(nid)
            if shape == 'round':
                nodes.append(f'    {nid}(["{label}"])')
            elif shape == 'hex':
                nodes.append(f'    {nid}{{{{{label}}}}}')
            elif shape == 'stadium':
                nodes.append(f'    {nid}(["{label}"])')
            elif shape == 'cylinder':
                nodes.append(f'    {nid}[("{label}")]')
            else:
                nodes.append(f'    {nid}["{label}"]')

    # AHB bus interface
    add_node('AHB', 'AHB Bus', 'round')

    # Register decode
    add_node('REG_DECODE', 'Register\\nDecode')
    edges.append('    AHB --> REG_DECODE')

    # Config registers (if any)
    if config_regs:
        label = 'Config Regs\\n' + ', '.join(config_regs[:6])
        if len(config_regs) > 6:
            label += f'\\n+{len(config_regs)-6} more'
        add_node('CONFIG', label)
        edges.append('    REG_DECODE --> CONFIG')

    # FIFOs
    for prefix, depth in fifos:
        nid = f'FIFO_{prefix}'
        depth_str = f'\\n{depth}-deep' if depth > 0 else ''
        add_node(nid, f'{prefix} FIFO{depth_str}', 'cylinder')

    # FSMs
    for prefix in sorted(fsm_prefixes):
        nid = f'FSM_{prefix}'
        states = fsm_states.get(prefix, [])
        state_str = ', '.join(states[:5])
        if len(states) > 5:
            state_str += '...'
        add_node(nid, f'{prefix} FSM\\n{state_str}', 'hex')

    # Connect FIFOs <-> FSMs and register decode based on TX/RX semantics:
    #   TX path: CPU --> REG_DECODE --> TX_FIFO --> TX_FSM --> tx_pin
    #   RX path: rx_pin --> RX_FSM --> RX_FIFO --> READ_MUX --> CPU
    for prefix, _ in fifos:
        p = prefix.lower()
        fifo_nid = f'FIFO_{prefix}'
        fsm_nid = f'FSM_{prefix}' if prefix in fsm_prefixes else None

        if 'tx' in p:
            # Write path: decode -> fifo -> fsm
            edges.append(f'    REG_DECODE --> {fifo_nid}')
            if fsm_nid:
                edges.append(f'    {fifo_nid} --> {fsm_nid}')
        elif 'rx' in p:
            # Read path: fsm -> fifo -> read mux
            if fsm_nid:
                edges.append(f'    {fsm_nid} --> {fifo_nid}')
        else:
            # Generic: both directions
            edges.append(f'    REG_DECODE --> {fifo_nid}')
            if fsm_nid:
                edges.append(f'    {fifo_nid} --> {fsm_nid}')

    # FSMs without a matching FIFO get connected to config
    for prefix in sorted(fsm_prefixes):
        p = prefix.lower()
        has_fifo = any(p in fp.lower() for fp, _ in fifos)
        if not has_fifo and config_regs:
            edges.append(f'    CONFIG --> FSM_{prefix}')

    # Sub-module instances
    for mod_type, inst_name in submodules:
        nid = f'SUB_{inst_name}'
        add_node(nid, f'{inst_name}\\n({mod_type})')
        edges.append(f'    REG_DECODE --> {nid}')

    # I/O ports — smart connection based on name matching
    for inp in inputs:
        nid = f'IN_{inp}'
        add_node(nid, inp, 'round')
        inp_lower = inp.lower()

        # Match to FSM by prefix (e.g. uart_rx -> RX FSM, spi_miso -> RX FSM)
        connected = False
        for prefix in fsm_prefixes:
            pl = prefix.lower()
            if pl in inp_lower or (pl == 'rx' and ('miso' in inp_lower or 'rx' in inp_lower)):
                edges.append(f'    {nid} --> FSM_{prefix}')
                connected = True
                break

        # CTS-like flow control inputs connect to TX FSM
        if not connected and ('cts' in inp_lower):
            for prefix in fsm_prefixes:
                if prefix.lower() == 'tx':
                    edges.append(f'    {nid} --> FSM_{prefix}')
                    connected = True
                    break

        if not connected:
            edges.append(f'    {nid} --> REG_DECODE')

    for out in outputs:
        nid = f'OUT_{out}'
        add_node(nid, out, 'round')
        out_lower = out.lower()

        connected = False
        # TX pin / MOSI / SCLK -> from TX FSM
        for prefix in fsm_prefixes:
            pl = prefix.lower()
            if pl in out_lower or (pl == 'tx' and ('mosi' in out_lower or 'sclk' in out_lower or 'tx' in out_lower)):
                edges.append(f'    FSM_{prefix} --> {nid}')
                connected = True
                break

        if not connected:
            # RTS connects from RX FIFO status
            if 'rts' in out_lower:
                for fp, _ in fifos:
                    if 'rx' in fp.lower():
                        edges.append(f'    FIFO_{fp} --> {nid}')
                        connected = True
                        break
            # IRQ comes from interrupt logic (config + fifo levels)
            elif 'irq' in out_lower:
                add_node('IRQ_LOGIC', 'IRQ Logic\\n(mask & status)')
                if config_regs:
                    edges.append(f'    CONFIG --> IRQ_LOGIC')
                for fp, _ in fifos:
                    edges.append(f'    FIFO_{fp} -.-> IRQ_LOGIC')
                edges.append(f'    IRQ_LOGIC --> {nid}')
                connected = True
            # DREQ (DMA request) comes from FIFO status
            elif 'dreq' in out_lower:
                for fp, _ in fifos:
                    if fp.lower() in out_lower:
                        edges.append(f'    FIFO_{fp} --> {nid}')
                        connected = True
                        break

        if not connected:
            edges.append(f'    REG_DECODE --> {nid}')

    # Config feeds all FSMs (baud rate, enable, etc.)
    if config_regs:
        for prefix in fsm_prefixes:
            edges.append(f'    CONFIG -.-> FSM_{prefix}')

    # Read path
    add_node('READ_MUX', 'Read Mux\\n(hrdata)')
    edges.append('    READ_MUX --> AHB')
    if config_regs:
        edges.append('    CONFIG --> READ_MUX')
    for prefix, _ in fifos:
        # Only RX-like FIFOs feed the read mux (CPU reads from them)
        if 'rx' in prefix.lower():
            edges.append(f'    FIFO_{prefix} --> READ_MUX')

    # Build final mermaid string
    mermaid = 'graph TD\n'
    mermaid += '\n'.join(nodes) + '\n'
    mermaid += '\n'.join(edges) + '\n'

    return mermaid


# ---------------------------------------------------------------------------
# SoC-level data flow diagram (parsed from rxpsm32.sv)

def build_soc_diagram():
    """Generate mermaid diagram of the SoC-level data flow from rxpsm32.sv."""
    soc_path = RTL / 'rxpsm32.sv'
    if not soc_path.exists():
        return None

    source = open(soc_path).read()
    lines = source.split('\n')

    # Extract top-level I/O ports (skip clk/rst)
    io_ports = {}  # name -> 'input'|'output'
    in_module = False
    for line in lines:
        stripped = line.strip()
        if re.match(r'module\s+rxpsm32', stripped):
            in_module = True
        if in_module:
            if re.match(r'(input|output)\s+wire\s+.*\b(clk|rst_n)\b', stripped):
                continue
            m = re.match(r'(input|output)\s+wire\s+(?:\[[\d:]+\]\s+)?(\w+)', stripped)
            if m:
                io_ports[m.group(2)] = m.group(1)
            if stripped == ');':
                break

    # Extract crossbar address map (packed MSB-first, so reverse for natural order)
    slaves = []
    in_addr_map = False
    for line in lines:
        if 'XBAR_D_ADDR_MAP' in line and 'localparam' in line:
            in_addr_map = True
            continue
        if in_addr_map:
            m = re.match(r"\s*32'h([\w_]+)\s*,?\s*//\s*\d+:\s*(\w+)", line)
            if m:
                addr = '0x' + m.group(1).replace('_', '')
                name = m.group(2)
                slaves.append((name, addr))
            if '};' in line:
                break
    slaves.reverse()  # natural order: SRAM first

    # Map peripherals to their external pins
    peripheral_pins = {
        'GPIO':     ['gpio_in', 'gpio_out', 'gpio_oe'],
        'PIO0':     ['pio_gpio_in', 'pio_gpio_out', 'pio_gpio_oe', 'pio_irq[3:0]'],
        'PIO1':     ['pio_gpio_in', 'pio_gpio_out', 'pio_gpio_oe', 'pio_irq[7:4]'],
        'UART0':    ['uart_tx', 'uart_rx'],
        'SPI0':     ['spi0_sclk', 'spi0_mosi', 'spi0_miso', 'spi0_cs_n'],
        'WATCHDOG': ['wdog_reset'],
        'RESET':    ['periph_rst_n'],
    }

    # Build mermaid
    m = 'graph TD\n'

    # JTAG + Debug
    m += '    JTAG(["JTAG\\ntck/tms/tdi/tdo"]) --> DTM["JTAG DTM"] --> DM["Debug Module"]\n'
    m += '    DM --> CPU\n'

    # CPU
    m += '    CPU{{"CPU0\\nHazard3 RV32IMC"}}\n'

    # SRAM — shared by I-port and D-port
    m += '    SRAM[("SRAM\\n64KB")]\n'

    # Instruction port
    m += '    CPU -- "I-port" --> I_DEC["i_decoder\\n1:2"]\n'
    m += '    I_DEC -- "I-port" --> SRAM\n'
    m += '    I_DEC --> XIP["XIP Cache\\n+ SPI Flash"]\n'
    m += '    XIP --> SPI_FLASH(["spi_cs_n / spi_sck\\nspi_mosi / spi_miso"])\n'

    # Data port crossbar
    m += '    CPU -- "D-port" --> XBAR["Crossbar\\n1x10"]\n'
    m += '    XBAR -- "D-port" --> SRAM\n'

    # Crossbar slaves (skip SRAM — handled above)
    for name, addr in slaves:
        if name == 'SRAM':
            continue
        nid = f'S_{name}'
        label = f'{name}\\n{addr}'
        m += f'    XBAR --> {nid}["{label}"]\n'

        # External pins
        pins = peripheral_pins.get(name, [])
        if pins:
            pin_label = '\\n'.join(pins[:3])
            if len(pins) > 3:
                pin_label += f'\\n+{len(pins)-3} more'
            pin_nid = f'PIN_{name}'
            m += f'    {nid} --> {pin_nid}(["{pin_label}"])\n'

    # IRQ connections (dashed)
    m += '    S_UART0 -.-> |irq| CPU\n'
    m += '    S_SPI0 -.-> |irq| CPU\n'
    m += '    S_TIMER -.-> |timer_irq| CPU\n'

    # Reset path
    m += '    S_WATCHDOG -.-> |wdog_reset| S_RESET\n'
    m += '    S_RESET -.-> |periph_rst_n| CPU\n'

    return m


# ---------------------------------------------------------------------------
# Module section builder

def build_module_section(module, sv_rel_path, run_yosys=True):
    """Build HTML fragment for one module. Returns (html_str, test_count) or (None, 0)."""
    sv_path  = RTL / sv_rel_path
    tb_path  = TB / f'test_{module}.py'
    res_path = TB / 'results.xml'

    if not sv_path.exists():
        print(f'  Skipping {module}: {sv_path} not found')
        return None, 0

    print(f'  Parsing {sv_path.name}...')
    sv = parse_sv(sv_path)
    tests = parse_tests(tb_path, res_path)

    key_signals = []
    if run_yosys:
        key_signals = yosys_key_signals(sv_path, module)

    desc = get_first_header_line(sv_path)

    # Block diagram
    try:
        mermaid_src = extract_block_diagram(sv_path)
        diagram_html = (f'<div class="mermaid">\n{mermaid_src}</div>')
    except Exception as e:
        print(f'  Block diagram skipped: {e}')
        diagram_html = '<p style="color:#666"><em>Block diagram generation failed.</em></p>'

    # Key signals
    if key_signals:
        pills = ''.join(
            f'<span class="key-pill"><code>{name}</code>'
            f'<span class="fanout">({fanout})</span></span>'
            for name, fanout in key_signals
        )
        key_html = f'<p style="color:#666;margin-bottom:10px">Ranked by fanout.</p>{pills}'
    else:
        key_html = '<p style="color:#666"><em>Yosys not available — fanout analysis skipped.</em></p>'

    # Registers
    reg_html = tbl(
        ['Name', 'Description'],
        [(f'<code>{name}</code>', comment or '<em>-</em>') for name, comment in sv['regs']]
    ) if sv['regs'] else '<p style="color:#666"><em>No register declarations found.</em></p>'

    # Address decoder
    addr_html = tbl(
        ['Register', 'Byte offset', 'Word addr', 'Description'],
        [(f'<code>{name}</code>', f'<code>{byte_off}</code>',
          f'<code>{word}</code>', comment or '<em>-</em>')
         for name, word, byte_off, comment in sv['addr_params']]
    ) if sv['addr_params'] else '<p style="color:#666"><em>No address parameters found.</em></p>'

    # FSM states
    fsm_html = ''
    for prefix, states in sv['fsm_groups'].items():
        fsm_html += f'<h4>{prefix} states</h4>'
        fsm_html += tbl(
            ['Name', 'Value', 'Description'],
            [(f'<code>{n}</code>', f'<code>{v}</code>', c or '<em>-</em>')
             for n, v, c in states]
        )
    if sv['other_params']:
        fsm_html += '<h4>Constants</h4>'
        fsm_html += tbl(
            ['Name', 'Value', 'Description'],
            [(f'<code>{n}</code>', f'<code>{v}</code>', c or '<em>-</em>')
             for n, v, c in sv['other_params']]
        )
    if not fsm_html:
        fsm_html = '<p style="color:#666"><em>No FSM states or constants found.</em></p>'

    # Combinational logic
    assign_html = tbl(
        ['Signal', 'Expression', 'Description'],
        [(f'<code>{name}</code>',
          f'<code title="{escape(expr)}">{escape(expr[:70])}{"..." if len(expr) > 70 else ""}</code>',
          comment or '<em>-</em>')
         for name, expr, comment in sv['assigns']]
    ) if sv['assigns'] else '<p style="color:#666"><em>No assign statements found.</em></p>'

    # Always blocks
    always_html = ''.join(
        f'<div class="always"><code>{escape(sens)}</code>'
        f'{"<p>" + escape(c) + "</p>" if c else ""}</div>'
        for sens, c in sv['always_blocks']
    ) if sv['always_blocks'] else '<p style="color:#666"><em>No always blocks found.</em></p>'

    # Tests
    total   = len(tests)
    if total > 0:
        passed  = sum(1 for *_, st in tests if st == 'pass')
        failed  = sum(1 for *_, st in tests if st == 'fail')
        skipped = sum(1 for *_, st in tests if st == 'skip')
        unknown = sum(1 for *_, st in tests if st == 'unknown')

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
                f'<p>{escape(purpose)}</p>{cond}'
                f'</div>'
            )
        test_html = summary + test_items
    else:
        test_html = '<p style="color:#666"><em>No testbench found.</em></p>'

    # Header block
    header_html = ''
    if sv['header']:
        header_html = '<pre style="color:#888;font-size:0.9em;line-height:1.5;margin:8px 0;white-space:pre-wrap">'
        header_html += escape('\n'.join(sv['header']))
        header_html += '</pre>'

    test_label = f'Tests ({total})' if total > 0 else 'Tests'

    html = f'''<div class="module-section" id="{module}">
<h1>{module}.sv</h1>
<p style="color:#555">{escape(desc)}</p>

{det("Block diagram", diagram_html)}
{det("Module header", header_html) if header_html else ""}
{det("Key signals", key_html)}
{det("Registers", reg_html, open_=True)}
{det("Address decoder", addr_html)}
{det("FSM states &amp; constants", fsm_html)}
{det("Combinational logic", assign_html)}
{det("Always blocks", always_html)}
{det(test_label, test_html)}
</div>
'''
    return html, total


# ---------------------------------------------------------------------------
# Main

def main():
    import sys

    DOCS.mkdir(exist_ok=True)

    # Check yosys
    try:
        subprocess.run(['yosys', '--version'], capture_output=True, timeout=5)
        has_yosys = True
    except Exception:
        has_yosys = False
        print('Yosys not found — skipping fanout analysis')

    # Build SoC-level overview diagram
    print('[overall]')
    overview_html = '''<div class="module-section" id="overall">
<h1>SoC Overview</h1>
<p style="color:#555">RP2350 reference architecture.</p>
<img src="rp2350/rp2350-architecture.jpg" style="max-width:100%;border-radius:4px;margin:8px 0" alt="RP2350 Architecture">
</div>
'''

    # Build sidebar
    sidebar_links = '<h2>SoC</h2>\n<a href="#overall">Overall</a>\n'
    for group_name, modules in GROUPS:
        sidebar_links += f'<h2>{group_name}</h2>\n'
        for name, sv_rel in modules:
            sv_path = RTL / sv_rel
            if sv_path.exists():
                sidebar_links += f'<a href="#{name}">{name}</a>\n'
            else:
                sidebar_links += f'<a href="#{name}" style="opacity:0.35">{name}</a>\n'

    sidebar = f'''<nav class="sidebar">
<div class="title">rxpsm32</div>
{sidebar_links}
</nav>'''

    # Build all module sections
    sections = overview_html
    for group_name, modules in GROUPS:
        for name, sv_rel in modules:
            print(f'[{name}]')
            html, tc = build_module_section(name, sv_rel, run_yosys=has_yosys)
            if html:
                sections += html

    out_path = DOCS / 'rxpsm32.html'
    full_html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>rxpsm32 — SoC documentation</title>
<style>{CSS}</style>
<script src="mermaid.min.js"></script>
<script>mermaid.initialize({{startOnLoad:true,theme:'dark',themeVariables:{{primaryColor:'#2a3a2a',primaryTextColor:'#d4d4d4',lineColor:'#4ec9b0',edgeLabelBackground:'#252526'}}}});</script>
</head>
<body>
{sidebar}
<div class="main">
{sections}
</div>
{SCRIPT}
</body>
</html>'''

    out_path.write_text(full_html)
    print(f'\nDone -> {out_path}')


if __name__ == '__main__':
    main()
