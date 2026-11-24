#!/usr/bin/env python3
"""Generate docs/p2m-data-dictionary.md from an installed database.

Types, nullability, defaults, constraints and triggers are read from the PostgreSQL
catalog, so the dictionary always matches the physical schema. Only the meaning of
each table, column and trigger is maintained by hand below.

Usage (database must contain db_init.sql + o2c-database.sql + p2m-database.sql):
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=erp \
        python3 database/docs/tools/gen_p2m_data_dictionary.py
"""
import json
import os
import pathlib
import subprocess

OUT = pathlib.Path(__file__).resolve().parent.parent / "p2m-data-dictionary.md"

# (relation, description, {column: meaning})
TABLES = [
    ("engineering.bom", "Bill of materials header: one revision of the recipe for a manufacturable item.", {
        "bom_id": "Surrogate BOM identifier",
        "item_id": "Manufacturable item the recipe produces",
        "revision": "Revision label, unique per item",
        "status": "`TASLAK` draft, `ONAYLI` approved, `GECERSIZ` retired",
        "base_quantity": "Output quantity the component quantities refer to",
        "effective_from": "First date a production order may start with this revision",
        "effective_to": "Last valid start date; open-ended when empty",
        "approved_by": "Employee who approved the revision; required once approved",
    }),
    ("engineering.bom_line", "Component of a BOM revision.", {
        "bom_line_id": "Surrogate BOM line identifier",
        "bom_id": "BOM revision the line belongs to",
        "line_no": "Line number within the BOM",
        "component_item_id": "Consumable item used; each component appears once per BOM",
        "quantity_per": "Component quantity per `bom.base_quantity` of output",
        "scrap_percent": "Expected loss added on top of `quantity_per` (0 to below 100)",
    }),
    ("engineering.work_center", "Production resource where routing operations are performed.", {
        "work_center_id": "Surrogate work-center identifier",
        "work_center_code": "Stable business code",
        "work_center_name": "Display name",
        "department_id": "Owning department (shared master)",
        "capacity_hours_per_day": "Available hours per day (up to 24)",
        "hourly_rate": "Cost rate per hour",
        "is_active": "Active work-center flag",
    }),
    ("engineering.routing", "Ordered list of operations needed to make a manufacturable item.", {
        "routing_id": "Surrogate routing identifier",
        "item_id": "Manufacturable item the routing produces",
        "revision": "Revision label, unique per item",
        "status": "`TASLAK` draft, `ONAYLI` approved, `GECERSIZ` retired",
    }),
    ("engineering.routing_operation", "One step of a routing at a work center.", {
        "routing_operation_id": "Surrogate operation identifier",
        "routing_id": "Routing the step belongs to",
        "operation_no": "Sequence number within the routing (10, 20, ...)",
        "operation_name": "Step description",
        "work_center_id": "Work center performing the step",
        "setup_minutes": "Fixed setup time per production order",
        "run_minutes_per_unit": "Run time per unit produced",
    }),
    ("planning.production_plan", "Production plan for a period.", {
        "production_plan_id": "Surrogate plan identifier",
        "plan_no": "Unique plan number",
        "plan_name": "Plan title",
        "period_start": "First day of the planning period",
        "period_end": "Last day of the planning period",
        "status": "`TASLAK` draft, `ONAYLANDI` approved, `KAPANDI` closed",
        "created_by": "Planner who created the plan",
        "approved_by": "Employee who approved the plan; required unless draft",
        "created_at": "Creation timestamp",
    }),
    ("planning.production_plan_line", "Quantity of one item to produce within a plan; optionally pegged to an O2C sales order line.", {
        "production_plan_line_id": "Surrogate plan-line identifier",
        "production_plan_id": "Plan the line belongs to",
        "line_no": "Line number within the plan",
        "item_id": "Manufacturable item to produce; must equal the sales line item when pegged",
        "sales_order_line_id": "O2C sales line this production satisfies; empty for dependent or stock demand",
        "planned_quantity": "Quantity to produce",
        "planned_start_date": "Planned start; within the plan period and not before the order date",
        "planned_finish_date": "Planned finish; within the plan period",
    }),
    ("planning.material_requirement", "MRP gross requirement: BOM explosion (including scrap) of one plan line for one component.", {
        "material_requirement_id": "Surrogate requirement identifier",
        "production_plan_line_id": "Plan line generating the demand",
        "component_item_id": "Component required",
        "gross_requirement": "Required quantity before stock netting",
        "needed_by_date": "Date the component is needed (plan-line start)",
    }),
    ("planning.plan_stock_snapshot", "On-hand stock captured once per plan and item when MRP runs; used for netting at plan level.", {
        "production_plan_id": "Plan the snapshot belongs to",
        "item_id": "Component item",
        "on_hand_quantity": "Ledger stock across all locations at snapshot time",
    }),
    ("production.production_order", "Order to make a quantity of one item from a plan line with a fixed BOM and routing.", {
        "production_order_id": "Surrogate production-order identifier",
        "order_no": "Unique production order number",
        "production_plan_line_id": "Plan line the order fulfils (same item)",
        "item_id": "Item produced; must match the plan line, BOM and routing",
        "bom_id": "Approved BOM revision effective on the planned start",
        "routing_id": "Approved routing revision",
        "planned_quantity": "Quantity to produce; non-cancelled orders of a plan line cannot exceed it",
        "status": "`PLANLANDI` planned, `SERBEST` released, `DEVAM_EDIYOR` in progress, `TAMAMLANDI` completed, `IPTAL` cancelled",
        "planned_start_date": "Planned start date",
        "planned_finish_date": "Planned finish date",
        "actual_start_date": "Actual start; required once in progress or completed",
        "actual_finish_date": "Actual finish; required once completed",
        "responsible_employee_id": "Employee responsible for the order",
    }),
    ("production.production_order_component", "Component requirement of a production order, snapshotted from its BOM at release.", {
        "production_order_component_id": "Surrogate component-requirement identifier",
        "production_order_id": "Production order",
        "bom_id": "The order's BOM; ties the component to a line of that BOM",
        "component_item_id": "Component item; must be a line of the order's BOM",
        "required_quantity": "Quantity required in ledger precision; caps cumulative issues",
    }),
    ("production.production_order_operation", "Routing step scheduled for a production order.", {
        "production_order_operation_id": "Surrogate order-operation identifier",
        "production_order_id": "Production order",
        "routing_id": "The order's routing; ties the step to that routing",
        "routing_operation_id": "Routing step; must belong to the order's routing",
        "planned_setup_minutes": "Planned setup time",
        "planned_run_minutes": "Planned run time for the order quantity",
        "status": "`BEKLIYOR` waiting, `DEVAM_EDIYOR` in progress, `TAMAMLANDI` done",
        "operator_id": "Employee performing the step",
    }),
    ("production.material_issue", "Component quantity issued from a stock location to a production order. Posts one `PROD_ISSUE` ledger movement.", {
        "material_issue_id": "Surrogate issue identifier",
        "production_order_id": "Production order consuming the material",
        "component_item_id": "Component issued; must be a component of that order",
        "location_id": "Stock location the material leaves",
        "quantity": "Issued quantity in the item base unit",
        "issued_by": "Employee issuing the material; recorded on the movement",
        "issued_at": "Issue timestamp; its date is the ledger business date",
    }),
    ("production.production_receipt", "Finished quantity received from a production order into a stock location. Posts one `PROD_RECEIPT` ledger movement.", {
        "production_receipt_id": "Surrogate receipt identifier",
        "production_order_id": "Production order that produced the goods",
        "location_id": "Stock location receiving the goods",
        "quantity": "Received quantity in the item base unit",
        "received_by": "Employee receiving the goods; recorded on the movement",
        "inspected_by": "Quality inspector",
        "received_at": "Receipt timestamp; its date is the ledger business date",
        "notes": "Free-text remarks",
    }),
    ("production.item_unit", "Individually tracked physical unit of a serialized item, tied to the order that made it.", {
        "item_unit_id": "Surrogate unit identifier",
        "item_id": "Serialized item; must match the producing order",
        "production_order_id": "Order that produced the unit",
        "serial_number": "Serial number, unique per item",
        "status": "`STOKTA` in stock, `SEVK_EDILDI` shipped, `HURDA` scrapped",
    }),
    ("inventory.inventory_movement", "Shared append-only stock ledger owned by O2C. P2M adds two movement types and their source columns. Each movement has exactly one source document.", {
        "movement_id": "Surrogate movement identifier",
        "movement_no": "Unique movement reference (`GR:`, `MI:`, `PR:` prefixes for posted documents)",
        "movement_type": "`RECEIPT`, `SALE_ISSUE` (O2C) and `PROD_RECEIPT`, `PROD_ISSUE` (P2M)",
        "location_id": "Location affected by the movement",
        "item_id": "Stock item affected by the movement",
        "order_line_id": "Sales line for a sales issue",
        "receipt_line_id": "Goods-receipt line for a purchase receipt",
        "moved_on": "Effective stock business date",
        "quantity": "Positive magnitude in the item unit; direction comes from the type",
        "recorded_by": "Employee who recorded the movement",
        "material_issue_id": "P2M material issue for a `PROD_ISSUE` (added by P2M)",
        "production_receipt_id": "P2M production receipt for a `PROD_RECEIPT` (added by P2M)",
    }),
]

VIEWS = [
    ("planning.material_requirement_net", "Net component requirement per plan: total gross demand of all plan lines less the stock snapshot taken once for the plan.", {
        "production_plan_id": "Plan",
        "component_item_id": "Component item",
        "gross_requirement": "Sum of gross requirements over the plan's lines",
        "on_hand_quantity": "Plan stock snapshot, zero when none was taken",
        "net_requirement": "Gross requirement less on-hand, never below zero",
        "first_needed_by": "Earliest date the component is needed",
    }),
    ("inventory.stock_balance", "Read-only stock on hand per location and item (O2C view; now includes production movements).", {
        "location_id": "Location in the movement ledger",
        "item_id": "Item in the movement ledger",
        "quantity_on_hand": "Inbound (`RECEIPT`, `PROD_RECEIPT`) less outbound (`SALE_ISSUE`, `PROD_ISSUE`) quantities",
    }),
]

TRIGGERS = {
    "trg_bom_manufacturable": "The BOM item must be manufacturable.",
    "trg_bom_line_consumable": "A BOM component must be consumable.",
    "trg_bom_line_acyclic": "A component may not be the parent item or contain it at any depth (no BOM cycles).",
    "trg_routing_manufacturable": "The routing item must be manufacturable.",
    "trg_guard_plan_period": "The plan period cannot be changed to exclude existing plan lines.",
    "trg_guard_plan_line": "Dates fall within the plan period. A pegged sales line must belong to a confirmed order dated on or before the planned start, and the quantity planned for it cannot exceed the ordered quantity.",
    "trg_plan_line_manufacturable": "The planned item must be manufacturable.",
    "trg_guard_production_order": "Requires an approved BOM effective on the planned start and an approved routing. Non-cancelled orders of a plan line cannot exceed its planned quantity.",
    "trg_po_manufacturable": "The produced item must be manufacturable.",
    "trg_post_material_issue": "Only released or in-progress orders accept issues, cumulative issues cannot exceed the required quantity, and the issue posts one `PROD_ISSUE` movement.",
    "trg_keep_material_issue": "Posted issues cannot be changed or deleted.",
    "trg_post_production_receipt": "Only started orders accept receipts, the receipt cannot precede the actual start, cumulative receipts cannot exceed the planned quantity, and the receipt posts one `PROD_RECEIPT` movement.",
    "trg_keep_production_receipt": "Posted receipts cannot be changed or deleted.",
    "trg_item_unit_serialized": "Units can only be recorded for serialized items.",
    "trg_guard_item_unit": "The number of serial numbers cannot exceed the quantity received from the order.",
    "trg_apply_movement": "O2C: validates receipt and sales-issue sources, serializes postings per location and item, and rejects any outbound movement that makes the end-of-day balance negative on any date.",
    "trg_validate_production_movement": "P2M: a production movement must match its source issue or receipt (location, item, date, quantity, employee).",
    "trg_keep_stock_movement": "O2C: posted movements cannot be changed or deleted.",
    "trg_prevent_movement_truncate": "O2C: the ledger cannot be truncated.",
}

KIND = {"p": "PK", "f": "FK", "u": "UQ", "c": "CK"}
ORDER = {"p": 0, "f": 1, "u": 2, "c": 3}


def query(sql):
    # an empty search_path makes pg_get_constraintdef print schema-qualified names (public.item)
    env = dict(os.environ, PGOPTIONS="-c search_path=pg_catalog")
    out = subprocess.run(["psql", "-X", "-At", "-c", sql], check=True, capture_output=True, text=True, env=env).stdout
    return json.loads(out) if out.strip() else []


def relation_meta(rel):
    columns = query(f"""
        SELECT json_agg(json_build_object(
            'name', a.attname, 'num', a.attnum, 'type', format_type(a.atttypid, a.atttypmod),
            'notnull', a.attnotnull, 'identity', a.attidentity, 'generated', a.attgenerated,
            'default', pg_get_expr(d.adbin, d.adrelid)) ORDER BY a.attnum)
        FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = '{rel}'::regclass AND a.attnum > 0 AND NOT a.attisdropped""")
    constraints = query(f"""
        SELECT json_agg(json_build_object('type', contype, 'def', pg_get_constraintdef(oid), 'cols', conkey))
        FROM pg_constraint WHERE conrelid = '{rel}'::regclass AND contype IN ('p', 'f', 'u', 'c')""") or []
    triggers = query(f"""
        SELECT json_agg(tgname ORDER BY tgname) FROM pg_trigger
        WHERE tgrelid = '{rel}'::regclass AND NOT tgisinternal""") or []
    return columns, constraints, triggers


def null_default(col):
    text = "Required" if col["notnull"] else "Nullable"
    if col["identity"]:
        return text + ", generated identity"
    if col["default"]:
        default = col["default"].replace("::character varying", "").replace("::numeric", "")
        return f"{text}, default `{default}`"
    return text


def table_section(rel, description, meanings, is_view=False):
    columns, constraints, triggers = relation_meta(rel)
    constraints.sort(key=lambda c: (ORDER[c["type"]], c["def"]))
    missing = {c["name"] for c in columns} - set(meanings)
    if missing:
        raise SystemExit(f"{rel}: no meaning documented for {sorted(missing)}")
    lines = [f"## `{rel}`", "", description, "",
             "| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |",
             "| --- | --- | --- | --- | --- |"]
    for col in columns:
        refs = [f"{KIND[c['type']]} {i}" for i, c in enumerate(constraints, 1) if col["num"] in (c["cols"] or [])]
        nd = "Derived" if is_view else null_default(col)
        lines.append(f"| `{col['name']}` | `{col['type']}` | {nd} | {', '.join(refs) or '—'} | {meanings[col['name']]} |")
    lines.append("")
    for i, c in enumerate(constraints, 1):
        lines.append(f"{i}. `{c['def']}`")
    if constraints:
        lines.append("")
    if triggers:
        lines.append("Rules enforced by triggers:")
        lines.append("")
        for name in triggers:
            if name not in TRIGGERS:
                raise SystemExit(f"{rel}: trigger {name} is not documented")
            lines.append(f"- `{name}`: {TRIGGERS[name]}")
        lines.append("")
    return lines


def main():
    doc = [
        "# P2M Data Dictionary",
        "",
        "This dictionary describes the installed Plan to Manufacture (P2M) schema and the parts of the shared "
        "stock ledger it extends. It is generated from the PostgreSQL catalog by "
        "`tools/gen_p2m_data_dictionary.py`; edit meanings there and regenerate rather than editing this file. "
        "PK is a primary key, FK is a foreign key, UQ is a unique constraint, and CK is a check constraint. "
        "Constraint references below each table give the exact PostgreSQL definitions.",
        "",
        "The shared master tables `public.item`, `public.employee`, `public.department`, `public.customer`, "
        "`public.supplier`, the O2C tables `sales.sales_order` and `sales.sales_order_line`, and "
        "`inventory.stock_location` are used unchanged and are described in `o2c-data-dictionary.md`.",
        "",
    ]
    for rel, description, meanings in TABLES:
        doc += table_section(rel, description, meanings)
    for rel, description, meanings in VIEWS:
        doc += table_section(rel, description, meanings, is_view=True)
    doc += [
        "## Ledger Direction",
        "",
        "`inventory.signed_quantity(movement_type, quantity)` (defined in `o2c-database.sql`) returns the quantity "
        "for inbound types `RECEIPT` and `PROD_RECEIPT` and the negated quantity for every other type. "
        "`inventory.stock_balance` and the negative-stock check in `inventory.apply_movement` both use it, so "
        "receipts, sales issues, material issues and production receipts share one balance per location and item.",
        "",
        "## Transaction Rules",
        "",
        "- BOMs and routings belong to manufacturable items; BOM components are consumable. A BOM may never contain "
        "its own item directly or indirectly.",
        "- A plan line stays inside its plan period. When it is pegged to an O2C sales line it plans the same item, "
        "the order is confirmed and dated on or before the planned start, and the quantity planned across all plan "
        "lines does not exceed the ordered quantity.",
        "- MRP stores gross requirements per plan line and one stock snapshot per plan. "
        "`planning.material_requirement_net` nets the total demand against that snapshot once.",
        "- A production order uses the plan line's item, an approved BOM effective on its planned start and an "
        "approved routing. Its components and operations come only from that BOM and routing.",
        "- Material may be issued to released or in-progress orders, only for the order's components and up to the "
        "required quantity. Each issue posts a `PROD_ISSUE` movement; the ledger rejects it if stock at the "
        "location would be negative at the end of any date.",
        "- Finished goods may be received from in-progress or completed orders, not before the actual start and up to "
        "the planned quantity. Each receipt posts a `PROD_RECEIPT` movement that O2C can then ship and invoice.",
        "- Serial numbers of a serialized item cannot outnumber the units received. Posted issues, receipts and "
        "movements cannot be changed or deleted.",
        "",
    ]
    OUT.write_text("\n".join(doc), encoding="utf-8")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
