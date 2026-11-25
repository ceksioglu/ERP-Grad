-- Plan to Manufacture (P2M)
--
-- P2M is built on the shared database, not on its own copy of the master data:
--   * masters      : public.department / employee / customer / supplier / item   (db_init.sql)
--   * customer demand: sales.sales_order / sales_order_line                     (o2c-database.sql)
--   * stock        : inventory.stock_location and the inventory.inventory_movement ledger (o2c-database.sql)
-- Material issues and finished-goods receipts post PROD_ISSUE / PROD_RECEIPT movements to the
-- same ledger that O2C sells from, so a manufactured item can be shipped and invoiced by O2C.
--
-- Install order on a fresh database:
--   db_init.sql -> o2c-database.sql -> p2m-database.sql
--   then any of: o2c-demo.sql, o2c-business-cases.sql, p2m-business-cases.sql

SET client_encoding = 'UTF8';

BEGIN;

CREATE SCHEMA engineering;
CREATE SCHEMA planning;
CREATE SCHEMA production;

-- 1. ENGINEERING ----------------------------------------------------------------

-- Bill of materials header: one revision of the recipe for a manufacturable item
CREATE TABLE engineering.bom (
    bom_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        INTEGER NOT NULL REFERENCES public.item (item_id),
    revision       VARCHAR(10) NOT NULL,
    status         VARCHAR(10) NOT NULL DEFAULT 'TASLAK' CHECK (status IN ('TASLAK', 'ONAYLI', 'GECERSIZ')),
    base_quantity  NUMERIC(12,3) NOT NULL DEFAULT 1 CHECK (base_quantity > 0 AND base_quantity <> 'NaN'::numeric),
    effective_from DATE NOT NULL,
    effective_to   DATE,
    approved_by    INTEGER REFERENCES public.employee (employee_id),
    UNIQUE (item_id, revision),
    UNIQUE (bom_id, item_id),     -- target of composite FK from production_order
    CONSTRAINT bom_dates_ok CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT bom_approved_has_approver CHECK (status <> 'ONAYLI' OR approved_by IS NOT NULL)
);

CREATE TABLE engineering.bom_line (
    bom_line_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_id            INTEGER NOT NULL REFERENCES engineering.bom (bom_id) ON DELETE CASCADE,
    line_no           INTEGER NOT NULL CHECK (line_no > 0),
    component_item_id INTEGER NOT NULL REFERENCES public.item (item_id),
    quantity_per      NUMERIC(14,4) NOT NULL CHECK (quantity_per > 0 AND quantity_per <> 'NaN'::numeric),  -- per bom.base_quantity
    scrap_percent     NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (scrap_percent >= 0 AND scrap_percent < 100),
    UNIQUE (bom_id, line_no),
    UNIQUE (bom_id, component_item_id)    -- target of composite FK from production_order_component
);

CREATE TABLE engineering.work_center (
    work_center_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    work_center_code       VARCHAR(15)  NOT NULL UNIQUE,
    work_center_name       VARCHAR(100) NOT NULL,
    department_id          INTEGER NOT NULL REFERENCES public.department (department_id),
    capacity_hours_per_day NUMERIC(5,2) NOT NULL CHECK (capacity_hours_per_day > 0 AND capacity_hours_per_day <= 24),
    hourly_rate            NUMERIC(10,2) CHECK (hourly_rate >= 0 AND hourly_rate <> 'NaN'::numeric),
    is_active              BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE engineering.routing (
    routing_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id    INTEGER NOT NULL REFERENCES public.item (item_id),
    revision   VARCHAR(10) NOT NULL,
    status     VARCHAR(10) NOT NULL DEFAULT 'TASLAK' CHECK (status IN ('TASLAK', 'ONAYLI', 'GECERSIZ')),
    UNIQUE (item_id, revision),
    UNIQUE (routing_id, item_id)    -- target of composite FK from production_order
);

CREATE TABLE engineering.routing_operation (
    routing_operation_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    routing_id            INTEGER NOT NULL REFERENCES engineering.routing (routing_id) ON DELETE CASCADE,
    operation_no          INTEGER NOT NULL CHECK (operation_no > 0),
    operation_name        VARCHAR(100) NOT NULL,
    work_center_id        INTEGER NOT NULL REFERENCES engineering.work_center (work_center_id),
    setup_minutes         NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (setup_minutes >= 0 AND setup_minutes <> 'NaN'::numeric),
    run_minutes_per_unit  NUMERIC(8,2) NOT NULL CHECK (run_minutes_per_unit >= 0 AND run_minutes_per_unit <> 'NaN'::numeric),
    UNIQUE (routing_id, operation_no),
    UNIQUE (routing_operation_id, routing_id)    -- target of composite FK from production_order_operation
);

-- 2. PLANNING -------------------------------------------------------------------

CREATE TABLE planning.production_plan (
    production_plan_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_no            VARCHAR(20) NOT NULL UNIQUE,
    plan_name          VARCHAR(150) NOT NULL,
    period_start       DATE NOT NULL,
    period_end         DATE NOT NULL,
    status             VARCHAR(12) NOT NULL DEFAULT 'TASLAK' CHECK (status IN ('TASLAK', 'ONAYLANDI', 'KAPANDI')),
    created_by         INTEGER NOT NULL REFERENCES public.employee (employee_id),
    approved_by        INTEGER REFERENCES public.employee (employee_id),
    created_at         TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT plan_period_ok CHECK (period_end >= period_start),
    CONSTRAINT plan_approved_has_approver CHECK (status = 'TASLAK' OR approved_by IS NOT NULL)
);

-- sales_order_line_id NULL = dependent / stock demand (e.g. table legs needed for tables).
-- When set, the line must plan the same item as the O2C sales order line (composite FK).
CREATE TABLE planning.production_plan_line (
    production_plan_line_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_plan_id      INTEGER NOT NULL REFERENCES planning.production_plan (production_plan_id) ON DELETE CASCADE,
    line_no                 INTEGER NOT NULL CHECK (line_no > 0),
    item_id                 INTEGER NOT NULL REFERENCES public.item (item_id),
    sales_order_line_id     INTEGER,
    planned_quantity        NUMERIC(12,3) NOT NULL CHECK (planned_quantity > 0 AND planned_quantity <> 'NaN'::numeric),
    planned_start_date      DATE NOT NULL,
    planned_finish_date     DATE NOT NULL,
    UNIQUE (production_plan_id, line_no),
    UNIQUE (production_plan_line_id, item_id),    -- target of composite FK from production_order
    CONSTRAINT fk_plan_line_sales_order_line FOREIGN KEY (sales_order_line_id, item_id)
        REFERENCES sales.sales_order_line (order_line_id, item_id),
    CONSTRAINT ppl_dates_ok CHECK (planned_finish_date >= planned_start_date)
);

-- MRP gross requirement per plan line and component (BOM explosion incl. scrap)
CREATE TABLE planning.material_requirement (
    material_requirement_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_plan_line_id INTEGER NOT NULL REFERENCES planning.production_plan_line (production_plan_line_id) ON DELETE CASCADE,
    component_item_id       INTEGER NOT NULL REFERENCES public.item (item_id),
    gross_requirement       NUMERIC(14,4) NOT NULL CHECK (gross_requirement >= 0 AND gross_requirement <> 'NaN'::numeric),
    needed_by_date          DATE NOT NULL,
    UNIQUE (production_plan_line_id, component_item_id)
);

-- On-hand stock captured ONCE per plan and item when the plan is run. Netting happens at plan
-- level (view below) so the same stock is never subtracted from several plan lines.
CREATE TABLE planning.plan_stock_snapshot (
    production_plan_id INTEGER NOT NULL REFERENCES planning.production_plan (production_plan_id) ON DELETE CASCADE,
    item_id            INTEGER NOT NULL REFERENCES public.item (item_id),
    on_hand_quantity   NUMERIC(14,4) NOT NULL CHECK (on_hand_quantity >= 0 AND on_hand_quantity <> 'NaN'::numeric),
    PRIMARY KEY (production_plan_id, item_id)
);

-- 3. PRODUCTION -----------------------------------------------------------------

CREATE TABLE production.production_order (
    production_order_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no                VARCHAR(20) NOT NULL UNIQUE,
    production_plan_line_id INTEGER NOT NULL,
    item_id                 INTEGER NOT NULL REFERENCES public.item (item_id),
    bom_id                  INTEGER NOT NULL,
    routing_id              INTEGER NOT NULL,
    planned_quantity        NUMERIC(12,3) NOT NULL CHECK (planned_quantity > 0 AND planned_quantity <> 'NaN'::numeric),
    status                  VARCHAR(12) NOT NULL DEFAULT 'PLANLANDI'
                            CHECK (status IN ('PLANLANDI', 'SERBEST', 'DEVAM_EDIYOR', 'TAMAMLANDI', 'IPTAL')),
    planned_start_date      DATE NOT NULL,
    planned_finish_date     DATE NOT NULL,
    actual_start_date       DATE,
    actual_finish_date      DATE,
    responsible_employee_id INTEGER NOT NULL REFERENCES public.employee (employee_id),
    UNIQUE (production_order_id, item_id),        -- target of composite FK from item_unit
    UNIQUE (production_order_id, bom_id),         -- target of composite FK from production_order_component
    UNIQUE (production_order_id, routing_id),     -- target of composite FK from production_order_operation
    -- the order's item must match the plan line's item, the BOM's item and the routing's item
    CONSTRAINT fk_po_plan_line FOREIGN KEY (production_plan_line_id, item_id)
        REFERENCES planning.production_plan_line (production_plan_line_id, item_id),
    CONSTRAINT fk_po_bom FOREIGN KEY (bom_id, item_id)
        REFERENCES engineering.bom (bom_id, item_id),
    CONSTRAINT fk_po_routing FOREIGN KEY (routing_id, item_id)
        REFERENCES engineering.routing (routing_id, item_id),
    CONSTRAINT po_planned_dates_ok CHECK (planned_finish_date >= planned_start_date),
    CONSTRAINT po_actual_dates_ok CHECK (actual_finish_date IS NULL
        OR (actual_start_date IS NOT NULL AND actual_finish_date >= actual_start_date)),
    CONSTRAINT po_started_has_start CHECK (status NOT IN ('DEVAM_EDIYOR', 'TAMAMLANDI') OR actual_start_date IS NOT NULL),
    CONSTRAINT po_completed_has_finish CHECK (status <> 'TAMAMLANDI' OR actual_finish_date IS NOT NULL)
);

-- Components required by an order (snapshot of the BOM explosion at release).
-- Each component must be a line of the order's own BOM.
CREATE TABLE production.production_order_component (
    production_order_component_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id           INTEGER NOT NULL,
    bom_id                        INTEGER NOT NULL,
    component_item_id             INTEGER NOT NULL,
    required_quantity             NUMERIC(12,3) NOT NULL CHECK (required_quantity > 0 AND required_quantity <> 'NaN'::numeric),
    UNIQUE (production_order_id, component_item_id),
    CONSTRAINT fk_poc_order_bom FOREIGN KEY (production_order_id, bom_id)
        REFERENCES production.production_order (production_order_id, bom_id) ON DELETE CASCADE,
    CONSTRAINT fk_poc_bom_line FOREIGN KEY (bom_id, component_item_id)
        REFERENCES engineering.bom_line (bom_id, component_item_id)
);

-- Each operation must come from the order's own routing.
CREATE TABLE production.production_order_operation (
    production_order_operation_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id           INTEGER NOT NULL,
    routing_id                    INTEGER NOT NULL,
    routing_operation_id          INTEGER NOT NULL,
    planned_setup_minutes         NUMERIC(10,2) NOT NULL CHECK (planned_setup_minutes >= 0 AND planned_setup_minutes <> 'NaN'::numeric),
    planned_run_minutes           NUMERIC(10,2) NOT NULL CHECK (planned_run_minutes >= 0 AND planned_run_minutes <> 'NaN'::numeric),
    status                        VARCHAR(12) NOT NULL DEFAULT 'BEKLIYOR'
                                  CHECK (status IN ('BEKLIYOR', 'DEVAM_EDIYOR', 'TAMAMLANDI')),
    operator_id                   INTEGER REFERENCES public.employee (employee_id),
    UNIQUE (production_order_id, routing_operation_id),
    CONSTRAINT fk_poo_order_routing FOREIGN KEY (production_order_id, routing_id)
        REFERENCES production.production_order (production_order_id, routing_id) ON DELETE CASCADE,
    CONSTRAINT fk_poo_routing_operation FOREIGN KEY (routing_operation_id, routing_id)
        REFERENCES engineering.routing_operation (routing_operation_id, routing_id)
);

-- Material issued from a stock location to an order; must be a component of THAT order.
-- Posts one PROD_ISSUE movement to the shared ledger. Quantity uses the ledger precision.
CREATE TABLE production.material_issue (
    material_issue_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id INTEGER NOT NULL,
    component_item_id   INTEGER NOT NULL,
    location_id         INTEGER NOT NULL REFERENCES inventory.stock_location (location_id),
    quantity            NUMERIC(12,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    issued_by           INTEGER NOT NULL REFERENCES public.employee (employee_id),
    issued_at           TIMESTAMP NOT NULL,
    UNIQUE (material_issue_id, component_item_id),    -- target of composite FK from inventory_movement
    CONSTRAINT fk_issue_order_component FOREIGN KEY (production_order_id, component_item_id)
        REFERENCES production.production_order_component (production_order_id, component_item_id)
);

-- Finished quantity received into a stock location from an order. Posts one PROD_RECEIPT movement.
CREATE TABLE production.production_receipt (
    production_receipt_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id   INTEGER NOT NULL REFERENCES production.production_order (production_order_id),
    location_id           INTEGER NOT NULL REFERENCES inventory.stock_location (location_id),
    quantity              NUMERIC(12,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    received_by           INTEGER NOT NULL REFERENCES public.employee (employee_id),
    inspected_by          INTEGER REFERENCES public.employee (employee_id),
    received_at           TIMESTAMP NOT NULL,
    notes                 TEXT
);

-- Individual physical units: ONLY for serialized items, tied to the order that made them
CREATE TABLE production.item_unit (
    item_unit_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id             INTEGER NOT NULL,
    production_order_id INTEGER NOT NULL,
    serial_number       VARCHAR(40) NOT NULL,
    status              VARCHAR(12) NOT NULL DEFAULT 'STOKTA' CHECK (status IN ('STOKTA', 'SEVK_EDILDI', 'HURDA')),
    UNIQUE (item_id, serial_number),
    CONSTRAINT fk_unit_order FOREIGN KEY (production_order_id, item_id)
        REFERENCES production.production_order (production_order_id, item_id)
);

-- 4. SHARED LEDGER EXTENSION ---------------------------------------------------------
-- Adds the two production movement types to the O2C ledger. Every movement still has exactly
-- one source document; the direction comes from inventory.signed_quantity (o2c-database.sql).

ALTER TABLE inventory.inventory_movement
    ADD COLUMN material_issue_id     INTEGER UNIQUE,
    ADD COLUMN production_receipt_id INTEGER UNIQUE
        REFERENCES production.production_receipt (production_receipt_id),
    ADD CONSTRAINT fk_movement_material_issue FOREIGN KEY (material_issue_id, item_id)
        REFERENCES production.material_issue (material_issue_id, component_item_id),
    DROP CONSTRAINT inventory_movement_type_check,
    DROP CONSTRAINT inventory_movement_source_check,
    ADD CONSTRAINT inventory_movement_type_check
        CHECK (movement_type IN ('RECEIPT', 'SALE_ISSUE', 'PROD_RECEIPT', 'PROD_ISSUE')),
    ADD CONSTRAINT inventory_movement_source_check CHECK (
           (movement_type = 'RECEIPT'      AND receipt_line_id IS NOT NULL
                AND num_nonnulls(order_line_id, material_issue_id, production_receipt_id) = 0)
        OR (movement_type = 'SALE_ISSUE'   AND order_line_id IS NOT NULL
                AND num_nonnulls(receipt_line_id, material_issue_id, production_receipt_id) = 0)
        OR (movement_type = 'PROD_ISSUE'   AND material_issue_id IS NOT NULL
                AND num_nonnulls(order_line_id, receipt_line_id, production_receipt_id) = 0)
        OR (movement_type = 'PROD_RECEIPT' AND production_receipt_id IS NOT NULL
                AND num_nonnulls(order_line_id, receipt_line_id, material_issue_id) = 0));

-- 5. BUSINESS-RULE TRIGGERS -------------------------------------------------------------

-- Generic: the item referenced by NEW.<TG_ARGV[0]> must have role flag TG_ARGV[1]
CREATE FUNCTION engineering.assert_item_role() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_item_id INTEGER;
    v_ok      BOOLEAN;
BEGIN
    v_item_id := (to_jsonb(NEW) ->> TG_ARGV[0])::INTEGER;
    EXECUTE format('SELECT %I FROM public.item WHERE item_id = $1', TG_ARGV[1])
        INTO v_ok USING v_item_id;
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'Item % does not have the required role "%" (table %.%)',
            v_item_id, TG_ARGV[1], TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_bom_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON engineering.bom
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_item_role('item_id', 'is_manufacturable');
CREATE TRIGGER trg_bom_line_consumable
    BEFORE INSERT OR UPDATE OF component_item_id ON engineering.bom_line
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_item_role('component_item_id', 'is_consumable');
CREATE TRIGGER trg_routing_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON engineering.routing
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_item_role('item_id', 'is_manufacturable');
CREATE TRIGGER trg_plan_line_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON planning.production_plan_line
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_item_role('item_id', 'is_manufacturable');
CREATE TRIGGER trg_po_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON production.production_order
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_item_role('item_id', 'is_manufacturable');
CREATE TRIGGER trg_item_unit_serialized
    BEFORE INSERT OR UPDATE OF item_id ON production.item_unit
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_item_role('item_id', 'is_serialized');

-- 5.1 BOM structure must stay acyclic (no item may be a direct or indirect component of itself)
CREATE FUNCTION engineering.assert_bom_acyclic() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_parent INTEGER;
BEGIN
    -- serialize BOM structure changes so two concurrent edits cannot close a loop together
    PERFORM pg_advisory_xact_lock(hashtext('engineering.bom_structure'));
    SELECT item_id INTO v_parent FROM engineering.bom WHERE bom_id = NEW.bom_id;
    IF EXISTS (
        WITH RECURSIVE reachable(item_id) AS (
            SELECT NEW.component_item_id
            UNION
            SELECT line.component_item_id
            FROM reachable
            JOIN engineering.bom AS bom ON bom.item_id = reachable.item_id
            JOIN engineering.bom_line AS line ON line.bom_id = bom.bom_id
            WHERE line.bom_line_id IS DISTINCT FROM NEW.bom_line_id
        )
        SELECT 1 FROM reachable WHERE item_id = v_parent
    ) THEN
        RAISE EXCEPTION 'BOM line would make item % a component of itself', v_parent
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_bom_line_acyclic
    BEFORE INSERT OR UPDATE OF bom_id, component_item_id ON engineering.bom_line
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_bom_acyclic();

-- 5.2 Plan lines: inside the plan period; linked demand must be a confirmed O2C order placed
--     on or before the planned start, and may not be planned beyond the ordered quantity.
CREATE FUNCTION planning.guard_plan_line() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_period_start DATE;
    v_period_end   DATE;
    v_order_id     INTEGER;
    v_ordered      NUMERIC;
    v_planned      NUMERIC;
BEGIN
    SELECT period_start, period_end INTO v_period_start, v_period_end
    FROM planning.production_plan WHERE production_plan_id = NEW.production_plan_id
    FOR SHARE;
    IF NEW.planned_start_date < v_period_start OR NEW.planned_finish_date > v_period_end THEN
        RAISE EXCEPTION 'Plan line dates must fall within the plan period % - %', v_period_start, v_period_end
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.sales_order_line_id IS NOT NULL THEN
        SELECT order_id, quantity INTO v_order_id, v_ordered
        FROM sales.sales_order_line
        WHERE order_line_id = NEW.sales_order_line_id AND item_id = NEW.item_id
        FOR NO KEY UPDATE;
        IF FOUND THEN
            -- O2C helper: requires a CONFIRMED order dated on or before the event date
            PERFORM sales.lock_confirmed_order(v_order_id, NEW.planned_start_date);
            SELECT COALESCE(SUM(planned_quantity), 0) INTO v_planned
            FROM planning.production_plan_line
            WHERE sales_order_line_id = NEW.sales_order_line_id
              AND production_plan_line_id <> NEW.production_plan_line_id;
            IF v_planned + NEW.planned_quantity > v_ordered THEN
                RAISE EXCEPTION 'Planned quantity % exceeds the open sales order line quantity %',
                    v_planned + NEW.planned_quantity, v_ordered USING ERRCODE = 'check_violation';
            END IF;
        END IF;   -- a missing line or an item mismatch is reported by the FK
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_guard_plan_line
    BEFORE INSERT OR UPDATE ON planning.production_plan_line
    FOR EACH ROW EXECUTE FUNCTION planning.guard_plan_line();

CREATE FUNCTION planning.guard_plan_period() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM planning.production_plan_line
               WHERE production_plan_id = NEW.production_plan_id
                 AND (planned_start_date < NEW.period_start OR planned_finish_date > NEW.period_end)) THEN
        RAISE EXCEPTION 'Plan period cannot exclude existing plan lines' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_guard_plan_period
    BEFORE UPDATE OF period_start, period_end ON planning.production_plan
    FOR EACH ROW EXECUTE FUNCTION planning.guard_plan_period();

-- 5.3 Production orders: approved BOM effective on the start date, approved routing, and the
--     non-cancelled orders of a plan line may not exceed the planned quantity.
CREATE FUNCTION production.guard_production_order() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_line_quantity NUMERIC;
    v_ordered       NUMERIC;
BEGIN
    IF TG_OP = 'INSERT' OR (NEW.bom_id, NEW.routing_id, NEW.planned_start_date)
                           IS DISTINCT FROM (OLD.bom_id, OLD.routing_id, OLD.planned_start_date) THEN
        IF NOT EXISTS (SELECT 1 FROM engineering.bom
                       WHERE bom_id = NEW.bom_id AND status = 'ONAYLI'
                         AND NEW.planned_start_date >= effective_from
                         AND (effective_to IS NULL OR NEW.planned_start_date <= effective_to)) THEN
            RAISE EXCEPTION 'Production order needs an approved BOM effective on %', NEW.planned_start_date
                USING ERRCODE = 'check_violation';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM engineering.routing WHERE routing_id = NEW.routing_id AND status = 'ONAYLI') THEN
            RAISE EXCEPTION 'Production order needs an approved routing' USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF NEW.status <> 'IPTAL' THEN
        SELECT planned_quantity INTO v_line_quantity
        FROM planning.production_plan_line WHERE production_plan_line_id = NEW.production_plan_line_id
        FOR NO KEY UPDATE;
        SELECT COALESCE(SUM(planned_quantity), 0) INTO v_ordered
        FROM production.production_order
        WHERE production_plan_line_id = NEW.production_plan_line_id
          AND status <> 'IPTAL' AND production_order_id <> NEW.production_order_id;
        IF v_ordered + NEW.planned_quantity > v_line_quantity THEN
            RAISE EXCEPTION 'Production orders (%) exceed the plan line quantity %',
                v_ordered + NEW.planned_quantity, v_line_quantity USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_guard_production_order
    BEFORE INSERT OR UPDATE OF production_plan_line_id, bom_id, routing_id, planned_start_date,
                               planned_quantity, status
    ON production.production_order
    FOR EACH ROW EXECUTE FUNCTION production.guard_production_order();

-- 5.4 Material issue: released / in-progress order only, cumulative issue <= required quantity,
--     then post a PROD_ISSUE movement (the ledger rejects it if stock would go negative).
CREATE FUNCTION production.post_material_issue() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_status   TEXT;
    v_required NUMERIC;
    v_issued   NUMERIC;
BEGIN
    SELECT status INTO v_status FROM production.production_order
    WHERE production_order_id = NEW.production_order_id FOR NO KEY UPDATE;
    IF v_status NOT IN ('SERBEST', 'DEVAM_EDIYOR') THEN
        RAISE EXCEPTION 'Material can only be issued to a released or in-progress production order (status %)', v_status
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT required_quantity INTO v_required FROM production.production_order_component
    WHERE production_order_id = NEW.production_order_id AND component_item_id = NEW.component_item_id;
    SELECT SUM(quantity) INTO v_issued FROM production.material_issue
    WHERE production_order_id = NEW.production_order_id AND component_item_id = NEW.component_item_id;
    IF v_issued > v_required THEN
        RAISE EXCEPTION 'Material issues (%) exceed the required component quantity %', v_issued, v_required
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO inventory.inventory_movement
        (movement_no, movement_type, location_id, item_id, material_issue_id, moved_on, quantity, recorded_by)
    VALUES ('MI:' || NEW.material_issue_id, 'PROD_ISSUE', NEW.location_id, NEW.component_item_id,
            NEW.material_issue_id, NEW.issued_at::date, NEW.quantity, NEW.issued_by);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_post_material_issue
    AFTER INSERT ON production.material_issue
    FOR EACH ROW EXECUTE FUNCTION production.post_material_issue();

-- 5.5 Production receipt: started order only, not before the actual start,
--     cumulative receipts <= planned quantity, then post a PROD_RECEIPT movement.
CREATE FUNCTION production.post_production_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_order    production.production_order%ROWTYPE;
    v_received NUMERIC;
BEGIN
    SELECT * INTO v_order FROM production.production_order
    WHERE production_order_id = NEW.production_order_id FOR NO KEY UPDATE;
    IF v_order.status NOT IN ('DEVAM_EDIYOR', 'TAMAMLANDI') THEN
        RAISE EXCEPTION 'Finished goods can only be received from a started production order (status %)', v_order.status
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.received_at::date < v_order.actual_start_date THEN
        RAISE EXCEPTION 'Production receipt cannot precede the order start date %', v_order.actual_start_date
            USING ERRCODE = 'check_violation';
    END IF;
    SELECT SUM(quantity) INTO v_received FROM production.production_receipt
    WHERE production_order_id = NEW.production_order_id;
    IF v_received > v_order.planned_quantity THEN
        RAISE EXCEPTION 'Received quantity % exceeds the planned quantity %', v_received, v_order.planned_quantity
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO inventory.inventory_movement
        (movement_no, movement_type, location_id, item_id, production_receipt_id, moved_on, quantity, recorded_by)
    VALUES ('PR:' || NEW.production_receipt_id, 'PROD_RECEIPT', NEW.location_id, v_order.item_id,
            NEW.production_receipt_id, NEW.received_at::date, NEW.quantity, NEW.received_by);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_post_production_receipt
    AFTER INSERT ON production.production_receipt
    FOR EACH ROW EXECUTE FUNCTION production.post_production_receipt();

-- 5.6 A production movement must mirror its source document exactly (as O2C does for receipts)
CREATE FUNCTION production.validate_production_movement() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.movement_type = 'PROD_ISSUE' AND NOT EXISTS (
        SELECT 1 FROM production.material_issue AS issue
        WHERE issue.material_issue_id = NEW.material_issue_id
          AND (issue.location_id, issue.component_item_id, issue.issued_at::date, issue.quantity, issue.issued_by)
              = (NEW.location_id, NEW.item_id, NEW.moved_on, NEW.quantity, NEW.recorded_by)
    ) THEN
        RAISE EXCEPTION 'Production issue movement must match its material issue' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.movement_type = 'PROD_RECEIPT' AND NOT EXISTS (
        SELECT 1 FROM production.production_receipt AS receipt
        JOIN production.production_order AS po USING (production_order_id)
        WHERE receipt.production_receipt_id = NEW.production_receipt_id
          AND (receipt.location_id, po.item_id, receipt.received_at::date, receipt.quantity, receipt.received_by)
              = (NEW.location_id, NEW.item_id, NEW.moved_on, NEW.quantity, NEW.recorded_by)
    ) THEN
        RAISE EXCEPTION 'Production receipt movement must match its production receipt' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_validate_production_movement
    AFTER INSERT ON inventory.inventory_movement
    FOR EACH ROW WHEN (NEW.movement_type IN ('PROD_ISSUE', 'PROD_RECEIPT'))
    EXECUTE FUNCTION production.validate_production_movement();

-- 5.7 Serial numbers cannot exceed the quantity received from the order
CREATE FUNCTION production.guard_item_unit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_received NUMERIC;
    v_units    BIGINT;
BEGIN
    PERFORM 1 FROM production.production_order
    WHERE production_order_id = NEW.production_order_id FOR NO KEY UPDATE;
    SELECT COALESCE(SUM(quantity), 0) INTO v_received FROM production.production_receipt
    WHERE production_order_id = NEW.production_order_id;
    SELECT COUNT(*) INTO v_units FROM production.item_unit
    WHERE production_order_id = NEW.production_order_id;
    IF v_units > v_received THEN
        RAISE EXCEPTION 'Serial numbers (%) exceed the quantity received from the production order (%)', v_units, v_received
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_guard_item_unit
    AFTER INSERT OR UPDATE OF production_order_id ON production.item_unit
    FOR EACH ROW EXECUTE FUNCTION production.guard_item_unit();

-- 5.8 Posted stock documents are immutable (same O2C guard as goods receipts and movements)
CREATE TRIGGER trg_keep_material_issue BEFORE UPDATE OR DELETE ON production.material_issue
    FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();
CREATE TRIGGER trg_keep_production_receipt BEFORE UPDATE OR DELETE ON production.production_receipt
    FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();

-- 6. VIEWS ------------------------------------------------------------------------------

-- Net requirement per plan and component: total gross demand less the stock captured once per plan
CREATE VIEW planning.material_requirement_net AS
SELECT line.production_plan_id,
       req.component_item_id,
       SUM(req.gross_requirement)                                        AS gross_requirement,
       COALESCE(snap.on_hand_quantity, 0)                                AS on_hand_quantity,
       GREATEST(SUM(req.gross_requirement) - COALESCE(snap.on_hand_quantity, 0), 0) AS net_requirement,
       MIN(req.needed_by_date)                                           AS first_needed_by
FROM planning.material_requirement AS req
JOIN planning.production_plan_line AS line USING (production_plan_line_id)
LEFT JOIN planning.plan_stock_snapshot AS snap
       ON snap.production_plan_id = line.production_plan_id AND snap.item_id = req.component_item_id
GROUP BY line.production_plan_id, req.component_item_id, snap.on_hand_quantity;

-- 7. INDEXES ON FOREIGN-KEY COLUMNS ----------------------------------------------------

CREATE INDEX ix_bom_line_component       ON engineering.bom_line (component_item_id);
CREATE INDEX ix_work_center_department   ON engineering.work_center (department_id);
CREATE INDEX ix_routing_op_work_center   ON engineering.routing_operation (work_center_id);
CREATE INDEX ix_plan_line_item           ON planning.production_plan_line (item_id);
CREATE INDEX ix_plan_line_so_line        ON planning.production_plan_line (sales_order_line_id);
CREATE INDEX ix_mat_req_component        ON planning.material_requirement (component_item_id);
CREATE INDEX ix_po_plan_line             ON production.production_order (production_plan_line_id);
CREATE INDEX ix_po_bom                   ON production.production_order (bom_id);
CREATE INDEX ix_po_routing               ON production.production_order (routing_id);
CREATE INDEX ix_po_responsible           ON production.production_order (responsible_employee_id);
CREATE INDEX ix_po_component_bom_line    ON production.production_order_component (bom_id, component_item_id);
CREATE INDEX ix_po_operation_routing_op  ON production.production_order_operation (routing_operation_id, routing_id);
CREATE INDEX ix_material_issue_component ON production.material_issue (production_order_id, component_item_id);
CREATE INDEX ix_material_issue_location  ON production.material_issue (location_id);
CREATE INDEX ix_receipt_order            ON production.production_receipt (production_order_id);
CREATE INDEX ix_receipt_location         ON production.production_receipt (location_id);
CREATE INDEX ix_item_unit_order          ON production.item_unit (production_order_id, item_id);

-- 8. SAMPLE DATA -------------------------------------------------------------------------
-- Master rows are resolved by business code (employee_no, item_code, ...), never by id.

-- 8.1 Shared masters P2M needs in addition to db_init.sql (existing rows are left untouched)
INSERT INTO public.employee (employee_no, first_name, last_name, job_title, email, phone, hire_date, monthly_salary) VALUES
('E-0008', 'Burcu', 'Kılıç', 'Üretim Planlama Uzmanı', 'burcu.kilic@anadolumobilya.com.tr', '0530 888 99 00', '2022-04-04', 47000.00),
('E-0009', 'Osman', 'Taş',   'Depo Sorumlusu',         'osman.tas@anadolumobilya.com.tr',   '0531 999 00 11', '2018-08-13', 39000.00)
ON CONFLICT (employee_no) DO NOTHING;

INSERT INTO inventory.stock_location (location_code, location_name, location_type)
VALUES ('DEPO-ANA', 'Ana Depo (Hammadde ve Mamul)', 'WAREHOUSE')
ON CONFLICT (location_code) DO NOTHING;

-- 8.2 Opening stock of purchased materials, via the O2C goods-receipt path (single inbound path)
INSERT INTO inventory.goods_receipt (receipt_no, supplier_id, location_id, received_on, received_by)
SELECT v.receipt_no, s.supplier_id, l.location_id, DATE '2026-10-20', e.employee_id
FROM (VALUES ('GR-2026-0001', 'T-0001'), ('GR-2026-0002', 'T-0002'), ('GR-2026-0003', 'T-0006'),
             ('GR-2026-0004', 'T-0003'), ('GR-2026-0005', 'T-0004'), ('GR-2026-0006', 'T-0005')
) AS v(receipt_no, sup_code)
JOIN public.supplier s        ON s.supplier_code = v.sup_code
JOIN inventory.stock_location l ON l.location_code = 'DEPO-ANA'
JOIN public.employee e        ON e.employee_no = 'E-0009';

INSERT INTO inventory.goods_receipt_line (receipt_id, line_no, item_id, quantity)
SELECT r.receipt_id, 1, i.item_id, v.qty
FROM (VALUES ('GR-2026-0001', 'HM-0001',   2.500), ('GR-2026-0002', 'HM-0002',  30.000),
             ('GR-2026-0003', 'BL-0001', 120.000), ('GR-2026-0004', 'SM-0001',  40.000),
             ('GR-2026-0005', 'SM-0002',  25.000), ('GR-2026-0006', 'BL-0002',   5.000)
) AS v(receipt_no, item_code, qty)
JOIN inventory.goods_receipt r ON r.receipt_no = v.receipt_no
JOIN public.item i             ON i.item_code  = v.item_code;

-- 8.3 Engineering: BOMs, work centers, routings
INSERT INTO engineering.bom (item_id, revision, status, base_quantity, effective_from, approved_by)
SELECT i.item_id, 'A', 'ONAYLI', 1, DATE '2026-01-01', e.employee_id
FROM public.item i
CROSS JOIN public.employee e
WHERE i.item_code IN ('MM-0001', 'MM-0002', 'MM-0003', 'YM-0001', 'BL-0002')
  AND e.employee_no = 'E-0003';

INSERT INTO engineering.bom_line (bom_id, line_no, component_item_id, quantity_per, scrap_percent)
SELECT b.bom_id, v.line_no, c.item_id, v.qty, v.scrap
FROM (VALUES
 ('MM-0001', 1, 'YM-0001', 4.0000, 0.00),
 ('MM-0001', 2, 'HM-0001', 0.0600, 8.00),
 ('MM-0001', 3, 'SM-0001', 0.5000, 0.00),
 ('MM-0001', 4, 'SM-0002', 0.8000, 5.00),
 ('MM-0002', 1, 'BL-0002', 1.0000, 0.00),
 ('MM-0002', 2, 'HM-0001', 0.0120, 8.00),
 ('MM-0002', 3, 'SM-0001', 0.2500, 0.00),
 ('MM-0002', 4, 'SM-0002', 0.3000, 5.00),
 ('MM-0003', 1, 'HM-0002', 1.5000, 5.00),
 ('MM-0003', 2, 'BL-0001', 2.0000, 2.00),
 ('MM-0003', 3, 'SM-0001', 0.5000, 0.00),
 ('MM-0003', 4, 'SM-0002', 0.4000, 5.00),
 ('YM-0001', 1, 'HM-0001', 0.0040, 8.00),
 ('YM-0001', 2, 'SM-0002', 0.0500, 5.00),
 ('BL-0002', 1, 'HM-0002', 0.1000, 5.00)
) AS v(parent_code, line_no, comp_code, qty, scrap)
JOIN public.item p        ON p.item_code = v.parent_code
JOIN engineering.bom b    ON b.item_id = p.item_id AND b.revision = 'A'
JOIN public.item c        ON c.item_code = v.comp_code;

INSERT INTO engineering.work_center (work_center_code, work_center_name, department_id, capacity_hours_per_day, hourly_rate)
SELECT v.code, v.name, d.department_id, v.capacity, v.rate
FROM (VALUES
 ('WC-KESIM',   'Kesim Atölyesi',           'URT', 16.00, 600.00),
 ('WC-ZIMPARA', 'Zımpara Hattı',            'URT',  8.00, 350.00),
 ('WC-MONTAJ',  'Montaj Atölyesi',          'URT', 24.00, 450.00),
 ('WC-BOYA',    'Boya ve Vernik Kabini',    'URT',  8.00, 500.00),
 ('WC-KALITE',  'Kalite Kontrol İstasyonu', 'KKT',  8.00, 400.00)
) AS v(code, name, dept_code, capacity, rate)
JOIN public.department d ON d.department_code = v.dept_code;

INSERT INTO engineering.routing (item_id, revision, status)
SELECT i.item_id, 'A', 'ONAYLI'
FROM public.item i
WHERE i.item_code IN ('MM-0001', 'MM-0002', 'MM-0003', 'YM-0001', 'BL-0002');

INSERT INTO engineering.routing_operation (routing_id, operation_no, operation_name, work_center_id, setup_minutes, run_minutes_per_unit)
SELECT r.routing_id, v.op_no, v.op_name, w.work_center_id, v.setup, v.run
FROM (VALUES
 ('MM-0001', 10, 'Tahta kesimi',            'WC-KESIM',   30, 45),
 ('MM-0001', 20, 'Zımparalama',             'WC-ZIMPARA', 10, 60),
 ('MM-0001', 30, 'Montaj',                  'WC-MONTAJ',  15, 90),
 ('MM-0001', 40, 'Vernik uygulaması',       'WC-BOYA',    20, 75),
 ('MM-0001', 50, 'Final kalite kontrol',    'WC-KALITE',   5, 15),
 ('MM-0002', 10, 'Parça kesimi',            'WC-KESIM',   30, 20),
 ('MM-0002', 20, 'Zımparalama',             'WC-ZIMPARA', 10, 15),
 ('MM-0002', 30, 'Montaj',                  'WC-MONTAJ',  15, 30),
 ('MM-0002', 40, 'Vernik uygulaması',       'WC-BOYA',    20, 20),
 ('MM-0002', 50, 'Final kalite kontrol',    'WC-KALITE',   5,  5),
 ('MM-0003', 10, 'Levha kesimi',            'WC-KESIM',   30, 40),
 ('MM-0003', 20, 'Montaj',                  'WC-MONTAJ',  15, 60),
 ('MM-0003', 30, 'Final kalite kontrol',    'WC-KALITE',   5, 10),
 ('YM-0001', 10, 'Ayak kesimi ve tornalama','WC-KESIM',   20, 12),
 ('YM-0001', 20, 'Zımparalama',             'WC-ZIMPARA',  5,  6),
 ('BL-0002', 10, 'Taban kesimi',            'WC-KESIM',   10,  3),
 ('BL-0002', 20, 'Döşeme montajı',          'WC-MONTAJ',  10,  8)
) AS v(item_code, op_no, op_name, wc_code, setup, run)
JOIN public.item i                ON i.item_code = v.item_code
JOIN engineering.routing r        ON r.item_id = i.item_id AND r.revision = 'A'
JOIN engineering.work_center w    ON w.work_center_code = v.wc_code;

-- 8.4 Customer demand, entered through O2C (draft -> lines -> confirm)
INSERT INTO sales.sales_order (order_no, customer_id, ordered_on, currency_code, created_by)
SELECT v.order_no, c.customer_id, v.ordered_on::date, 'TRY', e.employee_id
FROM (VALUES
 ('SO-2026-0001', 'M-0001', '2026-10-12'),
 ('SO-2026-0002', 'M-0003', '2026-10-20'),
 ('SO-2026-0003', 'M-0004', '2026-10-28')
) AS v(order_no, cust_code, ordered_on)
JOIN public.customer c ON c.customer_code = v.cust_code
JOIN public.employee e ON e.employee_no   = 'E-0002';

INSERT INTO sales.sales_order_line (order_id, line_no, item_id, quantity, unit_price)
SELECT so.order_id, v.line_no, i.item_id, v.qty, v.price
FROM (VALUES
 ('SO-2026-0001', 1, 'MM-0002', 40, 2250.00),
 ('SO-2026-0001', 2, 'MM-0001', 10, 9800.00),
 ('SO-2026-0002', 1, 'MM-0003', 25, 4950.00),
 ('SO-2026-0003', 1, 'MM-0001',  1, 9800.00)
) AS v(order_no, line_no, item_code, qty, price)
JOIN sales.sales_order so ON so.order_no  = v.order_no
JOIN public.item i        ON i.item_code  = v.item_code;

UPDATE sales.sales_order SET status = 'CONFIRMED'
WHERE order_no IN ('SO-2026-0001', 'SO-2026-0002', 'SO-2026-0003');

-- 8.5 Production plan
INSERT INTO planning.production_plan (plan_no, plan_name, period_start, period_end, status, created_by, approved_by, created_at)
SELECT 'PP-2026-11', 'Kasım-Aralık 2026 Üretim Planı', DATE '2026-10-26', DATE '2026-12-18',
       'ONAYLANDI', c.employee_id, a.employee_id, TIMESTAMP '2026-10-23 14:00'
FROM public.employee c, public.employee a
WHERE c.employee_no = 'E-0008' AND a.employee_no = 'E-0003';

-- Line 4 (single table) starts after the legs of line 5 are produced (2026-11-03).
INSERT INTO planning.production_plan_line (production_plan_id, line_no, item_id, sales_order_line_id, planned_quantity, planned_start_date, planned_finish_date)
SELECT pp.production_plan_id, v.line_no, i.item_id, sol.order_line_id, v.qty, v.start_date::date, v.finish_date::date
FROM (VALUES
 (1, 'MM-0002', 'SO-2026-0001', 1,    40, '2026-11-16', '2026-12-04'),
 (2, 'MM-0001', 'SO-2026-0001', 2,    10, '2026-11-09', '2026-12-04'),
 (3, 'MM-0003', 'SO-2026-0002', 1,    25, '2026-11-23', '2026-12-18'),
 (4, 'MM-0001', 'SO-2026-0003', 1,     1, '2026-11-04', '2026-11-10'),
 (5, 'YM-0001', NULL,           NULL, 44, '2026-10-27', '2026-11-03'),   -- dependent demand: legs for 11 tables
 (6, 'BL-0002', NULL,           NULL, 40, '2026-11-04', '2026-11-20')    -- dependent demand: seats for 40 chairs
) AS v(line_no, item_code, so_no, so_line_no, qty, start_date, finish_date)
JOIN planning.production_plan pp ON pp.plan_no = 'PP-2026-11'
JOIN public.item i               ON i.item_code = v.item_code
LEFT JOIN sales.sales_order so       ON so.order_no = v.so_no
LEFT JOIN sales.sales_order_line sol ON sol.order_id = so.order_id AND sol.line_no = v.so_line_no;

-- 8.6 MRP: gross requirement per plan line, one stock snapshot per plan (taken from the ledger)
INSERT INTO planning.material_requirement (production_plan_line_id, component_item_id, gross_requirement, needed_by_date)
SELECT ppl.production_plan_line_id, bl.component_item_id,
       ROUND(ppl.planned_quantity / b.base_quantity * bl.quantity_per * (1 + bl.scrap_percent / 100), 4),
       ppl.planned_start_date
FROM planning.production_plan pp
JOIN planning.production_plan_line ppl USING (production_plan_id)
JOIN engineering.bom b       ON b.item_id = ppl.item_id AND b.status = 'ONAYLI'
                            AND ppl.planned_start_date >= b.effective_from
                            AND (b.effective_to IS NULL OR ppl.planned_start_date <= b.effective_to)
JOIN engineering.bom_line bl ON bl.bom_id = b.bom_id
WHERE pp.plan_no = 'PP-2026-11';

INSERT INTO planning.plan_stock_snapshot (production_plan_id, item_id, on_hand_quantity)
SELECT pp.production_plan_id, comp.component_item_id, COALESCE(SUM(sb.quantity_on_hand), 0)
FROM planning.production_plan pp
JOIN (SELECT DISTINCT line.production_plan_id, req.component_item_id
      FROM planning.material_requirement req
      JOIN planning.production_plan_line line USING (production_plan_line_id)) AS comp USING (production_plan_id)
LEFT JOIN inventory.stock_balance sb ON sb.item_id = comp.component_item_id
WHERE pp.plan_no = 'PP-2026-11'
GROUP BY pp.production_plan_id, comp.component_item_id;

-- 8.7 Production orders (created as planned, then started / completed in date order)
INSERT INTO production.production_order
(order_no, production_plan_line_id, item_id, bom_id, routing_id, planned_quantity,
 planned_start_date, planned_finish_date, responsible_employee_id)
SELECT v.order_no, ppl.production_plan_line_id, ppl.item_id, b.bom_id, r.routing_id, ppl.planned_quantity,
       ppl.planned_start_date, ppl.planned_finish_date, e.employee_id
FROM (VALUES
 ('UE-2026-0001', 5, 'E-0005'),
 ('UE-2026-0002', 4, 'E-0005'),
 ('UE-2026-0003', 6, 'E-0005'),
 ('UE-2026-0004', 1, 'E-0003'),
 ('UE-2026-0005', 2, 'E-0003'),
 ('UE-2026-0006', 3, 'E-0003')
) AS v(order_no, plan_line_no, resp_no)
JOIN planning.production_plan pp       ON pp.plan_no = 'PP-2026-11'
JOIN planning.production_plan_line ppl ON ppl.production_plan_id = pp.production_plan_id AND ppl.line_no = v.plan_line_no
JOIN engineering.bom b                 ON b.item_id = ppl.item_id AND b.revision = 'A'
JOIN engineering.routing r             ON r.item_id = ppl.item_id AND r.revision = 'A'
JOIN public.employee e                 ON e.employee_no = v.resp_no;

INSERT INTO production.production_order_component (production_order_id, bom_id, component_item_id, required_quantity)
SELECT po.production_order_id, po.bom_id, bl.component_item_id,
       ROUND(po.planned_quantity / b.base_quantity * bl.quantity_per * (1 + bl.scrap_percent / 100), 3)
FROM production.production_order po
JOIN engineering.bom b       ON b.bom_id = po.bom_id
JOIN engineering.bom_line bl ON bl.bom_id = b.bom_id;

UPDATE production.production_order po
SET status = 'DEVAM_EDIYOR', actual_start_date = v.started::date
FROM (VALUES ('UE-2026-0001', '2026-10-27'), ('UE-2026-0002', '2026-11-04'), ('UE-2026-0003', '2026-11-04'))
     AS v(order_no, started)
WHERE po.order_no = v.order_no;

-- Issues and receipts are posted in date order: the ledger rejects any day with negative stock.
-- Legs order: issue materials, receive 44 legs, complete.
INSERT INTO production.material_issue (production_order_id, component_item_id, location_id, quantity, issued_by, issued_at)
SELECT c.production_order_id, c.component_item_id, l.location_id, c.required_quantity, e.employee_id, TIMESTAMP '2026-10-27 08:30'
FROM production.production_order_component c
JOIN production.production_order po ON po.production_order_id = c.production_order_id AND po.order_no = 'UE-2026-0001'
JOIN inventory.stock_location l     ON l.location_code = 'DEPO-ANA'
JOIN public.employee e              ON e.employee_no = 'E-0009';

INSERT INTO production.production_receipt (production_order_id, location_id, quantity, received_by, inspected_by, received_at, notes)
SELECT po.production_order_id, l.location_id, po.planned_quantity, r.employee_id, k.employee_id,
       TIMESTAMP '2026-11-03 16:45', '44 adet meşe masa ayağı kalite kontrolden geçti ve depoya girdi.'
FROM production.production_order po
JOIN inventory.stock_location l ON l.location_code = 'DEPO-ANA'
JOIN public.employee r ON r.employee_no = 'E-0009'
JOIN public.employee k ON k.employee_no = 'E-0007'
WHERE po.order_no = 'UE-2026-0001';

UPDATE production.production_order SET status = 'TAMAMLANDI', actual_finish_date = DATE '2026-11-03'
WHERE order_no = 'UE-2026-0001';

-- Table and seat orders draw their components (the table uses 4 of the legs just produced).
INSERT INTO production.material_issue (production_order_id, component_item_id, location_id, quantity, issued_by, issued_at)
SELECT c.production_order_id, c.component_item_id, l.location_id, c.required_quantity, e.employee_id, v.issued_at::timestamp
FROM production.production_order_component c
JOIN production.production_order po ON po.production_order_id = c.production_order_id
JOIN (VALUES ('UE-2026-0002', '2026-11-04 08:30'), ('UE-2026-0003', '2026-11-04 08:15')) AS v(order_no, issued_at)
     ON v.order_no = po.order_no
JOIN inventory.stock_location l ON l.location_code = 'DEPO-ANA'
JOIN public.employee e          ON e.employee_no = 'E-0009';

INSERT INTO production.production_receipt (production_order_id, location_id, quantity, received_by, inspected_by, received_at, notes)
SELECT po.production_order_id, l.location_id, po.planned_quantity, r.employee_id, k.employee_id,
       TIMESTAMP '2026-11-10 17:10', 'Yemek masası kalite kontrolden geçti ve depoya girdi.'
FROM production.production_order po
JOIN inventory.stock_location l ON l.location_code = 'DEPO-ANA'
JOIN public.employee r ON r.employee_no = 'E-0009'
JOIN public.employee k ON k.employee_no = 'E-0007'
WHERE po.order_no = 'UE-2026-0002';

UPDATE production.production_order SET status = 'TAMAMLANDI', actual_finish_date = DATE '2026-11-10'
WHERE order_no = 'UE-2026-0002';

-- MM-0001 is serialized
INSERT INTO production.item_unit (item_id, production_order_id, serial_number, status)
SELECT po.item_id, po.production_order_id, 'MM1-2026-000001', 'STOKTA'
FROM production.production_order po
WHERE po.order_no = 'UE-2026-0002';

INSERT INTO production.production_order_operation
(production_order_id, routing_id, routing_operation_id, planned_setup_minutes, planned_run_minutes, status, operator_id)
SELECT s.production_order_id, s.routing_id, s.routing_operation_id, s.setup_minutes, s.run_minutes, s.op_status,
       CASE WHEN s.op_status <> 'BEKLIYOR'
            THEN (SELECT employee_id FROM public.employee WHERE employee_no = 'E-0005') END
FROM (
    SELECT po.production_order_id, po.routing_id, ro.routing_operation_id, ro.setup_minutes,
           ro.run_minutes_per_unit * po.planned_quantity AS run_minutes,
           CASE WHEN po.status = 'TAMAMLANDI'                              THEN 'TAMAMLANDI'
                WHEN po.status = 'DEVAM_EDIYOR' AND ro.operation_no = 10   THEN 'TAMAMLANDI'
                WHEN po.status = 'DEVAM_EDIYOR' AND ro.operation_no = 20   THEN 'DEVAM_EDIYOR'
                ELSE 'BEKLIYOR' END AS op_status
    FROM production.production_order po
    JOIN engineering.routing_operation ro ON ro.routing_id = po.routing_id
) s;

COMMIT;
