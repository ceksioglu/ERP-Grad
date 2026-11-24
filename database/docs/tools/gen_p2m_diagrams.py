#!/usr/bin/env python3
"""Draw the P2M diagrams as standalone SVG files (no Graphviz needed).

    python3 database/docs/tools/gen_p2m_diagrams.py

Writes, next to the other docs:
    p2m-er-diagram.svg      physical model: tables, PK/FK columns, FK relationships
    p2m-logical-model.svg   logical model: entities, identifiers, crow's-foot cardinalities
    p2m-process-flow.svg    Plan to Manufacture process across roles and the shared stock ledger

Layout is explicit (coordinates below) so the drawings stay stable between edits.
Colours follow o2c-er-diagram.svg.
"""
import html
import math
import pathlib

DOCS = pathlib.Path(__file__).resolve().parent.parent
FONT = "Helvetica,Arial,'Liberation Sans',sans-serif"
INK = "#16263a"
MUTED = "#536277"
EDGE = "#546b81"
EDGE_LABEL = "#30485f"

# cluster key: (header colour, background, title)
THEME = {
    "public":      ("#245a78", "#eaf4fb", "Shared master data"),
    "sales":       ("#5b4b95", "#f0ecfa", "Order to cash (O2C)"),
    "inventory":   ("#1c6b5c", "#e7f6f0", "Shared inventory ledger"),
    "planning":    ("#2f5d8a", "#e9f0f8", "Planning"),
    "production":  ("#8b3a2e", "#fbeeec", "Production"),
    "output":      ("#8b3a2e", "#fbeeec", "Production output"),
    "engineering": ("#8a5a12", "#fbf3e4", "Engineering"),
}

NARROW = set("iljtfr.,:;'|!I()[] ")
WIDE = set("mwMW@%")


def tw(text, size, bold=False):
    """Approximate rendered width of Helvetica text."""
    units = 0.0
    for ch in text:
        if ch in NARROW:
            units += 0.30
        elif ch in WIDE:
            units += 0.85
        elif ch.isupper():
            units += 0.68
        else:
            units += 0.56
    return units * size * (1.08 if bold else 1.0)


def esc(text):
    return html.escape(str(text), quote=True)


class Svg:
    def __init__(self, width, height, title):
        self.width, self.height, self.parts = width, height, []
        self.add(f'<rect x="0" y="0" width="{width}" height="{height}" fill="#ffffff"/>')
        self.text(width / 2, 44, title, size=26, anchor="middle", fill=INK)

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=12, anchor="start", fill=INK, bold=False, italic=False, halo=False):
        attrs = f'font-family="{FONT}" font-size="{size}" fill="{fill}" text-anchor="{anchor}"'
        if bold:
            attrs += ' font-weight="bold"'
        if italic:
            attrs += ' font-style="italic"'
        if halo:
            attrs += ' stroke="#ffffff" stroke-width="4" stroke-linejoin="round" paint-order="stroke"'
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" {attrs}>{esc(s)}</text>')

    def save(self, name):
        body = "\n".join(self.parts)
        svg = (f'<?xml version="1.0" encoding="UTF-8"?>\n'
               f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
               f'viewBox="0 0 {self.width} {self.height}">\n{body}\n</svg>\n')
        (DOCS / name).write_text(svg, encoding="utf-8")
        print(f"wrote {DOCS / name}")


# ---------------------------------------------------------------- boxes and edges

class Box:
    HEADER, ROW, PAD = 28, 20, 8

    def __init__(self, x, y, title, rows, cluster, width=None, tag_col=26):
        self.x, self.y, self.title, self.rows, self.cluster = x, y, title, rows, cluster
        self.tag_col = tag_col
        content = [tw(title, 12, bold=True)]
        for tag, name, note in rows:
            w = tag_col + tw(name, 12)
            if note:
                w += 6 + tw(note, 10)
            content.append(w)
        self.w = width or math.ceil(max(content) + 2 * self.PAD + 4)
        self.h = self.HEADER + len(rows) * self.ROW + self.PAD

    def port(self, side, frac=0.5):
        if side == "L":
            return (self.x, self.y + self.h * frac)
        if side == "R":
            return (self.x + self.w, self.y + self.h * frac)
        if side == "T":
            return (self.x + self.w * frac, self.y)
        return (self.x + self.w * frac, self.y + self.h)

    def draw(self, svg):
        colour = THEME[self.cluster][0]
        x, y, w, h = self.x, self.y, self.w, self.h
        svg.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#ffffff" stroke="{colour}" stroke-width="1.2"/>')
        svg.add(f'<path d="M{x},{y + self.HEADER} V{y + 3} a3,3 0 0 1 3,-3 H{x + w - 3} a3,3 0 0 1 3,3 V{y + self.HEADER} Z" fill="{colour}"/>')
        svg.text(x + self.PAD, y + 19, self.title, size=12, fill="#ffffff", bold=True)
        for i, (tag, name, note) in enumerate(self.rows):
            base = y + self.HEADER + (i + 1) * self.ROW - 5
            if tag:
                svg.text(x + self.PAD, base - 1, tag, size=9, fill=MUTED)
            svg.text(x + self.PAD + self.tag_col, base, name, size=12)
            if note:
                svg.text(x + self.PAD + self.tag_col + tw(name, 12) + 6, base, note, size=10, fill=MUTED, italic=True)


def cluster(svg, key, boxes, pad=18, title=None, extra=(0, 0, 0, 0)):
    header, bg, default_title = THEME[key]
    x0 = min(b.x for b in boxes) - pad - extra[0]
    y0 = min(b.y for b in boxes) - pad - 22 - extra[1]
    x1 = max(b.x + b.w for b in boxes) + pad + extra[2]
    y1 = max(b.y + b.h for b in boxes) + pad + extra[3]
    svg.add(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="6" fill="{bg}" stroke="{bg}"/>')
    svg.text((x0 + x1) / 2, y0 + 19, title or default_title, size=15, anchor="middle", fill=header)


DIRS = {"L": (-1, 0), "R": (1, 0), "T": (0, -1), "B": (0, 1)}


def route(p1, s1, p2, s2, mid=None):
    (x1, y1), (x2, y2) = p1, p2
    h1, h2 = s1 in "LR", s2 in "LR"
    if h1 and h2:
        mx = mid if mid is not None else (x1 + x2) / 2
        return [p1, (mx, y1), (mx, y2), p2]
    if not h1 and not h2:
        my = mid if mid is not None else (y1 + y2) / 2
        return [p1, (x1, my), (x2, my), p2]
    if h1:
        return [p1, (x2, y1), p2]
    return [p1, (x1, y2), p2]


def polyline(svg, pts, dashed=False, colour=EDGE, width=1.3):
    clean = [pts[0]]
    for p in pts[1:]:
        if abs(p[0] - clean[-1][0]) > 0.01 or abs(p[1] - clean[-1][1]) > 0.01:
            clean.append(p)
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in clean)
    dash = ' stroke-dasharray="6 4"' if dashed else ""
    svg.add(f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{width}" stroke-linejoin="round"{dash}/>')
    return clean


def arrowhead(svg, tip, direction, colour=EDGE):
    dx, dy = direction            # direction the arrow travels
    nx, ny = -dy, dx
    bx, by = tip[0] - dx * 9, tip[1] - dy * 9
    pts = f"{tip[0]:.1f},{tip[1]:.1f} {bx + nx * 4:.1f},{by + ny * 4:.1f} {bx - nx * 4:.1f},{by - ny * 4:.1f}"
    svg.add(f'<polygon points="{pts}" fill="{colour}"/>')


def end_label(svg, point, side, text):
    dx, dy = DIRS[side]
    if dx:   # horizontal leg: put the label above the line
        x, y = point[0] + dx * 14, point[1] - 5
    else:    # vertical leg: put the label to the right of the line
        x, y = point[0] + 13, point[1] + dy * 16 + 3
    svg.text(x, y, text, size=10, anchor="middle", fill=EDGE_LABEL, halo=True)


def resolve(boxes, e):
    """Return (p1, p2, polyline points) for an edge spec."""
    p1 = boxes[e["src"]].port(e["ss"], e["sf"])
    dst = boxes[e["dst"]]
    if e["df"] == "align":      # straight vertical drop into the target
        p2 = (p1[0], dst.y if e["ds"] == "T" else dst.y + dst.h)
    else:
        p2 = dst.port(e["ds"], e["df"])
    if e.get("via"):
        pick = lambda v, i: p1[i] if v == "p1" else p2[i] if v == "p2" else v
        pts = [p1] + [(pick(x, 0), pick(y, 1)) for x, y in e["via"]] + [p2]
    else:
        pts = route(p1, e["ss"], p2, e["ds"], e.get("mid"))
    return p1, p2, pts


def fk_edge(svg, boxes, e):
    p1, p2, pts = resolve(boxes, e)
    pts = polyline(svg, pts)
    last = pts[-2]
    length = math.hypot(p2[0] - last[0], p2[1] - last[1]) or 1
    arrowhead(svg, p2, ((p2[0] - last[0]) / length, (p2[1] - last[1]) / length))
    end_label(svg, p1, e["ss"], e["card"][0])
    end_label(svg, p2, e["ds"], e["card"][1])


def crow_marks(svg, point, side, card):
    """Crow's-foot notation drawn at a box edge; side is the box side the line leaves from."""
    dx, dy = DIRS[side]
    nx, ny = -dy, dx
    px, py = point

    def at(dist, off=0):
        return (px + dx * dist + nx * off, py + dy * dist + ny * off)

    def bar(dist):
        a, b = at(dist, -6), at(dist, 6)
        svg.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{INK}" stroke-width="1.4"/>')

    def circle(dist):
        c = at(dist)
        svg.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4" fill="#ffffff" stroke="{INK}" stroke-width="1.4"/>')

    many = card.endswith("*")
    if many:
        tip = at(13)
        for off in (-7, 0, 7):
            f = at(0, off)
            svg.add(f'<line x1="{tip[0]:.1f}" y1="{tip[1]:.1f}" x2="{f[0]:.1f}" y2="{f[1]:.1f}" stroke="{INK}" stroke-width="1.4"/>')
    else:
        bar(7)
    if card.startswith("0"):
        circle(21 if many else 17)
    else:
        bar(17 if many else 12)


def rel_edge(svg, boxes, e):
    p1, p2, pts = resolve(boxes, e)
    pts = polyline(svg, pts, colour=INK, width=1.2)
    crow_marks(svg, p1, e["ss"], e["card"][0])
    crow_marks(svg, p2, e["ds"], e["card"][1])
    segs = list(zip(pts, pts[1:]))
    a, b = segs[e["label_seg"]] if e.get("label_seg") is not None else max(segs, key=lambda s: math.dist(*s))
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    if abs(a[0] - b[0]) < 0.5:   # vertical segment: label beside it
        svg.text(mx + 6, my + 4, e["verb"], size=10, fill=EDGE_LABEL, italic=True, halo=True)
    else:
        svg.text(mx, my - 5, e["verb"], size=10, anchor="middle", fill=EDGE_LABEL, italic=True, halo=True)


# ---------------------------------------------------------------- shared layout

POS = {
    # planning column
    "sales_order_line":     (60, 110),
    "production_plan":      (60, 290),
    "production_plan_line": (60, 470),
    "material_requirement": (60, 690),
    "plan_stock_snapshot":  (60, 850),
    # production column
    "production_order_operation": (480, 110),
    "production_order":           (480, 380),
    "production_order_component": (480, 630),
    "material_issue":             (480, 810),
    # engineering columns
    "routing_operation": (900, 110),
    "work_center":       (1210, 110),
    "routing":           (900, 300),
    "bom":               (900, 450),
    "bom_line":          (900, 660),
    # output and ledger band
    "item_unit":          (60, 1060),
    "production_receipt": (330, 1060),
    "inventory_movement": (560, 1060),
    "stock_location":     (960, 1060),
}


def E(src, ss, sf, dst, ds, df, card, verb, **kw):
    return dict(src=src, ss=ss, sf=sf, dst=dst, ds=ds, df=df, card=card, verb=verb, **kw)


# One relationship list drives both the physical and the logical drawing.
# card = (parent end, child end); via = explicit bend points ("p1"/"p2" reuse an end coordinate).
EDGES = [
    E("sales_order_line", "R", 0.5, "production_plan_line", "R", 0.15, ("0..1", "0..*"), "is fulfilled by",
      via=[(320, "p1"), (320, "p2")], label_seg=1),
    E("production_plan", "B", 0.5, "production_plan_line", "T", 0.5, ("1", "1..*"), "contains"),
    E("production_plan", "L", 0.5, "plan_stock_snapshot", "L", 0.5, ("1", "0..*"), "captures",
      via=[(36, "p1"), (36, "p2")]),
    E("production_plan_line", "B", 0.5, "material_requirement", "T", 0.5, ("1", "0..*"), "explodes into"),
    E("production_plan_line", "R", 0.4, "production_order", "L", 0.3, ("1", "0..*"), "is executed by", mid=452, label_seg=0),
    E("routing", "T", 0.5, "routing_operation", "B", 0.5, ("1", "1..*"), "consists of"),
    E("work_center", "L", 0.5, "routing_operation", "R", 0.5, ("1", "0..*"), "performs"),
    E("bom", "B", 0.5, "bom_line", "T", 0.5, ("1", "1..*"), "lists"),
    E("routing_operation", "L", 0.5, "production_order_operation", "R", 0.6, ("1", "0..*"), "scheduled as", mid=860, label_seg=2),
    E("routing", "L", 0.5, "production_order", "R", 0.25, ("1", "0..*"), "guides", mid=870, label_seg=2),
    E("bom", "L", 0.5, "production_order", "R", 0.75, ("1", "0..*"), "specifies", mid=870, label_seg=2),
    E("bom_line", "L", 0.5, "production_order_component", "R", 0.6, ("1", "0..*"), "copied to", mid=860, label_seg=2),
    E("production_order", "T", 0.5, "production_order_operation", "B", 0.5, ("1", "0..*"), "runs"),
    E("production_order", "B", 0.5, "production_order_component", "T", 0.5, ("1", "0..*"), "requires"),
    E("production_order_component", "B", 0.5, "material_issue", "T", 0.5, ("1", "0..*"), "is issued by"),
    E("production_order", "L", 0.8, "production_receipt", "T", 0.5, ("1", "0..*"), "yields",
      via=[(422, "p1"), (422, 1000), ("p2", 1000)], label_seg=1),
    E("production_order", "L", 0.92, "item_unit", "T", 0.5, ("1", "0..*"), "serializes",
      via=[(400, "p1"), (400, 984), ("p2", 984)], label_seg=2),
    E("material_issue", "B", 0.5, "inventory_movement", "T", "align", ("1", "1"), "posts"),
    E("production_receipt", "R", 0.5, "inventory_movement", "L", 0.5, ("1", "1"), "posts"),
    E("stock_location", "L", 0.5, "inventory_movement", "R", 0.3, ("1", "0..*"), "holds"),
    E("stock_location", "T", 0.5, "material_issue", "R", 0.6, ("1", "0..*"), "supplies", label_seg=1),
    E("stock_location", "B", 0.5, "production_receipt", "B", 0.5, ("1", "0..*"), "receives", mid=1300),
]


def physical():
    E, F = "→", "FK"
    spec = {
        "sales_order_line": ("sales_order_line", [("PK", "order_line_id", ""), (F, "order_id", ""), (F, "item_id", E + " item")], "sales"),
        "production_plan": ("production_plan", [("PK", "production_plan_id", ""), ("UQ", "plan_no", ""), (F, "created_by", E + " employee"), (F, "approved_by", E + " employee")], "planning"),
        "production_plan_line": ("production_plan_line", [("PK", "production_plan_line_id", ""), (F, "production_plan_id", ""), (F, "item_id", E + " item"), (F, "sales_order_line_id", "+ item_id")], "planning"),
        "material_requirement": ("material_requirement", [("PK", "material_requirement_id", ""), (F, "production_plan_line_id", ""), (F, "component_item_id", E + " item")], "planning"),
        "plan_stock_snapshot": ("plan_stock_snapshot", [("PK", "production_plan_id", "FK"), ("PK", "item_id", "FK " + E + " item")], "planning"),
        "production_order_operation": ("production_order_operation", [("PK", "production_order_operation_id", ""), (F, "production_order_id", "+ routing_id"), (F, "routing_operation_id", "+ routing_id"), (F, "operator_id", E + " employee")], "production"),
        "production_order": ("production_order", [("PK", "production_order_id", ""), ("UQ", "order_no", ""), (F, "production_plan_line_id", "+ item_id"), (F, "bom_id", "+ item_id"), (F, "routing_id", "+ item_id"), (F, "item_id", E + " item"), (F, "responsible_employee_id", E + " employee")], "production"),
        "production_order_component": ("production_order_component", [("PK", "production_order_component_id", ""), (F, "production_order_id", "+ bom_id"), (F, "bom_id", "+ component_item_id"), (F, "component_item_id", "")], "production"),
        "material_issue": ("material_issue", [("PK", "material_issue_id", ""), (F, "production_order_id", "+ component_item_id"), (F, "location_id", ""), (F, "issued_by", E + " employee")], "production"),
        "routing_operation": ("routing_operation", [("PK", "routing_operation_id", ""), (F, "routing_id", ""), (F, "work_center_id", "")], "engineering"),
        "work_center": ("work_center", [("PK", "work_center_id", ""), ("UQ", "work_center_code", ""), (F, "department_id", E + " department")], "engineering"),
        "routing": ("routing", [("PK", "routing_id", ""), (F, "item_id", E + " item")], "engineering"),
        "bom": ("bom", [("PK", "bom_id", ""), (F, "item_id", E + " item"), (F, "approved_by", E + " employee")], "engineering"),
        "bom_line": ("bom_line", [("PK", "bom_line_id", ""), (F, "bom_id", ""), (F, "component_item_id", E + " item")], "engineering"),
        "item_unit": ("item_unit", [("PK", "item_unit_id", ""), (F, "production_order_id", "+ item_id"), ("UQ", "serial_number", "")], "output"),
        "production_receipt": ("production_receipt", [("PK", "production_receipt_id", ""), (F, "production_order_id", ""), (F, "location_id", ""), (F, "received_by", E + " employee")], "output"),
        "inventory_movement": ("inventory_movement", [("PK", "movement_id", ""), (F, "location_id", ""), (F, "item_id", E + " item"), (F, "order_line_id", E + " sales_order_line"), (F, "receipt_line_id", E + " goods_receipt_line"), (F, "material_issue_id", "+ item_id"), (F, "production_receipt_id", ""), (F, "recorded_by", E + " employee")], "inventory"),
        "stock_location": ("stock_location", [("PK", "location_id", ""), ("UQ", "location_code", "")], "inventory"),
    }
    boxes = {k: Box(*POS[k], *v) for k, v in spec.items()}
    svg = Svg(1460, 1340, "Furniture ERP | Plan to Manufacture (physical model)")

    groups = {}
    for k, b in boxes.items():
        groups.setdefault(b.cluster, []).append(b)
    cluster(svg, "planning", [boxes[k] for k in ("production_plan", "production_plan_line", "material_requirement", "plan_stock_snapshot")])
    cluster(svg, "sales", [boxes["sales_order_line"]])
    cluster(svg, "production", groups["production"])
    cluster(svg, "engineering", groups["engineering"])
    cluster(svg, "output", groups["output"])
    cluster(svg, "inventory", groups["inventory"])

    for edge in EDGES:
        fk_edge(svg, boxes, edge)

    for b in boxes.values():
        b.draw(svg)

    lx = 1128
    svg.text(lx, 1080, "Reading the diagram", size=12, bold=True)
    notes = [
        "Arrows point from the referenced (parent) table",
        "to the referencing table.",
        "“+ column”: composite FK that also matches that",
        "column, so an order's BOM, routing and plan line",
        "are all for the order's own item.",
        "“→ table”: FK to a shared table (public.item,",
        "public.employee, ...); those edges are not drawn.",
        "Each material issue and production receipt posts",
        "exactly one ledger movement.",
        "O2C tables: see o2c-er-diagram.svg.",
    ]
    for i, n in enumerate(notes):
        svg.text(lx, 1100 + i * 16, n, size=11, fill=MUTED)
    svg.save("p2m-er-diagram.svg")


def logical():
    def ent(name, ident, attrs, key):
        rows = [("ID", ident, "")] + [("", a, "") for a in attrs]
        return Box(*POS[key], name, rows, CLUSTER[key], tag_col=22)

    CLUSTER = {
        "sales_order_line": "sales", "production_plan": "planning", "production_plan_line": "planning",
        "material_requirement": "planning", "plan_stock_snapshot": "planning",
        "production_order_operation": "production", "production_order": "production",
        "production_order_component": "production", "material_issue": "production",
        "routing_operation": "engineering", "work_center": "engineering", "routing": "engineering",
        "bom": "engineering", "bom_line": "engineering", "item_unit": "output", "production_receipt": "output",
        "inventory_movement": "inventory", "stock_location": "inventory",
    }
    boxes = {
        "sales_order_line": ent("SalesOrderLine", "order no + line no", ["item, quantity", "confirmed order date"], "sales_order_line"),
        "production_plan": ent("ProductionPlan", "plan no", ["period start / end", "status, planner, approver"], "production_plan"),
        "production_plan_line": ent("PlanLine", "plan no + line no", ["item, planned quantity", "planned start / finish", "pegged sales line (optional)"], "production_plan_line"),
        "material_requirement": ent("MaterialRequirement", "plan line + component", ["gross requirement", "needed by date"], "material_requirement"),
        "plan_stock_snapshot": ent("PlanStockSnapshot", "plan + item", ["on-hand quantity"], "plan_stock_snapshot"),
        "production_order_operation": ent("OrderOperation", "order + routing step", ["planned setup / run minutes", "status, operator"], "production_order_operation"),
        "production_order": ent("ProductionOrder", "order no", ["item, planned quantity, status", "planned / actual dates", "BOM + routing revision", "responsible employee"], "production_order"),
        "production_order_component": ent("OrderComponent", "order + component item", ["required quantity"], "production_order_component"),
        "material_issue": ent("MaterialIssue", "issue id", ["quantity, location", "issued by, issued at"], "material_issue"),
        "routing_operation": ent("RoutingStep", "routing + operation no", ["operation name", "setup / run minutes"], "routing_operation"),
        "work_center": ent("WorkCenter", "work center code", ["department", "capacity, hourly rate"], "work_center"),
        "routing": ent("Routing", "item + revision", ["status"], "routing"),
        "bom": ent("BillOfMaterials", "item + revision", ["status, base quantity", "effective from / to", "approver"], "bom"),
        "bom_line": ent("BOMLine", "BOM + component item", ["quantity per base", "scrap %"], "bom_line"),
        "item_unit": ent("ItemUnit", "item + serial no", ["status"], "item_unit"),
        "production_receipt": ent("ProductionReceipt", "receipt id", ["quantity, location", "received / inspected by"], "production_receipt"),
        "inventory_movement": ent("StockMovement", "movement no", ["type: RECEIPT, SALE_ISSUE,", "PROD_ISSUE, PROD_RECEIPT", "item, location, date, quantity"], "inventory_movement"),
        "stock_location": ent("StockLocation", "location code", ["store or warehouse"], "stock_location"),
    }
    svg = Svg(1460, 1340, "Furniture ERP | Plan to Manufacture (logical model)")
    cluster(svg, "planning", [boxes[k] for k in ("production_plan", "production_plan_line", "material_requirement", "plan_stock_snapshot")])
    cluster(svg, "sales", [boxes["sales_order_line"]])
    cluster(svg, "production", [boxes[k] for k in ("production_order_operation", "production_order", "production_order_component", "material_issue")])
    cluster(svg, "engineering", [boxes[k] for k in ("routing_operation", "work_center", "routing", "bom", "bom_line")])
    cluster(svg, "output", [boxes["item_unit"], boxes["production_receipt"]])
    cluster(svg, "inventory", [boxes["inventory_movement"], boxes["stock_location"]])

    for edge in EDGES:
        rel_edge(svg, boxes, edge)

    for b in boxes.values():
        b.draw(svg)

    lx, ly = 1150, 1075
    svg.text(lx, ly, "Notation (crow's foot)", size=12, bold=True)
    legend = [("1", "exactly one"), ("0..1", "zero or one"), ("1..*", "one or more"), ("0..*", "zero or more")]
    for i, (card, label) in enumerate(legend):
        y = ly + 24 + i * 22
        svg.add(f'<line x1="{lx}" y1="{y}" x2="{lx + 46}" y2="{y}" stroke="{INK}" stroke-width="1.2"/>')
        crow_marks(svg, (lx + 46, y), "L", card)
        svg.text(lx + 58, y + 4, f"{card}  {label}", size=11, fill=MUTED)
    notes = ["ID = identifier of the entity.",
             "Every event also records the employee",
             "who performed it (shared Employee)."]
    for i, n in enumerate(notes):
        svg.text(lx, ly + 120 + i * 16, n, size=11, fill=MUTED)
    svg.save("p2m-logical-model.svg")


def process_flow():
    lanes = ["Sales (O2C)", "Engineering", "Production planning", "Shop floor", "Warehouse"]
    lane_h, top, left, width = 132, 80, 30, 1640
    ledger_y = top + lane_h * len(lanes) + 30
    svg = Svg(left + width + 30, ledger_y + 140, "Furniture ERP | Plan to Manufacture process")
    for i, name in enumerate(lanes):
        y = top + i * lane_h
        fill = "#f6f8fb" if i % 2 == 0 else "#ffffff"
        svg.add(f'<rect x="{left}" y="{y}" width="{width}" height="{lane_h}" fill="{fill}" stroke="#c9d3de"/>')
        svg.add(f'<rect x="{left}" y="{y}" width="34" height="{lane_h}" fill="#16263a"/>')
        cx, cy = left + 17, y + lane_h / 2
        svg.add(f'<text x="{cx}" y="{cy}" transform="rotate(-90 {cx} {cy})" font-family="{FONT}" font-size="12" '
                f'font-weight="bold" fill="#ffffff" text-anchor="middle" dominant-baseline="middle">{esc(name)}</text>')

    step_w, step_h = 196, 62
    steps = {}

    def step(key, lane, cx, lines, note=None, colour="#2f5d8a"):
        note_above = lane == 3          # shop floor: arrows arrive from below, keep notes clear of them
        y = top + lane * lane_h + (44 if note_above else 18)
        x = cx - step_w / 2
        svg.add(f'<rect x="{x}" y="{y}" width="{step_w}" height="{step_h}" rx="9" fill="#ffffff" stroke="{colour}" stroke-width="1.6"/>')
        for i, line in enumerate(lines):
            svg.text(cx, y + 24 + i * 16 - (len(lines) - 2) * 8, line, size=12, anchor="middle", bold=(i == 0))
        if note:
            ny = y - 9 if note_above else y + step_h + 17
            svg.text(cx, ny, note, size=10, anchor="middle", fill=MUTED, italic=True)
        steps[key] = (x, y, step_w, step_h)

    def port(key, side, frac=0.5):
        x, y, w, h = steps[key]
        return {"L": (x, y + h * frac), "R": (x + w, y + h * frac),
                "T": (x + w * frac, y), "B": (x + w * frac, y + h)}[side]

    def flow(a, sa, b, sb, mid=None, dashed=False, label=None, fa=0.5, fb=0.5):
        p1, p2 = port(a, sa, fa), port(b, sb, fb)
        pts = polyline(svg, route(p1, sa, p2, sb, mid), dashed=dashed, colour=INK if not dashed else EDGE)
        last = pts[-2]
        length = math.dist(last, p2) or 1
        arrowhead(svg, p2, ((p2[0] - last[0]) / length, (p2[1] - last[1]) / length), colour=INK if not dashed else EDGE)
        if label:
            a_, b_ = pts[-2], pts[-1]
            if abs(a_[0] - b_[0]) < 0.5:
                svg.text(a_[0] + 6, (a_[1] + b_[1]) / 2 + 4, label, size=10, fill=EDGE_LABEL, halo=True)
            else:
                svg.text((a_[0] + b_[0]) / 2, a_[1] - 6, label, size=10, anchor="middle", fill=EDGE_LABEL, halo=True)

    O2C, ENG, PLN, SHOP, WH = "#5b4b95", "#8a5a12", "#2f5d8a", "#8b3a2e", "#1c6b5c"
    step("so", 0, 190, ["Confirm sales order", "draft → lines → confirmed"], colour=O2C)
    step("eng", 1, 650, ["Approve BOM + routing", "revision, effective dates"], "no BOM cycles", colour=ENG)
    step("gr", 4, 190, ["Receive purchased stock", "goods receipt"], "posts RECEIPT", colour=WH)
    step("plan", 2, 420, ["Build production plan", "peg sales lines + legs/seats"], "same item · ≤ ordered qty", colour=PLN)
    step("mrp", 2, 650, ["Run MRP", "explode BOM, snapshot stock"], "stock netted once per plan", colour=PLN)
    step("po", 2, 880, ["Create production orders", "approved BOM + routing"], "Σ orders ≤ plan line qty", colour=PLN)
    step("start", 3, 880, ["Release and start order", "released → in progress"], colour=SHOP)
    step("issue", 4, 1100, ["Issue components", "to the order, from a location"], "≤ required · stock never < 0", colour=WH)
    step("ops", 3, 1100, ["Perform operations", "routing steps at work centers"], "steps of the order's routing", colour=SHOP)
    step("receipt", 4, 1320, ["Receive finished goods", "quality inspected"], "started order · ≤ planned qty", colour=WH)
    step("done", 3, 1320, ["Complete order", "record serial numbers"], "serials ≤ units received", colour=SHOP)
    step("ship", 0, 1540, ["Ship, invoice, collect", "O2C sales issue"], "from produced stock", colour=O2C)

    flow("so", "R", "plan", "T", label="demand")
    flow("eng", "B", "mrp", "T", label="BOM", fa=0.8, fb=0.8)
    flow("plan", "R", "mrp", "L")
    flow("mrp", "R", "po", "L")
    flow("po", "B", "start", "T", fa=0.88, fb=0.88)
    flow("start", "B", "issue", "L")
    flow("issue", "T", "ops", "B")
    flow("ops", "R", "receipt", "L", mid=1215)
    flow("receipt", "T", "done", "B")
    flow("done", "R", "ship", "B", label="stock available", fb=0.16)
    flow("gr", "T", "mrp", "B", dashed=True, label="on-hand", fb=0.1)

    # shared ledger band
    lx, lw = left + 120, width - 160
    svg.add(f'<rect x="{lx}" y="{ledger_y}" width="{lw}" height="58" rx="10" fill="#e7f6f0" stroke="#1c6b5c" stroke-width="1.4"/>')
    svg.text(lx + lw / 2, ledger_y + 24, "Shared stock ledger: inventory.inventory_movement", size=14, anchor="middle", fill="#1c6b5c", bold=True)
    svg.text(lx + lw / 2, ledger_y + 44, "balance per location and item = inbound (RECEIPT, PROD_RECEIPT) − outbound (SALE_ISSUE, PROD_ISSUE); "
             "every posting is rejected if any day's end balance would be negative", size=11, anchor="middle", fill=MUTED)
    for key, label in (("gr", "RECEIPT"), ("issue", "PROD_ISSUE"), ("receipt", "PROD_RECEIPT")):
        x, y, w, h = steps[key]
        p1, p2 = (x + w / 2, y + h + (24 if key != "gr" else 24)), (x + w / 2, ledger_y)
        polyline(svg, [p1, p2], dashed=True)
        arrowhead(svg, p2, (0, 1))
        svg.text(p1[0] + 6, ledger_y - 8, label, size=10, fill=EDGE_LABEL, halo=True)
    x, y, w, h = steps["ship"]
    p1, p2 = (x + w * 0.9, y + h + 24), (x + w * 0.9, ledger_y)
    polyline(svg, [p1, p2], dashed=True)
    arrowhead(svg, p2, (0, 1))
    svg.text(p1[0] - 6, ledger_y - 8, "SALE_ISSUE", size=10, anchor="end", fill=EDGE_LABEL, halo=True)

    svg.text(left, ledger_y + 92, "Solid arrows: process sequence. Dashed arrows: postings to and reads from the shared stock ledger. "
             "Italic notes: rules the database enforces at that step.", size=11, fill=MUTED)
    svg.save("p2m-process-flow.svg")


if __name__ == "__main__":
    physical()
    logical()
    process_flow()
