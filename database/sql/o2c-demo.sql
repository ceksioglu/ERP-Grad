BEGIN;

DO $$
DECLARE
    demo_customer_id INTEGER;
    demo_employee_id INTEGER;
    demo_stock_employee_id INTEGER;
    demo_finance_employee_id INTEGER;
    demo_supplier_id INTEGER;
    demo_receipt_id INTEGER;
    demo_item_id INTEGER;
    demo_location_id INTEGER;
    demo_order_id INTEGER;
    demo_line_id INTEGER;
    demo_invoice_id INTEGER;
    rejected BOOLEAN;
BEGIN
    SELECT employee_id INTO STRICT demo_employee_id FROM public.employee WHERE employee_no = 'E-0002';
    SELECT employee_id INTO STRICT demo_stock_employee_id FROM public.employee WHERE employee_no = 'E-0007';
    SELECT employee_id INTO STRICT demo_finance_employee_id FROM public.employee WHERE employee_no = 'E-0006';
    SELECT supplier_id INTO STRICT demo_supplier_id FROM public.supplier WHERE supplier_code = 'T-0001';
    SELECT item_id INTO STRICT demo_item_id FROM public.item WHERE item_code = 'HM-0002';

    INSERT INTO public.customer (customer_code, customer_name, customer_type)
    VALUES ('O2C-DEMO-C', 'O2C Demo Customer', 'BIREYSEL') RETURNING customer_id INTO demo_customer_id;

    INSERT INTO inventory.stock_location (location_code, location_name, location_type)
    VALUES ('O2C-DEMO-STORE', 'O2C Demo Store', 'STORE') RETURNING location_id INTO demo_location_id;

    INSERT INTO sales.sales_order (order_no, customer_id, ordered_on, currency_code, created_by)
    VALUES ('SO-O2C-DEMO-01', demo_customer_id, DATE '2026-11-23', 'TRY', demo_employee_id)
    RETURNING order_id INTO demo_order_id;

    rejected := FALSE;
    BEGIN
        UPDATE sales.sales_order SET status = 'CONFIRMED' WHERE order_id = demo_order_id;
    EXCEPTION WHEN check_violation THEN
        rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'An empty order was confirmed'; END IF;

    INSERT INTO sales.sales_order_line (order_id, line_no, item_id, quantity, unit_price)
    VALUES (demo_order_id, 1, demo_item_id, 2, 2500.00) RETURNING order_line_id INTO demo_line_id;
    UPDATE sales.sales_order SET status = 'CONFIRMED' WHERE order_id = demo_order_id;

    rejected := FALSE;
    BEGIN
        INSERT INTO inventory.inventory_movement
            (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by)
        VALUES ('ISSUE-NO-STOCK', 'SALE_ISSUE', demo_location_id, demo_item_id, demo_line_id,
                DATE '2026-11-24', 1, demo_employee_id);
    EXCEPTION WHEN check_violation THEN
        rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'A stock issue without available quantity was accepted'; END IF;

    INSERT INTO inventory.goods_receipt (receipt_no, supplier_id, location_id, received_on, received_by)
    VALUES ('GR-O2C-DEMO-01', demo_supplier_id, demo_location_id, DATE '2026-11-23', demo_stock_employee_id)
    RETURNING receipt_id INTO demo_receipt_id;
    INSERT INTO inventory.goods_receipt_line (receipt_id, line_no, item_id, quantity)
    VALUES (demo_receipt_id, 1, demo_item_id, 10);
    INSERT INTO inventory.goods_receipt_line (receipt_id, line_no, item_id, quantity)
    VALUES (demo_receipt_id, 1, demo_item_id, 10) ON CONFLICT (receipt_id, line_no) DO NOTHING;

    IF NOT EXISTS (
        SELECT 1 FROM inventory.inventory_movement AS movement
        JOIN inventory.goods_receipt_line AS line USING (receipt_line_id)
        WHERE line.receipt_id = demo_receipt_id AND movement.quantity = 10
    ) THEN
        RAISE EXCEPTION 'Goods receipt did not post to the shared stock ledger';
    END IF;

    INSERT INTO inventory.inventory_movement
        (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by)
    VALUES ('ISSUE-O2C-DEMO-01', 'SALE_ISSUE', demo_location_id, demo_item_id, demo_line_id,
            DATE '2026-11-24', 1, demo_stock_employee_id);

    rejected := FALSE;
    BEGIN
        INSERT INTO sales.customer_invoice (invoice_no, order_id, issued_on, due_on, issued_by)
        VALUES ('INV-TOO-EARLY', demo_order_id, DATE '2026-11-24', DATE '2026-12-24', demo_employee_id);
    EXCEPTION WHEN check_violation THEN
        rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'A partially issued order was invoiced'; END IF;

    INSERT INTO inventory.inventory_movement
        (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by)
    VALUES ('ISSUE-O2C-DEMO-02', 'SALE_ISSUE', demo_location_id, demo_item_id, demo_line_id,
            DATE '2026-11-25', 1, demo_stock_employee_id);

    rejected := FALSE;
    BEGIN
        INSERT INTO inventory.inventory_movement
            (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by)
        VALUES ('ISSUE-OVER-ORDER', 'SALE_ISSUE', demo_location_id, demo_item_id, demo_line_id,
                DATE '2026-11-25', 1, demo_employee_id);
    EXCEPTION WHEN check_violation THEN
        rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'More units than ordered were issued'; END IF;

    INSERT INTO sales.customer_invoice (invoice_no, order_id, issued_on, due_on, issued_by)
    VALUES ('INV-O2C-DEMO-01', demo_order_id, DATE '2026-11-25', DATE '2026-12-25', demo_finance_employee_id)
    RETURNING invoice_id INTO demo_invoice_id;

    INSERT INTO sales.customer_payment (payment_no, invoice_id, received_on, amount, recorded_by)
    VALUES ('PAY-O2C-DEMO-01', demo_invoice_id, DATE '2026-11-28', 2000.00, demo_finance_employee_id);

    IF NOT EXISTS (SELECT 1 FROM sales.customer_invoice_balance
                   WHERE invoice_id = demo_invoice_id AND total_amount = 5000 AND balance_due = 3000) THEN
        RAISE EXCEPTION 'Incorrect invoice total or balance after partial payment';
    END IF;

    rejected := FALSE;
    BEGIN
        INSERT INTO sales.customer_payment (payment_no, invoice_id, received_on, amount, recorded_by)
        VALUES ('PAY-OVER-BALANCE', demo_invoice_id, DATE '2026-12-01', 3001.00, demo_employee_id);
    EXCEPTION WHEN check_violation THEN
        rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'An overpayment was accepted'; END IF;

    INSERT INTO sales.customer_payment (payment_no, invoice_id, received_on, amount, recorded_by)
    VALUES ('PAY-O2C-DEMO-02', demo_invoice_id, DATE '2026-12-01', 3000.00, demo_finance_employee_id);

    IF NOT EXISTS (SELECT 1 FROM sales.customer_invoice_balance
                   WHERE invoice_id = demo_invoice_id AND currency_code = 'TRY' AND paid_amount = 5000 AND balance_due = 0) THEN
        RAISE EXCEPTION 'Incorrect settled invoice balance';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM inventory.stock_balance
                   WHERE location_id = demo_location_id AND item_id = demo_item_id AND quantity_on_hand = 8) THEN
        RAISE EXCEPTION 'Incorrect remaining stock';
    END IF;
END;
$$;

SELECT customer.customer_code, invoice.order_no, invoice.invoice_no, invoice.currency_code,
       invoice.total_amount, invoice.paid_amount, invoice.balance_due, stock.quantity_on_hand
FROM sales.customer_invoice_balance AS invoice
JOIN public.customer AS customer USING (customer_id)
CROSS JOIN inventory.stock_balance AS stock
JOIN inventory.stock_location AS location ON location.location_id = stock.location_id
JOIN public.item AS item ON item.item_id = stock.item_id
WHERE invoice.invoice_no = 'INV-O2C-DEMO-01'
  AND location.location_code = 'O2C-DEMO-STORE'
  AND item.item_code = 'HM-0002';

ROLLBACK;
