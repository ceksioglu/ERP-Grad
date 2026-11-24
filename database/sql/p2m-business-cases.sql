-- P2M business-rule checks and P2M -> O2C integration test.
-- Run after p2m-database.sql. Everything is rolled back at the end.

BEGIN;

CREATE FUNCTION pg_temp.expect_p2m_failure(case_name TEXT, expected_state TEXT, statement TEXT, expected_reason TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = expected_state AND (expected_reason IS NULL OR POSITION(expected_reason IN SQLERRM) > 0) THEN
            RETURN;
        END IF;
        RAISE EXCEPTION 'Case % expected SQLSTATE %, got %: %', case_name, expected_state, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'Case % was accepted but should have failed', case_name;
END;
$$;

DO $$
DECLARE
    plan_key          INTEGER;
    warehouse_key     INTEGER;
    empty_loc_key     INTEGER;
    clerk_key         INTEGER;
    sales_key         INTEGER;
    finance_key       INTEGER;
    customer_key      INTEGER;
    table_key         INTEGER;
    desk_key          INTEGER;
    leg_key           INTEGER;
    seat_key          INTEGER;
    mdf_key           INTEGER;
    screw_key         INTEGER;
    handle_key        INTEGER;
    chair_line        INTEGER;
    table_line        INTEGER;
    single_table_line INTEGER;
    draft_order       INTEGER;
    draft_line        INTEGER;
    legs_order        INTEGER;
    table_order       INTEGER;
    seats_order       INTEGER;
    chairs_order      INTEGER;
    legs_plan_line    INTEGER;
    legs_bom          INTEGER;
    seat_bom          INTEGER;
    table_bom         INTEGER;
    draft_bom         INTEGER;
    so3               INTEGER;
    invoice_key       INTEGER;
    plan_line_sql     TEXT := 'INSERT INTO planning.production_plan_line (production_plan_id, line_no, item_id, sales_order_line_id, planned_quantity, planned_start_date, planned_finish_date) VALUES (%s, %s, %s, %s, %s, %L, %L)';
    issue_sql         TEXT := 'INSERT INTO production.material_issue (production_order_id, component_item_id, location_id, quantity, issued_by, issued_at) VALUES (%s, %s, %s, %s, %s, %L)';
    receipt_sql       TEXT := 'INSERT INTO production.production_receipt (production_order_id, location_id, quantity, received_by, received_at) VALUES (%s, %s, %s, %s, %L)';
    sale_issue_sql    TEXT := 'INSERT INTO inventory.inventory_movement (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by) VALUES (%L, ''SALE_ISSUE'', %s, %s, %s, %L, %s, %s)';
BEGIN
    SELECT production_plan_id INTO STRICT plan_key FROM planning.production_plan WHERE plan_no = 'PP-2026-11';
    SELECT location_id INTO STRICT warehouse_key FROM inventory.stock_location WHERE location_code = 'DEPO-ANA';
    SELECT employee_id INTO STRICT clerk_key   FROM public.employee WHERE employee_no = 'E-0009';
    SELECT employee_id INTO STRICT sales_key   FROM public.employee WHERE employee_no = 'E-0002';
    SELECT employee_id INTO STRICT finance_key FROM public.employee WHERE employee_no = 'E-0006';
    SELECT customer_id INTO STRICT customer_key FROM public.customer WHERE customer_code = 'M-0002';
    SELECT item_id INTO STRICT table_key  FROM public.item WHERE item_code = 'MM-0001';
    SELECT item_id INTO STRICT desk_key   FROM public.item WHERE item_code = 'MM-0003';
    SELECT item_id INTO STRICT leg_key    FROM public.item WHERE item_code = 'YM-0001';
    SELECT item_id INTO STRICT seat_key   FROM public.item WHERE item_code = 'BL-0002';
    SELECT item_id INTO STRICT mdf_key    FROM public.item WHERE item_code = 'HM-0002';
    SELECT item_id INTO STRICT screw_key  FROM public.item WHERE item_code = 'SM-0001';
    SELECT item_id INTO STRICT handle_key FROM public.item WHERE item_code = 'BL-0001';

    SELECT line.order_line_id INTO STRICT chair_line FROM sales.sales_order_line line
    JOIN sales.sales_order so USING (order_id) WHERE so.order_no = 'SO-2026-0001' AND line.line_no = 1;
    SELECT line.order_line_id INTO STRICT table_line FROM sales.sales_order_line line
    JOIN sales.sales_order so USING (order_id) WHERE so.order_no = 'SO-2026-0001' AND line.line_no = 2;
    SELECT so.order_id, line.order_line_id INTO STRICT so3, single_table_line FROM sales.sales_order_line line
    JOIN sales.sales_order so USING (order_id) WHERE so.order_no = 'SO-2026-0003';

    SELECT production_order_id INTO STRICT legs_order   FROM production.production_order WHERE order_no = 'UE-2026-0001';
    SELECT production_order_id INTO STRICT table_order  FROM production.production_order WHERE order_no = 'UE-2026-0002';
    SELECT production_order_id INTO STRICT seats_order  FROM production.production_order WHERE order_no = 'UE-2026-0003';
    SELECT production_order_id INTO STRICT chairs_order FROM production.production_order WHERE order_no = 'UE-2026-0004';
    SELECT production_plan_line_id INTO STRICT legs_plan_line FROM planning.production_plan_line
    WHERE production_plan_id = plan_key AND line_no = 5;
    SELECT bom_id INTO STRICT legs_bom  FROM engineering.bom WHERE item_id = leg_key   AND revision = 'A';
    SELECT bom_id INTO STRICT seat_bom  FROM engineering.bom WHERE item_id = seat_key  AND revision = 'A';
    SELECT bom_id INTO STRICT table_bom FROM engineering.bom WHERE item_id = table_key AND revision = 'A';

    INSERT INTO inventory.stock_location (location_code, location_name, location_type)
    VALUES ('P2M-TEST-EMPTY', 'Empty test location', 'WAREHOUSE') RETURNING location_id INTO empty_loc_key;

    INSERT INTO sales.sales_order (order_no, customer_id, ordered_on, currency_code, created_by)
    VALUES ('P2M-TEST-DRAFT', customer_key, DATE '2026-10-01', 'TRY', sales_key) RETURNING order_id INTO draft_order;
    INSERT INTO sales.sales_order_line (order_id, line_no, item_id, quantity, unit_price)
    VALUES (draft_order, 1, desk_key, 3, 4950.00) RETURNING order_line_id INTO draft_line;

    INSERT INTO engineering.bom (item_id, revision, status, effective_from)
    VALUES (leg_key, 'Z', 'TASLAK', DATE '2026-01-01') RETURNING bom_id INTO draft_bom;

    -- ---------------------------------------------------------------- planning
    PERFORM pg_temp.expect_p2m_failure('Plan line item differs from sales order line item', '23503',
        FORMAT(plan_line_sql, plan_key, 90, desk_key, chair_line, 1, '2026-11-20', '2026-11-25'));
    PERFORM pg_temp.expect_p2m_failure('Plan line outside plan period', '23514',
        FORMAT(plan_line_sql, plan_key, 90, leg_key, 'NULL', 5, '2030-01-01', '2030-01-02'), 'plan period');
    PERFORM pg_temp.expect_p2m_failure('Plan line above ordered quantity', '23514',
        FORMAT(plan_line_sql, plan_key, 90, table_key, table_line, 1, '2026-11-20', '2026-11-25'), 'exceeds the open sales order');
    PERFORM pg_temp.expect_p2m_failure('Plan line for a draft sales order', '23514',
        FORMAT(plan_line_sql, plan_key, 90, desk_key, draft_line, 1, '2026-11-20', '2026-11-25'), 'confirmed order');
    PERFORM pg_temp.expect_p2m_failure('Plan line starts before the order date', '23514',
        FORMAT(plan_line_sql, plan_key, 90, table_key, single_table_line, 1, '2026-10-27', '2026-10-30'), 'confirmed order');
    PERFORM pg_temp.expect_p2m_failure('Plan line for a non-manufacturable item', '23514',
        FORMAT(plan_line_sql, plan_key, 90, mdf_key, 'NULL', 1, '2026-11-20', '2026-11-25'), 'is_manufacturable');
    PERFORM pg_temp.expect_p2m_failure('Plan period shrunk below its lines', '23514',
        FORMAT('UPDATE planning.production_plan SET period_end = %L WHERE production_plan_id = %s', '2026-11-30', plan_key));
    PERFORM pg_temp.expect_p2m_failure('NaN planned quantity', '23514',
        FORMAT(plan_line_sql, plan_key, 90, leg_key, 'NULL', '''NaN''', '2026-11-20', '2026-11-25'));

    -- ---------------------------------------------------------------- engineering
    PERFORM pg_temp.expect_p2m_failure('BOM lists its own parent', '23514',
        FORMAT('INSERT INTO engineering.bom_line (bom_id, line_no, component_item_id, quantity_per) VALUES (%s, 9, %s, 1)', seat_bom, seat_key));
    INSERT INTO engineering.bom_line (bom_id, line_no, component_item_id, quantity_per) VALUES (legs_bom, 9, seat_key, 1);
    PERFORM pg_temp.expect_p2m_failure('BOM cycle legs -> seat -> legs', '23514',
        FORMAT('INSERT INTO engineering.bom_line (bom_id, line_no, component_item_id, quantity_per) VALUES (%s, 9, %s, 1)', seat_bom, leg_key),
        'component of itself');
    PERFORM pg_temp.expect_p2m_failure('BOM cycle three levels deep (table -> legs -> seat -> table)', '23514',
        FORMAT('INSERT INTO engineering.bom_line (bom_id, line_no, component_item_id, quantity_per) VALUES (%s, 9, %s, 1)', seat_bom, table_key));
    DELETE FROM engineering.bom_line WHERE bom_id = legs_bom AND line_no = 9;

    -- ---------------------------------------------------------------- production orders
    PERFORM pg_temp.expect_p2m_failure('Production order with a draft BOM', '23514', FORMAT(
        'INSERT INTO production.production_order (order_no, production_plan_line_id, item_id, bom_id, routing_id, planned_quantity, planned_start_date, planned_finish_date, responsible_employee_id) '
        'SELECT ''P2M-BAD-BOM'', %s, %s, %s, routing_id, 1, ''2026-11-01'', ''2026-11-02'', %s FROM engineering.routing WHERE item_id = %s',
        legs_plan_line, leg_key, draft_bom, clerk_key, leg_key), 'approved BOM');
    PERFORM pg_temp.expect_p2m_failure('Production orders above plan line quantity', '23514', FORMAT(
        'INSERT INTO production.production_order (order_no, production_plan_line_id, item_id, bom_id, routing_id, planned_quantity, planned_start_date, planned_finish_date, responsible_employee_id) '
        'SELECT ''P2M-BAD-QTY'', %s, %s, %s, routing_id, 1, ''2026-11-01'', ''2026-11-02'', %s FROM engineering.routing WHERE item_id = %s',
        legs_plan_line, leg_key, legs_bom, clerk_key, leg_key), 'exceed the plan line');
    PERFORM pg_temp.expect_p2m_failure('Operation from another item routing', '23503', FORMAT(
        'INSERT INTO production.production_order_operation (production_order_id, routing_id, routing_operation_id, planned_setup_minutes, planned_run_minutes) '
        'SELECT %s, po.routing_id, ro.routing_operation_id, 0, 0 FROM production.production_order po, engineering.routing_operation ro '
        'JOIN engineering.routing r USING (routing_id) WHERE po.production_order_id = %s AND r.item_id = %s LIMIT 1',
        legs_order, legs_order, desk_key));
    PERFORM pg_temp.expect_p2m_failure('Component not in the order BOM', '23503', FORMAT(
        'INSERT INTO production.production_order_component (production_order_id, bom_id, component_item_id, required_quantity) VALUES (%s, %s, %s, 5)',
        legs_order, legs_bom, handle_key));
    UPDATE engineering.bom SET status = 'ONAYLI', approved_by = clerk_key WHERE bom_id = draft_bom;
    PERFORM pg_temp.expect_p2m_failure('Switch BOM of an order that has components', '23503', FORMAT(
        'UPDATE production.production_order SET bom_id = %s WHERE production_order_id = %s', draft_bom, legs_order));

    -- ---------------------------------------------------------------- material issues
    PERFORM pg_temp.expect_p2m_failure('Issue to a planned (not released) order', '23514',
        FORMAT(issue_sql, chairs_order, seat_key, warehouse_key, 1, clerk_key, '2026-11-20 08:00'), 'released or in-progress');
    PERFORM pg_temp.expect_p2m_failure('Issue above required quantity', '23514',
        FORMAT(issue_sql, seats_order, mdf_key, warehouse_key, 1, clerk_key, '2026-11-20 08:00'), 'exceed the required');
    PERFORM pg_temp.expect_p2m_failure('Issue to a completed order', '23514',
        FORMAT(issue_sql, legs_order, (SELECT item_id FROM public.item WHERE item_code = 'HM-0001'), warehouse_key, 0.001, clerk_key, '2026-11-20 08:00'));
    UPDATE production.production_order SET status = 'SERBEST' WHERE production_order_id = chairs_order;
    PERFORM pg_temp.expect_p2m_failure('Issue from a location without stock', '23514',
        FORMAT(issue_sql, chairs_order, screw_key, empty_loc_key, 1, clerk_key, '2026-11-20 08:00'), 'Insufficient stock');
    PERFORM pg_temp.expect_p2m_failure('Backdated issue before opening stock', '23514',
        FORMAT(issue_sql, chairs_order, screw_key, warehouse_key, 1, clerk_key, '2026-10-01 08:00'), 'Insufficient stock');
    PERFORM pg_temp.expect_p2m_failure('NaN issue quantity', '23514',
        FORMAT(issue_sql, chairs_order, screw_key, warehouse_key, '''NaN''', clerk_key, '2026-11-20 08:00'));
    PERFORM pg_temp.expect_p2m_failure('Posted material issue changed', '23514', FORMAT(
        'UPDATE production.material_issue SET quantity = quantity + 1 WHERE production_order_id = %s', legs_order));

    -- ---------------------------------------------------------------- production receipts
    PERFORM pg_temp.expect_p2m_failure('Receipt from a not-started order', '23514',
        FORMAT(receipt_sql, chairs_order, warehouse_key, 1, clerk_key, '2026-11-20 16:00'), 'started production order');
    PERFORM pg_temp.expect_p2m_failure('Receipt above planned quantity', '23514',
        FORMAT(receipt_sql, seats_order, warehouse_key, 41, clerk_key, '2026-11-20 16:00'), 'exceeds the planned');
    PERFORM pg_temp.expect_p2m_failure('Receipt before order start', '23514',
        FORMAT(receipt_sql, seats_order, warehouse_key, 1, clerk_key, '2026-11-01 16:00'), 'precede the order start');
    PERFORM pg_temp.expect_p2m_failure('NaN receipt quantity', '23514',
        FORMAT(receipt_sql, seats_order, warehouse_key, '''NaN''', clerk_key, '2026-11-20 16:00'));
    PERFORM pg_temp.expect_p2m_failure('Posted production receipt deleted', '23514', FORMAT(
        'DELETE FROM production.production_receipt WHERE production_order_id = %s', legs_order));
    PERFORM pg_temp.expect_p2m_failure('More serial numbers than units received', '23514', FORMAT(
        'INSERT INTO production.item_unit (item_id, production_order_id, serial_number) VALUES (%s, %s, ''MM1-2026-000002'')',
        table_key, table_order), 'Serial numbers');

    -- ---------------------------------------------------------------- shared ledger
    PERFORM pg_temp.expect_p2m_failure('Production receipt movement without source document', '23514', FORMAT(
        'INSERT INTO inventory.inventory_movement (movement_no, movement_type, location_id, item_id, moved_on, quantity, recorded_by) '
        'VALUES (''P2M-BAD-NOSRC'', ''PROD_RECEIPT'', %s, %s, ''2026-11-20'', 5, %s)', warehouse_key, table_key, clerk_key));
    PERFORM pg_temp.expect_p2m_failure('Production receipt posted twice', '23505', FORMAT(
        'INSERT INTO inventory.inventory_movement (movement_no, movement_type, location_id, item_id, production_receipt_id, moved_on, quantity, recorded_by) '
        'SELECT ''P2M-BAD-DUP'', ''PROD_RECEIPT'', location_id, %s, production_receipt_id, received_at::date, quantity, received_by '
        'FROM production.production_receipt WHERE production_order_id = %s', leg_key, legs_order));

    -- ---------------------------------------------------------------- expected state
    IF EXISTS (
        SELECT 1 FROM (VALUES ('HM-0002', 43.5750, 30.0000, 13.5750),
                              ('SM-0002', 34.6500, 25.0000,  9.6500),
                              ('YM-0001', 44.0000,  0.0000, 44.0000),
                              ('BL-0002', 40.0000,  5.0000, 35.0000),
                              ('SM-0001', 28.0000, 40.0000,  0.0000))
             AS expected(item_code, gross, on_hand, net)
        JOIN public.item i USING (item_code)
        LEFT JOIN planning.material_requirement_net n
               ON n.production_plan_id = plan_key AND n.component_item_id = i.item_id
        WHERE (n.gross_requirement, n.on_hand_quantity, n.net_requirement)
              IS DISTINCT FROM (expected.gross, expected.on_hand, expected.net)
    ) THEN
        RAISE EXCEPTION 'MRP net requirements are wrong (stock must be netted once per plan)';
    END IF;

    IF EXISTS (
        SELECT 1 FROM (VALUES ('YM-0001', 40.000), ('MM-0001', 1.000), ('HM-0002', 25.800),
                              ('HM-0001', 2.245), ('SM-0002', 21.850), ('BL-0002', 5.000))
             AS expected(item_code, qty)
        JOIN public.item i USING (item_code)
        LEFT JOIN inventory.stock_balance b ON b.item_id = i.item_id AND b.location_id = warehouse_key
        WHERE b.quantity_on_hand IS DISTINCT FROM expected.qty
    ) THEN
        RAISE EXCEPTION 'Warehouse stock after production postings is wrong';
    END IF;

    -- ---------------------------------------------------------------- P2M -> O2C hand-off
    -- The table produced on 2026-11-10 can be shipped, invoiced and paid through O2C.
    PERFORM pg_temp.expect_p2m_failure('Ship before the table was produced', '23514',
        FORMAT(sale_issue_sql, 'P2M-BAD-EARLY-SHIP', warehouse_key, table_key, single_table_line, '2026-11-09', 1, clerk_key),
        'Insufficient stock');
    EXECUTE FORMAT(sale_issue_sql, 'P2M-SHIP-SO3', warehouse_key, table_key, single_table_line, '2026-11-12', 1, clerk_key);
    PERFORM pg_temp.expect_p2m_failure('Ship a second table that was never produced', '23514',
        FORMAT(sale_issue_sql, 'P2M-BAD-SECOND', warehouse_key, table_key, table_line, '2026-11-13', 1, clerk_key),
        'Insufficient stock');

    INSERT INTO sales.customer_invoice (invoice_no, order_id, issued_on, due_on, issued_by)
    VALUES ('P2M-INV-SO3', so3, DATE '2026-11-12', DATE '2026-12-12', finance_key) RETURNING invoice_id INTO invoice_key;
    INSERT INTO sales.customer_payment (payment_no, invoice_id, received_on, amount, recorded_by)
    VALUES ('P2M-PAY-SO3', invoice_key, DATE '2026-11-20', 9800.00, finance_key);

    IF NOT EXISTS (SELECT 1 FROM sales.customer_invoice_balance
                   WHERE invoice_id = invoice_key AND total_amount = 9800.00 AND balance_due = 0)
       OR NOT EXISTS (SELECT 1 FROM inventory.stock_balance
                      WHERE location_id = warehouse_key AND item_id = table_key AND quantity_on_hand = 0) THEN
        RAISE EXCEPTION 'P2M -> O2C hand-off left a wrong invoice balance or table stock';
    END IF;

    RAISE NOTICE 'P2M business cases passed';
END;
$$;

ROLLBACK;
