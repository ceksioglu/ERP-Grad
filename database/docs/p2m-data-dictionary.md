# P2M Data Dictionary

This dictionary describes the installed Plan to Manufacture (P2M) schema and the parts of the shared stock ledger it extends. It is generated from the PostgreSQL catalog by `tools/gen_p2m_data_dictionary.py`; edit meanings there and regenerate rather than editing this file. PK is a primary key, FK is a foreign key, UQ is a unique constraint, and CK is a check constraint. Constraint references below each table give the exact PostgreSQL definitions.

The shared master tables `public.item`, `public.employee`, `public.department`, `public.customer`, `public.supplier`, the O2C tables `sales.sales_order` and `sales.sales_order_line`, and `inventory.stock_location` are used unchanged and are described in `o2c-data-dictionary.md`.

## `engineering.bom`

Bill of materials header: one revision of the recipe for a manufacturable item.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `bom_id` | `integer` | Required, generated identity | PK 1, UQ 4 | Surrogate BOM identifier |
| `item_id` | `integer` | Required | FK 3, UQ 4, UQ 5 | Manufacturable item the recipe produces |
| `revision` | `character varying(10)` | Required | UQ 5 | Revision label, unique per item |
| `status` | `character varying(10)` | Required, default `'TASLAK'` | CK 6, CK 9 | `TASLAK` draft, `ONAYLI` approved, `GECERSIZ` retired |
| `base_quantity` | `numeric(12,3)` | Required, default `1` | CK 7 | Output quantity the component quantities refer to |
| `effective_from` | `date` | Required | CK 8 | First date a production order may start with this revision |
| `effective_to` | `date` | Nullable | CK 8 | Last valid start date; open-ended when empty |
| `approved_by` | `integer` | Nullable | FK 2, CK 6 | Employee who approved the revision; required once approved |

1. `PRIMARY KEY (bom_id)`
2. `FOREIGN KEY (approved_by) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
4. `UNIQUE (bom_id, item_id)`
5. `UNIQUE (item_id, revision)`
6. `CHECK ((((status)::text <> 'ONAYLI'::text) OR (approved_by IS NOT NULL)))`
7. `CHECK (((base_quantity > (0)::numeric) AND (base_quantity <> 'NaN'::numeric)))`
8. `CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))`
9. `CHECK (((status)::text = ANY ((ARRAY['TASLAK'::character varying, 'ONAYLI'::character varying, 'GECERSIZ'::character varying])::text[])))`

Rules enforced by triggers:

- `trg_bom_manufacturable`: The BOM item must be manufacturable.

## `engineering.bom_line`

Component of a BOM revision.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `bom_line_id` | `integer` | Required, generated identity | PK 1 | Surrogate BOM line identifier |
| `bom_id` | `integer` | Required | FK 2, UQ 4, UQ 5 | BOM revision the line belongs to |
| `line_no` | `integer` | Required | UQ 5, CK 8 | Line number within the BOM |
| `component_item_id` | `integer` | Required | FK 3, UQ 4 | Consumable item used; each component appears once per BOM |
| `quantity_per` | `numeric(14,4)` | Required | CK 6 | Component quantity per `bom.base_quantity` of output |
| `scrap_percent` | `numeric(5,2)` | Required, default `0` | CK 7 | Expected loss added on top of `quantity_per` (0 to below 100) |

1. `PRIMARY KEY (bom_line_id)`
2. `FOREIGN KEY (bom_id) REFERENCES engineering.bom(bom_id) ON DELETE CASCADE`
3. `FOREIGN KEY (component_item_id) REFERENCES public.item(item_id)`
4. `UNIQUE (bom_id, component_item_id)`
5. `UNIQUE (bom_id, line_no)`
6. `CHECK (((quantity_per > (0)::numeric) AND (quantity_per <> 'NaN'::numeric)))`
7. `CHECK (((scrap_percent >= (0)::numeric) AND (scrap_percent < (100)::numeric)))`
8. `CHECK ((line_no > 0))`

Rules enforced by triggers:

- `trg_bom_line_acyclic`: A component may not be the parent item or contain it at any depth (no BOM cycles).
- `trg_bom_line_consumable`: A BOM component must be consumable.

## `engineering.work_center`

Production resource where routing operations are performed.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `work_center_id` | `integer` | Required, generated identity | PK 1 | Surrogate work-center identifier |
| `work_center_code` | `character varying(15)` | Required | UQ 3 | Stable business code |
| `work_center_name` | `character varying(100)` | Required | — | Display name |
| `department_id` | `integer` | Required | FK 2 | Owning department (shared master) |
| `capacity_hours_per_day` | `numeric(5,2)` | Required | CK 4 | Available hours per day (up to 24) |
| `hourly_rate` | `numeric(10,2)` | Nullable | CK 5 | Cost rate per hour |
| `is_active` | `boolean` | Required, default `true` | — | Active work-center flag |

1. `PRIMARY KEY (work_center_id)`
2. `FOREIGN KEY (department_id) REFERENCES public.department(department_id)`
3. `UNIQUE (work_center_code)`
4. `CHECK (((capacity_hours_per_day > (0)::numeric) AND (capacity_hours_per_day <= (24)::numeric)))`
5. `CHECK (((hourly_rate >= (0)::numeric) AND (hourly_rate <> 'NaN'::numeric)))`

## `engineering.routing`

Ordered list of operations needed to make a manufacturable item.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `routing_id` | `integer` | Required, generated identity | PK 1, UQ 4 | Surrogate routing identifier |
| `item_id` | `integer` | Required | FK 2, UQ 3, UQ 4 | Manufacturable item the routing produces |
| `revision` | `character varying(10)` | Required | UQ 3 | Revision label, unique per item |
| `status` | `character varying(10)` | Required, default `'TASLAK'` | CK 5 | `TASLAK` draft, `ONAYLI` approved, `GECERSIZ` retired |

1. `PRIMARY KEY (routing_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `UNIQUE (item_id, revision)`
4. `UNIQUE (routing_id, item_id)`
5. `CHECK (((status)::text = ANY ((ARRAY['TASLAK'::character varying, 'ONAYLI'::character varying, 'GECERSIZ'::character varying])::text[])))`

Rules enforced by triggers:

- `trg_routing_manufacturable`: The routing item must be manufacturable.

## `engineering.routing_operation`

One step of a routing at a work center.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `routing_operation_id` | `integer` | Required, generated identity | PK 1, UQ 5 | Surrogate operation identifier |
| `routing_id` | `integer` | Required | FK 2, UQ 4, UQ 5 | Routing the step belongs to |
| `operation_no` | `integer` | Required | UQ 4, CK 8 | Sequence number within the routing (10, 20, ...) |
| `operation_name` | `character varying(100)` | Required | — | Step description |
| `work_center_id` | `integer` | Required | FK 3 | Work center performing the step |
| `setup_minutes` | `numeric(8,2)` | Required, default `0` | CK 7 | Fixed setup time per production order |
| `run_minutes_per_unit` | `numeric(8,2)` | Required | CK 6 | Run time per unit produced |

1. `PRIMARY KEY (routing_operation_id)`
2. `FOREIGN KEY (routing_id) REFERENCES engineering.routing(routing_id) ON DELETE CASCADE`
3. `FOREIGN KEY (work_center_id) REFERENCES engineering.work_center(work_center_id)`
4. `UNIQUE (routing_id, operation_no)`
5. `UNIQUE (routing_operation_id, routing_id)`
6. `CHECK (((run_minutes_per_unit >= (0)::numeric) AND (run_minutes_per_unit <> 'NaN'::numeric)))`
7. `CHECK (((setup_minutes >= (0)::numeric) AND (setup_minutes <> 'NaN'::numeric)))`
8. `CHECK ((operation_no > 0))`

## `planning.production_plan`

Production plan for a period.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_plan_id` | `integer` | Required, generated identity | PK 1 | Surrogate plan identifier |
| `plan_no` | `character varying(20)` | Required | UQ 4 | Unique plan number |
| `plan_name` | `character varying(150)` | Required | — | Plan title |
| `period_start` | `date` | Required | CK 7 | First day of the planning period |
| `period_end` | `date` | Required | CK 7 | Last day of the planning period |
| `status` | `character varying(12)` | Required, default `'TASLAK'` | CK 5, CK 6 | `TASLAK` draft, `ONAYLANDI` approved, `KAPANDI` closed |
| `created_by` | `integer` | Required | FK 3 | Planner who created the plan |
| `approved_by` | `integer` | Nullable | FK 2, CK 5 | Employee who approved the plan; required unless draft |
| `created_at` | `timestamp without time zone` | Required, default `now()` | — | Creation timestamp |

1. `PRIMARY KEY (production_plan_id)`
2. `FOREIGN KEY (approved_by) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (created_by) REFERENCES public.employee(employee_id)`
4. `UNIQUE (plan_no)`
5. `CHECK ((((status)::text = 'TASLAK'::text) OR (approved_by IS NOT NULL)))`
6. `CHECK (((status)::text = ANY ((ARRAY['TASLAK'::character varying, 'ONAYLANDI'::character varying, 'KAPANDI'::character varying])::text[])))`
7. `CHECK ((period_end >= period_start))`

Rules enforced by triggers:

- `trg_guard_plan_period`: The plan period cannot be changed to exclude existing plan lines.

## `planning.production_plan_line`

Quantity of one item to produce within a plan; optionally pegged to an O2C sales order line.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_plan_line_id` | `integer` | Required, generated identity | PK 1, UQ 6 | Surrogate plan-line identifier |
| `production_plan_id` | `integer` | Required | FK 3, UQ 5 | Plan the line belongs to |
| `line_no` | `integer` | Required | UQ 5, CK 8 | Line number within the plan |
| `item_id` | `integer` | Required | FK 2, FK 4, UQ 6 | Manufacturable item to produce; must equal the sales line item when pegged |
| `sales_order_line_id` | `integer` | Nullable | FK 4 | O2C sales line this production satisfies; empty for dependent or stock demand |
| `planned_quantity` | `numeric(12,3)` | Required | CK 7 | Quantity to produce |
| `planned_start_date` | `date` | Required | CK 9 | Planned start; within the plan period and not before the order date |
| `planned_finish_date` | `date` | Required | CK 9 | Planned finish; within the plan period |

1. `PRIMARY KEY (production_plan_line_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (production_plan_id) REFERENCES planning.production_plan(production_plan_id) ON DELETE CASCADE`
4. `FOREIGN KEY (sales_order_line_id, item_id) REFERENCES sales.sales_order_line(order_line_id, item_id)`
5. `UNIQUE (production_plan_id, line_no)`
6. `UNIQUE (production_plan_line_id, item_id)`
7. `CHECK (((planned_quantity > (0)::numeric) AND (planned_quantity <> 'NaN'::numeric)))`
8. `CHECK ((line_no > 0))`
9. `CHECK ((planned_finish_date >= planned_start_date))`

Rules enforced by triggers:

- `trg_guard_plan_line`: Dates fall within the plan period. A pegged sales line must belong to a confirmed order dated on or before the planned start, and the quantity planned for it cannot exceed the ordered quantity.
- `trg_plan_line_manufacturable`: The planned item must be manufacturable.

## `planning.material_requirement`

MRP gross requirement: BOM explosion (including scrap) of one plan line for one component.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `material_requirement_id` | `integer` | Required, generated identity | PK 1 | Surrogate requirement identifier |
| `production_plan_line_id` | `integer` | Required | FK 3, UQ 4 | Plan line generating the demand |
| `component_item_id` | `integer` | Required | FK 2, UQ 4 | Component required |
| `gross_requirement` | `numeric(14,4)` | Required | CK 5 | Required quantity before stock netting |
| `needed_by_date` | `date` | Required | — | Date the component is needed (plan-line start) |

1. `PRIMARY KEY (material_requirement_id)`
2. `FOREIGN KEY (component_item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (production_plan_line_id) REFERENCES planning.production_plan_line(production_plan_line_id) ON DELETE CASCADE`
4. `UNIQUE (production_plan_line_id, component_item_id)`
5. `CHECK (((gross_requirement >= (0)::numeric) AND (gross_requirement <> 'NaN'::numeric)))`

## `planning.plan_stock_snapshot`

On-hand stock captured once per plan and item when MRP runs; used for netting at plan level.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_plan_id` | `integer` | Required | PK 1, FK 3 | Plan the snapshot belongs to |
| `item_id` | `integer` | Required | PK 1, FK 2 | Component item |
| `on_hand_quantity` | `numeric(14,4)` | Required | CK 4 | Ledger stock across all locations at snapshot time |

1. `PRIMARY KEY (production_plan_id, item_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (production_plan_id) REFERENCES planning.production_plan(production_plan_id) ON DELETE CASCADE`
4. `CHECK (((on_hand_quantity >= (0)::numeric) AND (on_hand_quantity <> 'NaN'::numeric)))`

## `production.production_order`

Order to make a quantity of one item from a plan line with a fixed BOM and routing.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_order_id` | `integer` | Required, generated identity | PK 1, UQ 8, UQ 9, UQ 10 | Surrogate production-order identifier |
| `order_no` | `character varying(20)` | Required | UQ 7 | Unique production order number |
| `production_plan_line_id` | `integer` | Required | FK 4 | Plan line the order fulfils (same item) |
| `item_id` | `integer` | Required | FK 2, FK 3, FK 4, FK 6, UQ 9 | Item produced; must match the plan line, BOM and routing |
| `bom_id` | `integer` | Required | FK 2, UQ 8 | Approved BOM revision effective on the planned start |
| `routing_id` | `integer` | Required | FK 6, UQ 10 | Approved routing revision |
| `planned_quantity` | `numeric(12,3)` | Required | CK 14 | Quantity to produce; non-cancelled orders of a plan line cannot exceed it |
| `status` | `character varying(12)` | Required, default `'PLANLANDI'` | CK 11, CK 12, CK 15 | `PLANLANDI` planned, `SERBEST` released, `DEVAM_EDIYOR` in progress, `TAMAMLANDI` completed, `IPTAL` cancelled |
| `planned_start_date` | `date` | Required | CK 16 | Planned start date |
| `planned_finish_date` | `date` | Required | CK 16 | Planned finish date |
| `actual_start_date` | `date` | Nullable | CK 12, CK 13 | Actual start; required once in progress or completed |
| `actual_finish_date` | `date` | Nullable | CK 11, CK 13 | Actual finish; required once completed |
| `responsible_employee_id` | `integer` | Required | FK 5 | Employee responsible for the order |

1. `PRIMARY KEY (production_order_id)`
2. `FOREIGN KEY (bom_id, item_id) REFERENCES engineering.bom(bom_id, item_id)`
3. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
4. `FOREIGN KEY (production_plan_line_id, item_id) REFERENCES planning.production_plan_line(production_plan_line_id, item_id)`
5. `FOREIGN KEY (responsible_employee_id) REFERENCES public.employee(employee_id)`
6. `FOREIGN KEY (routing_id, item_id) REFERENCES engineering.routing(routing_id, item_id)`
7. `UNIQUE (order_no)`
8. `UNIQUE (production_order_id, bom_id)`
9. `UNIQUE (production_order_id, item_id)`
10. `UNIQUE (production_order_id, routing_id)`
11. `CHECK ((((status)::text <> 'TAMAMLANDI'::text) OR (actual_finish_date IS NOT NULL)))`
12. `CHECK ((((status)::text <> ALL ((ARRAY['DEVAM_EDIYOR'::character varying, 'TAMAMLANDI'::character varying])::text[])) OR (actual_start_date IS NOT NULL)))`
13. `CHECK (((actual_finish_date IS NULL) OR ((actual_start_date IS NOT NULL) AND (actual_finish_date >= actual_start_date))))`
14. `CHECK (((planned_quantity > (0)::numeric) AND (planned_quantity <> 'NaN'::numeric)))`
15. `CHECK (((status)::text = ANY ((ARRAY['PLANLANDI'::character varying, 'SERBEST'::character varying, 'DEVAM_EDIYOR'::character varying, 'TAMAMLANDI'::character varying, 'IPTAL'::character varying])::text[])))`
16. `CHECK ((planned_finish_date >= planned_start_date))`

Rules enforced by triggers:

- `trg_guard_production_order`: Requires an approved BOM effective on the planned start and an approved routing. Non-cancelled orders of a plan line cannot exceed its planned quantity.
- `trg_po_manufacturable`: The produced item must be manufacturable.

## `production.production_order_component`

Component requirement of a production order, snapshotted from its BOM at release.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_order_component_id` | `integer` | Required, generated identity | PK 1 | Surrogate component-requirement identifier |
| `production_order_id` | `integer` | Required | FK 3, UQ 4 | Production order |
| `bom_id` | `integer` | Required | FK 2, FK 3 | The order's BOM; ties the component to a line of that BOM |
| `component_item_id` | `integer` | Required | FK 2, UQ 4 | Component item; must be a line of the order's BOM |
| `required_quantity` | `numeric(12,3)` | Required | CK 5 | Quantity required in ledger precision; caps cumulative issues |

1. `PRIMARY KEY (production_order_component_id)`
2. `FOREIGN KEY (bom_id, component_item_id) REFERENCES engineering.bom_line(bom_id, component_item_id)`
3. `FOREIGN KEY (production_order_id, bom_id) REFERENCES production.production_order(production_order_id, bom_id) ON DELETE CASCADE`
4. `UNIQUE (production_order_id, component_item_id)`
5. `CHECK (((required_quantity > (0)::numeric) AND (required_quantity <> 'NaN'::numeric)))`

## `production.production_order_operation`

Routing step scheduled for a production order.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_order_operation_id` | `integer` | Required, generated identity | PK 1 | Surrogate order-operation identifier |
| `production_order_id` | `integer` | Required | FK 3, UQ 5 | Production order |
| `routing_id` | `integer` | Required | FK 3, FK 4 | The order's routing; ties the step to that routing |
| `routing_operation_id` | `integer` | Required | FK 4, UQ 5 | Routing step; must belong to the order's routing |
| `planned_setup_minutes` | `numeric(10,2)` | Required | CK 7 | Planned setup time |
| `planned_run_minutes` | `numeric(10,2)` | Required | CK 6 | Planned run time for the order quantity |
| `status` | `character varying(12)` | Required, default `'BEKLIYOR'` | CK 8 | `BEKLIYOR` waiting, `DEVAM_EDIYOR` in progress, `TAMAMLANDI` done |
| `operator_id` | `integer` | Nullable | FK 2 | Employee performing the step |

1. `PRIMARY KEY (production_order_operation_id)`
2. `FOREIGN KEY (operator_id) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (production_order_id, routing_id) REFERENCES production.production_order(production_order_id, routing_id) ON DELETE CASCADE`
4. `FOREIGN KEY (routing_operation_id, routing_id) REFERENCES engineering.routing_operation(routing_operation_id, routing_id)`
5. `UNIQUE (production_order_id, routing_operation_id)`
6. `CHECK (((planned_run_minutes >= (0)::numeric) AND (planned_run_minutes <> 'NaN'::numeric)))`
7. `CHECK (((planned_setup_minutes >= (0)::numeric) AND (planned_setup_minutes <> 'NaN'::numeric)))`
8. `CHECK (((status)::text = ANY ((ARRAY['BEKLIYOR'::character varying, 'DEVAM_EDIYOR'::character varying, 'TAMAMLANDI'::character varying])::text[])))`

## `production.material_issue`

Component quantity issued from a stock location to a production order. Posts one `PROD_ISSUE` ledger movement.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `material_issue_id` | `integer` | Required, generated identity | PK 1, UQ 5 | Surrogate issue identifier |
| `production_order_id` | `integer` | Required | FK 4 | Production order consuming the material |
| `component_item_id` | `integer` | Required | FK 4, UQ 5 | Component issued; must be a component of that order |
| `location_id` | `integer` | Required | FK 3 | Stock location the material leaves |
| `quantity` | `numeric(12,3)` | Required | CK 6 | Issued quantity in the item base unit |
| `issued_by` | `integer` | Required | FK 2 | Employee issuing the material; recorded on the movement |
| `issued_at` | `timestamp without time zone` | Required | — | Issue timestamp; its date is the ledger business date |

1. `PRIMARY KEY (material_issue_id)`
2. `FOREIGN KEY (issued_by) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (location_id) REFERENCES inventory.stock_location(location_id)`
4. `FOREIGN KEY (production_order_id, component_item_id) REFERENCES production.production_order_component(production_order_id, component_item_id)`
5. `UNIQUE (material_issue_id, component_item_id)`
6. `CHECK (((quantity > (0)::numeric) AND (quantity <> 'NaN'::numeric)))`

Rules enforced by triggers:

- `trg_keep_material_issue`: Posted issues cannot be changed or deleted.
- `trg_post_material_issue`: Only released or in-progress orders accept issues, cumulative issues cannot exceed the required quantity, and the issue posts one `PROD_ISSUE` movement.

## `production.production_receipt`

Finished quantity received from a production order into a stock location. Posts one `PROD_RECEIPT` ledger movement.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_receipt_id` | `integer` | Required, generated identity | PK 1 | Surrogate receipt identifier |
| `production_order_id` | `integer` | Required | FK 4 | Production order that produced the goods |
| `location_id` | `integer` | Required | FK 3 | Stock location receiving the goods |
| `quantity` | `numeric(12,3)` | Required | CK 6 | Received quantity in the item base unit |
| `received_by` | `integer` | Required | FK 5 | Employee receiving the goods; recorded on the movement |
| `inspected_by` | `integer` | Nullable | FK 2 | Quality inspector |
| `received_at` | `timestamp without time zone` | Required | — | Receipt timestamp; its date is the ledger business date |
| `notes` | `text` | Nullable | — | Free-text remarks |

1. `PRIMARY KEY (production_receipt_id)`
2. `FOREIGN KEY (inspected_by) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (location_id) REFERENCES inventory.stock_location(location_id)`
4. `FOREIGN KEY (production_order_id) REFERENCES production.production_order(production_order_id)`
5. `FOREIGN KEY (received_by) REFERENCES public.employee(employee_id)`
6. `CHECK (((quantity > (0)::numeric) AND (quantity <> 'NaN'::numeric)))`

Rules enforced by triggers:

- `trg_keep_production_receipt`: Posted receipts cannot be changed or deleted.
- `trg_post_production_receipt`: Only started orders accept receipts, the receipt cannot precede the actual start, cumulative receipts cannot exceed the planned quantity, and the receipt posts one `PROD_RECEIPT` movement.

## `production.item_unit`

Individually tracked physical unit of a serialized item, tied to the order that made it.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `item_unit_id` | `integer` | Required, generated identity | PK 1 | Surrogate unit identifier |
| `item_id` | `integer` | Required | FK 2, UQ 3 | Serialized item; must match the producing order |
| `production_order_id` | `integer` | Required | FK 2 | Order that produced the unit |
| `serial_number` | `character varying(40)` | Required | UQ 3 | Serial number, unique per item |
| `status` | `character varying(12)` | Required, default `'STOKTA'` | CK 4 | `STOKTA` in stock, `SEVK_EDILDI` shipped, `HURDA` scrapped |

1. `PRIMARY KEY (item_unit_id)`
2. `FOREIGN KEY (production_order_id, item_id) REFERENCES production.production_order(production_order_id, item_id)`
3. `UNIQUE (item_id, serial_number)`
4. `CHECK (((status)::text = ANY ((ARRAY['STOKTA'::character varying, 'SEVK_EDILDI'::character varying, 'HURDA'::character varying])::text[])))`

Rules enforced by triggers:

- `trg_guard_item_unit`: The number of serial numbers cannot exceed the quantity received from the order.
- `trg_item_unit_serialized`: Units can only be recorded for serialized items.

## `inventory.inventory_movement`

Shared append-only stock ledger owned by O2C. P2M adds two movement types and their source columns. Each movement has exactly one source document.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `movement_id` | `integer` | Required, generated identity | PK 1 | Surrogate movement identifier |
| `movement_no` | `character varying(32)` | Required | UQ 10 | Unique movement reference (`GR:`, `MI:`, `PR:` prefixes for posted documents) |
| `movement_type` | `character varying(12)` | Required | CK 13, CK 14 | `RECEIPT`, `SALE_ISSUE` (O2C) and `PROD_RECEIPT`, `PROD_ISSUE` (P2M) |
| `location_id` | `integer` | Required | FK 3 | Location affected by the movement |
| `item_id` | `integer` | Required | FK 2, FK 4, FK 5 | Stock item affected by the movement |
| `order_line_id` | `integer` | Nullable | FK 5, CK 13 | Sales line for a sales issue |
| `receipt_line_id` | `integer` | Nullable | FK 7, UQ 12, CK 13 | Goods-receipt line for a purchase receipt |
| `moved_on` | `date` | Required | — | Effective stock business date |
| `quantity` | `numeric(12,3)` | Required | CK 15 | Positive magnitude in the item unit; direction comes from the type |
| `recorded_by` | `integer` | Required | FK 8 | Employee who recorded the movement |
| `material_issue_id` | `integer` | Nullable | FK 4, UQ 9, CK 13 | P2M material issue for a `PROD_ISSUE` (added by P2M) |
| `production_receipt_id` | `integer` | Nullable | FK 6, UQ 11, CK 13 | P2M production receipt for a `PROD_RECEIPT` (added by P2M) |

1. `PRIMARY KEY (movement_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (location_id) REFERENCES inventory.stock_location(location_id)`
4. `FOREIGN KEY (material_issue_id, item_id) REFERENCES production.material_issue(material_issue_id, component_item_id)`
5. `FOREIGN KEY (order_line_id, item_id) REFERENCES sales.sales_order_line(order_line_id, item_id)`
6. `FOREIGN KEY (production_receipt_id) REFERENCES production.production_receipt(production_receipt_id)`
7. `FOREIGN KEY (receipt_line_id) REFERENCES inventory.goods_receipt_line(receipt_line_id)`
8. `FOREIGN KEY (recorded_by) REFERENCES public.employee(employee_id)`
9. `UNIQUE (material_issue_id)`
10. `UNIQUE (movement_no)`
11. `UNIQUE (production_receipt_id)`
12. `UNIQUE (receipt_line_id)`
13. `CHECK (((((movement_type)::text = 'RECEIPT'::text) AND (receipt_line_id IS NOT NULL) AND (num_nonnulls(order_line_id, material_issue_id, production_receipt_id) = 0)) OR (((movement_type)::text = 'SALE_ISSUE'::text) AND (order_line_id IS NOT NULL) AND (num_nonnulls(receipt_line_id, material_issue_id, production_receipt_id) = 0)) OR (((movement_type)::text = 'PROD_ISSUE'::text) AND (material_issue_id IS NOT NULL) AND (num_nonnulls(order_line_id, receipt_line_id, production_receipt_id) = 0)) OR (((movement_type)::text = 'PROD_RECEIPT'::text) AND (production_receipt_id IS NOT NULL) AND (num_nonnulls(order_line_id, receipt_line_id, material_issue_id) = 0))))`
14. `CHECK (((movement_type)::text = ANY ((ARRAY['RECEIPT'::character varying, 'SALE_ISSUE'::character varying, 'PROD_RECEIPT'::character varying, 'PROD_ISSUE'::character varying])::text[])))`
15. `CHECK (((quantity > (0)::numeric) AND (quantity <> 'NaN'::numeric)))`

Rules enforced by triggers:

- `trg_apply_movement`: O2C: validates receipt and sales-issue sources, serializes postings per location and item, and rejects any outbound movement that makes the end-of-day balance negative on any date.
- `trg_keep_stock_movement`: O2C: posted movements cannot be changed or deleted.
- `trg_prevent_movement_truncate`: O2C: the ledger cannot be truncated.
- `trg_validate_production_movement`: P2M: a production movement must match its source issue or receipt (location, item, date, quantity, employee).

## `planning.material_requirement_net`

Net component requirement per plan: total gross demand of all plan lines less the stock snapshot taken once for the plan.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `production_plan_id` | `integer` | Derived | — | Plan |
| `component_item_id` | `integer` | Derived | — | Component item |
| `gross_requirement` | `numeric` | Derived | — | Sum of gross requirements over the plan's lines |
| `on_hand_quantity` | `numeric` | Derived | — | Plan stock snapshot, zero when none was taken |
| `net_requirement` | `numeric` | Derived | — | Gross requirement less on-hand, never below zero |
| `first_needed_by` | `date` | Derived | — | Earliest date the component is needed |

## `inventory.stock_balance`

Read-only stock on hand per location and item (O2C view; now includes production movements).

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `location_id` | `integer` | Derived | — | Location in the movement ledger |
| `item_id` | `integer` | Derived | — | Item in the movement ledger |
| `quantity_on_hand` | `numeric` | Derived | — | Inbound (`RECEIPT`, `PROD_RECEIPT`) less outbound (`SALE_ISSUE`, `PROD_ISSUE`) quantities |

## Ledger Direction

`inventory.signed_quantity(movement_type, quantity)` (defined in `o2c-database.sql`) returns the quantity for inbound types `RECEIPT` and `PROD_RECEIPT` and the negated quantity for every other type. `inventory.stock_balance` and the negative-stock check in `inventory.apply_movement` both use it, so receipts, sales issues, material issues and production receipts share one balance per location and item.

## Transaction Rules

- BOMs and routings belong to manufacturable items; BOM components are consumable. A BOM may never contain its own item directly or indirectly.
- A plan line stays inside its plan period. When it is pegged to an O2C sales line it plans the same item, the order is confirmed and dated on or before the planned start, and the quantity planned across all plan lines does not exceed the ordered quantity.
- MRP stores gross requirements per plan line and one stock snapshot per plan. `planning.material_requirement_net` nets the total demand against that snapshot once.
- A production order uses the plan line's item, an approved BOM effective on its planned start and an approved routing. Its components and operations come only from that BOM and routing.
- Material may be issued to released or in-progress orders, only for the order's components and up to the required quantity. Each issue posts a `PROD_ISSUE` movement; the ledger rejects it if stock at the location would be negative at the end of any date.
- Finished goods may be received from in-progress or completed orders, not before the actual start and up to the planned quantity. Each receipt posts a `PROD_RECEIPT` movement that O2C can then ship and invoice.
- Serial numbers of a serialized item cannot outnumber the units received. Posted issues, receipts and movements cannot be changed or deleted.
