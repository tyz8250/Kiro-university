#!/usr/bin/env python3
"""Generate editable SVG scene artwork for the Network Fault Observation demo."""

from pathlib import Path

OUT = Path(__file__).resolve().parent / "assets"
OUT.mkdir(parents=True, exist_ok=True)

BG = "#08111f"
PANEL = "#10233b"
PANEL2 = "#142c49"
INK = "#f5f7fb"
MUTED = "#9fb2c8"
CYAN = "#52d3ff"
GREEN = "#55e6a5"
AMBER = "#ffc857"
RED = "#ff6b7a"


def esc(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def text(x, y, value, size=30, color=INK, weight=500, anchor="start", family="Arial"):
    return f'<text x="{x}" y="{y}" fill="{color}" font-family="{family}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}">{esc(value)}</text>'


def multiline(x, y, lines, size=30, color=INK, weight=500, gap=1.28, anchor="start", family="Arial"):
    tspans = []
    for i, line in enumerate(lines):
        dy = 0 if i == 0 else size * gap
        tspans.append(f'<tspan x="{x}" dy="{dy}">{esc(line)}</tspan>')
    return f'<text x="{x}" y="{y}" fill="{color}" font-family="{family}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}">' + "".join(tspans) + "</text>"


def rect(x, y, w, h, fill=PANEL, stroke="none", sw=0, rx=18, opacity=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}"/>'


def line(x1, y1, x2, y2, color=CYAN, sw=4, dash=""):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{sw}" stroke-linecap="round"{d}/>'


def pill(x, y, value, color=CYAN, w=None):
    width = w or max(118, len(value) * 11 + 34)
    return rect(x, y, width, 36, color, "none", 0, 18, .14) + text(x + width / 2, y + 25, value, 16, color, 700, "middle")


def node(x, y, w, title, sub="", color=CYAN):
    parts = [rect(x, y, w, 92, PANEL2, color, 2, 16), text(x + w/2, y + 40, title, 23, INK, 700, "middle")]
    if sub:
        parts.append(text(x + w/2, y + 69, sub, 15, MUTED, 500, "middle"))
    return "".join(parts)


def arrow(x1, y, x2, color=CYAN, sw=4, broken=False):
    parts = [line(x1, y, x2 - 12, y, color, sw, "10 8" if broken else "")]
    parts.append(f'<path d="M {x2-18} {y-8} L {x2} {y} L {x2-18} {y+8}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>')
    return "".join(parts)


def base(kicker, title, subtitle=""):
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="1280" viewBox="0 0 1280 1280">',
        '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#08111f"/><stop offset="1" stop-color="#102742"/></linearGradient><filter id="glow"><feGaussianBlur stdDeviation="14"/></filter></defs>',
        f'<rect width="1280" height="1280" fill="{BG}"/>',
        '<g transform="translate(0 280)">',
        '<rect width="1280" height="720" fill="url(#bg)"/>',
        '<circle cx="1135" cy="20" r="190" fill="#1b5f83" opacity=".18" filter="url(#glow)"/>',
        pill(64, 42, kicker, CYAN),
        text(64, 120, title, 46, INK, 750),
        text(64, 158, subtitle, 22, MUTED, 500) if subtitle else "",
        text(1216, 64, "NETWORK FAULT OBSERVATION", 14, MUTED, 700, "end"),
    ]


def finish(parts, number):
    parts += [text(64, 686, f"0{number}  /  09", 14, MUTED, 700), text(1216, 686, "Kiro University Challenge", 14, MUTED, 500, "end"), '</g></svg>']
    (OUT / f"scene-{number:02d}.svg").write_text("".join(parts), encoding="utf-8")


# 01 — README title and architecture.
p = base("README.md", "Network Fault Observation", "AWS / Docker / Go network fault experiment")
p += [
    rect(64, 196, 1152, 398, PANEL, "#244766", 2, 24),
    text(96, 242, "# Network Fault Observation", 26, INK, 700, family="Menlo"),
    text(96, 278, "Where does communication stop during a network fault?", 20, MUTED, 500),
]
labels = [("Mac", "Observer"), ("Internet", "public path"), ("AWS VPC", "route table"), ("EC2", "host"), ("Docker", "container"), ("Go Server", "HTTP :8080")]
x = 96
for i, (a, b) in enumerate(labels):
    p.append(node(x, 340, 150, a, b, CYAN if i < 3 else GREEN))
    if i < len(labels) - 1:
        p.append(arrow(x + 150, 386, x + 178, CYAN if i < 2 else GREEN, 3))
    x += 190
p += [pill(96, 486, "Experiment 1", AMBER, 148), text(264, 512, "One boundary changed. Every boundary observed.", 22, INK, 600)]
finish(p, 1)

# 02 — request path and method.
p = base("REQUEST PATH", "Observe every boundary", "A failed request is only the first symptom")
nodes = [(72, "Mac", "curl"), (268, "Internet", "network"), (464, "AWS VPC", "route"), (660, "EC2", "NIC + host"), (856, "Docker", "runtime"), (1052, "Go", "/health")]
for i, (x, a, b) in enumerate(nodes):
    p.append(node(x, 220, 156, a, b, CYAN if i < 3 else GREEN))
    if i < 5:
        p.append(arrow(x + 156, 266, x + 190, CYAN, 3))
p += [rect(64, 360, 1152, 190, PANEL, "#244766", 2, 22), text(96, 405, "EXPERIMENT LOOP", 16, CYAN, 700)]
steps = ["Hypothesis", "Break", "Observe", "Explain", "Restore"]
sx = 108
for i, s in enumerate(steps):
    p.append(pill(sx, 444, s, [CYAN, RED, AMBER, GREEN, CYAN][i], 168))
    if i < 4:
        p.append(arrow(sx + 168, 462, sx + 202, MUTED, 2))
    sx += 220
p.append(text(640, 610, "Change one thing. Compare all observation points.", 28, INK, 700, "middle"))
finish(p, 2)

# 03 — baseline.
p = base("BASELINE", "5 / 5 observation points healthy", "Known-good evidence before fault injection")
p += [rect(64, 196, 1152, 390, PANEL, "#244766", 2, 24), text(1000, 310, "5/5", 112, GREEN, 800, "middle"), text(1000, 354, "healthy", 24, MUTED, 600, "middle")]
checks = [("Mac curl", "HTTP 200"), ("EC2 NIC", "SYN / SYN-ACK / ACK"), ("Docker", "go-server Up"), ("Host curl", "HTTP 200"), ("Go logs", "Trace ID found")]
for i, (a, b) in enumerate(checks):
    y = 238 + i * 66
    p += [rect(96, y, 680, 50, PANEL2, "none", 0, 12), rect(112, y + 13, 24, 24, GREEN, "none", 0, 12), text(124, y + 31, "OK", 10, BG, 800, "middle"), text(156, y + 31, a, 21, INK, 700), text(744, y + 31, b, 18, GREEN, 600, "end")]
p.append(text(96, 632, "Baseline creates the comparison that makes fault evidence meaningful.", 24, INK, 600))
finish(p, 3)

# 04 — fault injection.
p = base("EXPERIMENT 1", "Remove only the default route", "A controlled fault at the AWS network boundary")
p += [rect(64, 200, 1152, 344, PANEL, "#244766", 2, 24), node(110, 300, 260, "Public Route Table", "AWS VPC", AMBER), node(860, 300, 260, "Internet Gateway", "IGW", CYAN), arrow(370, 346, 860, RED, 8, True), line(570, 278, 690, 414, RED, 12), line(690, 278, 570, 414, RED, 12), text(640, 254, "0.0.0.0/0  ->  Internet Gateway", 32, INK, 700, "middle", "Menlo"), pill(494, 452, "REMOVED", RED, 292), text(640, 596, "Guardrail: no other infrastructure resource changed.", 24, GREEN, 650, "middle")]
finish(p, 4)

# 05 — packet evidence.
p = base("PACKET EVIDENCE", "The handshake stopped after SYN-ACK", "External curl: timeout / HTTP 000 / exit 28")
p += [rect(64, 196, 1152, 396, PANEL, "#244766", 2, 24)]
rows = [(252, "CLIENT", "SYN", "EC2 NIC", "5", GREEN, False), (352, "EC2 NIC", "SYN-ACK", "CLIENT", "10", AMBER, True), (452, "CLIENT", "FINAL ACK", "EC2 NIC", "0", RED, True)]
for y, left, packet, right, count, color, broken in rows:
    p += [node(100, y, 180, left, "", color), node(1000, y, 180, right, "", color), arrow(310, y + 46, 968, color, 5, broken), rect(524, y + 18, 232, 56, BG, color, 2, 16), text(640, y + 43, packet, 16, color, 700, "middle"), text(640, y + 67, f"count: {count}", 18, INK, 700, "middle")]
p += [pill(82, 612, "Hypothesis update", AMBER, 210), text(316, 637, "The original hypothesis was partially wrong.", 26, INK, 700)]
finish(p, 5)

# 06 — internal health and explanation.
p = base("BOUNDARY CHECK", "Docker and Go remained healthy", "The failed boundary was the external return path")
p += [rect(64, 196, 546, 260, PANEL, GREEN, 2, 24), rect(670, 196, 546, 260, PANEL, GREEN, 2, 24), text(337, 274, "22 / 22", 76, GREEN, 800, "middle"), text(337, 322, "HTTP 200", 30, INK, 700, "middle"), text(337, 366, "EC2 internal health", 20, MUTED, 600, "middle"), text(943, 274, "22 / 22", 76, GREEN, 800, "middle"), text(943, 322, "Up", 30, INK, 700, "middle"), text(943, 366, "Docker go-server", 20, MUTED, 600, "middle"), rect(64, 492, 1152, 120, "#2d2133", RED, 2, 20), text(96, 536, "INTERPRETATION", 15, RED, 800), multiline(96, 574, ["The SYN reached EC2. EC2 sent SYN-ACK.", "The final ACK never returned. The TCP handshake did not complete."], 24, INK, 650, 1.35)]
finish(p, 6)

# 07 — restore.
p = base("RESTORE", "Return to the known-good state", "Recovery was verified at both service and infrastructure layers")
p += [rect(64, 208, 548, 296, PANEL, GREEN, 2, 24), rect(668, 208, 548, 296, PANEL, CYAN, 2, 24), text(338, 292, "HTTP", 22, MUTED, 700, "middle"), text(338, 380, "200", 96, GREEN, 800, "middle"), text(338, 436, "after restore", 24, INK, 650, "middle"), text(942, 292, "TERRAFORM", 22, MUTED, 700, "middle"), text(942, 368, "No changes", 48, CYAN, 800, "middle"), text(942, 426, "zero infrastructure drift", 24, INK, 650, "middle"), pill(480, 548, "RESTORED + VERIFIED", GREEN, 320), text(640, 632, "End state matched the baseline.", 26, INK, 700, "middle")]
finish(p, 7)

# 08 — Kiro tree.
p = base("KIRO WORKFLOW", ".kiro makes the experiment reproducible", "Design guidance, safety boundaries, investigation, and validation")
p += [rect(64, 190, 430, 438, PANEL, "#244766", 2, 24), text(94, 232, ".kiro/", 25, CYAN, 800, family="Menlo")]
tree = [("specs/", "requirements + design + tasks"), ("steering/", "experiment context"), ("powers/", "failure-investigation"), ("agents/", "incident-investigator"), ("hooks/", "AgentStop validation"), ("settings/", "AWS Docs MCP")]
for i, (a, b) in enumerate(tree):
    y = 274 + i * 54
    p += [text(112, y, "|--", 18, MUTED, 500, family="Menlo"), text(160, y, a, 21, [CYAN, GREEN, AMBER, CYAN, RED, GREEN][i], 750, family="Menlo"), text(286, y, b, 14, MUTED, 500)]
p += [rect(534, 190, 682, 438, PANEL, "#244766", 2, 24)]
features = [("Kiro Specs", CYAN), ("Steering", GREEN), ("Property-Based Testing", AMBER), ("Power + AWS Docs MCP", CYAN), ("Read-only Custom Agent", GREEN), ("AgentStop Hook", RED)]
for i, (label, color) in enumerate(features):
    col, row = i % 2, i // 2
    x, y = 570 + col * 310, 244 + row * 104
    p += [rect(x, y, 274, 76, PANEL2, color, 2, 16), rect(x + 18, y + 21, 34, 34, color, "none", 0, 17, .25), text(x + 35, y + 44, str(i + 1), 15, color, 800, "middle"), text(x + 64, y + 46, label, 18, INK, 700)]
p.append(text(876, 586, "Observe first. Validate automatically. Restore deliberately.", 20, MUTED, 650, "middle"))
finish(p, 8)

# 09 — final message.
p = base("TAKEAWAY", "A failed curl does not necessarily", "")
p += [text(64, 190, "mean the application failed.", 52, INK, 780), rect(64, 242, 1152, 6, CYAN, "none", 0, 3), text(640, 378, "Observe each boundary separately.", 48, GREEN, 780, "middle"), rect(234, 428, 812, 110, PANEL, "#244766", 2, 22), text(640, 474, "NETWORK PATH  !=  HOST  !=  CONTAINER  !=  APP", 22, CYAN, 750, "middle", "Menlo"), text(640, 514, "Evidence tells you where the failure actually is.", 20, MUTED, 600, "middle"), pill(482, 590, "Network Fault Observation", CYAN, 316)]
finish(p, 9)

print(f"Generated 9 SVG scenes in {OUT}")
