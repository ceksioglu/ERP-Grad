BEGIN;

CREATE FUNCTION pg_temp.expect_o2c_failure(case_name TEXT, expected_state TEXT, statement TEXT, expected_reason TEXT DEFAULT NULL)
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
    customer_key INTEGER;
    individual_customer_key INTEGER;
    employee_key INTEGER;
    stock_employee_key INTEGER;
    finance_employee_key INTEGER;
    supplier_key INTEGER;
    store_receipt_key INTEGER;
    warehouse_receipt_key INTEGER;
    later_receipt_key INTEGER;
    chair_key INTEGER;
    desk_key INTEGER;
    metre_key INTEGER;
    inactive_key INTEGER;
    non_sellable_key INTEGER;
    store_key INTEGER;
    warehouse_key INTEGER;
    orders INTEGER[];
    draft_line INTEGER;
    unissued_line INTEGER;
    partial_line INTEGER;
    unpaid_invoice INTEGER;
    partial_invoice INTEGER;
    receipt_statement TEXT := 'INSERT INTO inventory.inventory_movement (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by) VALUES (%L, %L, %s, %s, %s, %L, %s, %s)';
    line_statement TEXT := 'INSERT INTO sales.sales_order_line (order_id,line_no,item_id,quantity,unit_price) VALUES (%s,%s,%s,%s,%s)';
    invoice_statement TEXT := 'INSERT INTO sales.customer_invoice (invoice_no,order_id,issued_on,due_on,issued_by) VALUES (%L,%s,%L,%L,%s)';
    payment_statement TEXT := 'INSERT INTO sales.customer_payment (payment_no,invoice_id,received_on,amount,recorded_by) VALUES (%L,%s,%L,%s,%s)';
BEGIN
    IF EXISTS (SELECT 1 FROM sales.sales_order WHERE order_no LIKE 'O2C-EX-%') THEN
        RAISE EXCEPTION 'O2C example orders are already installed';
    END IF;

    SELECT customer_id INTO STRICT customer_key FROM public.customer WHERE customer_code = 'M-0001';
    SELECT customer_id INTO STRICT individual_customer_key FROM public.customer WHERE customer_code = 'M-0004';
    SELECT employee_id INTO STRICT employee_key FROM public.employee WHERE employee_no = 'E-0002';
    SELECT employee_id INTO STRICT stock_employee_key FROM public.employee WHERE employee_no = 'E-0007';
    SELECT employee_id INTO STRICT finance_employee_key FROM public.employee WHERE employee_no = 'E-0006';
    SELECT supplier_id INTO STRICT supplier_key FROM public.supplier WHERE supplier_code = 'T-0001';
    SELECT item_id INTO STRICT non_sellable_key FROM public.item WHERE item_code = 'HM-0001';

    INSERT INTO public.item (item_code, item_name, item_category, unit_of_measure, is_purchasable, is_sellable, list_price)
    VALUES ('O2C-EX-CHAIR', 'Example chair', 'MAMUL', 'ADET', TRUE, TRUE, 2500.00) RETURNING item_id INTO chair_key;
    INSERT INTO public.item (item_code, item_name, item_category, unit_of_measure, is_purchasable, is_sellable, list_price)
    VALUES ('O2C-EX-DESK', 'Example desk', 'MAMUL', 'ADET', TRUE, TRUE, 120.00) RETURNING item_id INTO desk_key;

    INSERT INTO public.item
        (item_code, item_name, item_category, unit_of_measure, is_purchasable, is_sellable, list_price)
    VALUES ('O2C-EX-LENGTH', 'Example trim by metre', 'MAMUL', 'M', TRUE, TRUE, 10.00)
    RETURNING item_id INTO metre_key;

    INSERT INTO public.item
        (item_code, item_name, item_category, unit_of_measure, is_sellable, list_price, is_active)
    VALUES ('O2C-EX-INACTIVE', 'Example discontinued chair', 'MAMUL', 'ADET', TRUE, 2500.00, FALSE)
    RETURNING item_id INTO inactive_key;

    INSERT INTO inventory.stock_location (location_code, location_name, location_type)
    VALUES ('O2C-EX-STORE', 'Example Store', 'STORE') RETURNING location_id INTO store_key;
    INSERT INTO inventory.stock_location (location_code, location_name, location_type)
    VALUES ('O2C-EX-WAREHOUSE', 'Example Warehouse', 'WAREHOUSE') RETURNING location_id INTO warehouse_key;

    INSERT INTO sales.sales_order (order_no, customer_id, ordered_on, currency_code, created_by)
    SELECT 'O2C-EX-' || LPAD(example_number::text, 2, '0'),
           CASE WHEN example_number IN (7, 9) THEN individual_customer_key ELSE customer_key END,
           DATE '2026-11-10', CASE WHEN example_number = 8 THEN 'EUR' ELSE 'TRY' END, employee_key
    FROM generate_series(1, 10) AS examples(example_number);

    SELECT ARRAY_AGG(order_id ORDER BY order_no) INTO orders
    FROM sales.sales_order WHERE order_no LIKE 'O2C-EX-%';

    INSERT INTO sales.sales_order_line (order_id, line_no, item_id, quantity, unit_price)
    VALUES (orders[2], 1, chair_key, 1, 2500.00),
           (orders[3], 1, chair_key, 2, 2500.00),
           (orders[4], 1, chair_key, 2, 2500.00),
           (orders[5], 1, chair_key, 1, 2500.00),
           (orders[6], 1, chair_key, 2, 2500.00),
           (orders[6], 2, desk_key, 1, 0.00),
           (orders[7], 1, chair_key, 1, 2500.00),
           (orders[8], 1, desk_key, 1, 120.00),
           (orders[9], 1, metre_key, 0.001, 10.00),
           (orders[10], 1, chair_key, 1, 2500.00);

    UPDATE sales.sales_order SET status = 'CONFIRMED' WHERE order_id = ANY (orders[3:10]);

    INSERT INTO inventory.goods_receipt (receipt_no, supplier_id, location_id, received_on, received_by)
    VALUES ('O2C-EX-R01', supplier_key, store_key, DATE '2026-11-11', stock_employee_key)
    RETURNING receipt_id INTO store_receipt_key;
    INSERT INTO inventory.goods_receipt (receipt_no, supplier_id, location_id, received_on, received_by)
    VALUES ('O2C-EX-R02', supplier_key, warehouse_key, DATE '2026-11-11', stock_employee_key)
    RETURNING receipt_id INTO warehouse_receipt_key;
    INSERT INTO inventory.goods_receipt (receipt_no, supplier_id, location_id, received_on, received_by)
    VALUES ('O2C-EX-R03', supplier_key, warehouse_key, DATE '2026-11-20', stock_employee_key)
    RETURNING receipt_id INTO later_receipt_key;
    INSERT INTO inventory.goods_receipt_line (receipt_id, line_no, item_id, quantity)
    VALUES (store_receipt_key, 1, chair_key, 5), (store_receipt_key, 2, desk_key, 2),
           (store_receipt_key, 3, metre_key, 0.001), (warehouse_receipt_key, 1, chair_key, 1),
           (later_receipt_key, 1, chair_key, 1);

    INSERT INTO inventory.inventory_movement
        (movement_no, movement_type, location_id, item_id, order_line_id, moved_on, quantity, recorded_by)
    SELECT examples.movement_no, 'SALE_ISSUE', examples.location_id, line.item_id,
           line.order_line_id, examples.moved_on, examples.quantity, stock_employee_key
    FROM (VALUES ('O2C-EX-I01', orders[4], 1, store_key, DATE '2026-11-12', 1::numeric),
                 ('O2C-EX-I02', orders[5], 1, store_key, DATE '2026-11-12', 1),
                 ('O2C-EX-I03', orders[6], 1, store_key, DATE '2026-11-12', 1),
                 ('O2C-EX-I04', orders[6], 1, warehouse_key, DATE '2026-11-13', 1),
                 ('O2C-EX-I05', orders[6], 2, store_key, DATE '2026-11-13', 1),
                 ('O2C-EX-I06', orders[7], 1, store_key, DATE '2026-11-12', 1),
                 ('O2C-EX-I07', orders[8], 1, store_key, DATE '2026-11-13', 1),
                 ('O2C-EX-I08', orders[9], 1, store_key, DATE '2026-11-13', 0.001),
                 ('O2C-EX-I09', orders[10], 1, store_key, DATE '2026-11-13', 1))
        AS examples(movement_no, order_id, line_no, location_id, moved_on, quantity)
    JOIN sales.sales_order_line AS line USING (order_id, line_no);

    INSERT INTO sales.customer_invoice (invoice_no, order_id, issued_on, due_on, issued_by)
    SELECT 'O2C-EX-INV-' || LPAD(example_number::text, 2, '0'), orders[example_number],
           DATE '2026-11-14', CASE WHEN example_number = 7 THEN DATE '2026-11-14' ELSE DATE '2026-11-30' END,
           finance_employee_key
    FROM generate_series(5, 9) AS examples(example_number);

    INSERT INTO sales.customer_payment (payment_no, invoice_id, received_on, amount, recorded_by)
    SELECT examples.payment_no, invoice.invoice_id, examples.received_on, examples.amount, finance_employee_key
    FROM (VALUES ('O2C-EX-P01', 'O2C-EX-INV-06', DATE '2026-11-15', 1000.00),
                 ('O2C-EX-P02', 'O2C-EX-INV-06', DATE '2026-11-18', 500.00),
                 ('O2C-EX-P03', 'O2C-EX-INV-07', DATE '2026-11-14', 2500.00),
                 ('O2C-EX-P04', 'O2C-EX-INV-08', DATE '2026-11-16', 50.00),
                 ('O2C-EX-P05', 'O2C-EX-INV-08', DATE '2026-11-17', 70.00),
                 ('O2C-EX-P06', 'O2C-EX-INV-09', DATE '2026-11-15', 0.01))
        AS examples(payment_no, invoice_no, received_on, amount)
    JOIN sales.customer_invoice AS invoice USING (invoice_no);

    SELECT order_line_id INTO STRICT draft_line FROM sales.sales_order_line WHERE order_id = orders[2];
    SELECT order_line_id INTO STRICT unissued_line FROM sales.sales_order_line WHERE order_id = orders[3];
    SELECT order_line_id INTO STRICT partial_line FROM sales.sales_order_line WHERE order_id = orders[4];
    SELECT invoice_id INTO STRICT unpaid_invoice FROM sales.customer_invoice WHERE order_id = orders[5];
    SELECT invoice_id INTO STRICT partial_invoice FROM sales.customer_invoice WHERE order_id = orders[6];

    PERFORM pg_temp.expect_o2c_failure('Direct confirmed insert', '23514', FORMAT(
        'INSERT INTO sales.sales_order (order_no, customer_id, ordered_on, currency_code, created_by, status) VALUES (%L,%s,%L,%L,%s,%L)',
        'O2C-BAD-STATUS', customer_key, '2026-11-10', 'TRY', employee_key, 'CONFIRMED'));
    PERFORM pg_temp.expect_o2c_failure('Invalid currency format', '23514', FORMAT(
        'INSERT INTO sales.sales_order (order_no, customer_id, ordered_on, currency_code, created_by) VALUES (%L,%s,%L,%L,%s)',
        'O2C-BAD-CURRENCY', customer_key, '2026-11-10', '12', employee_key));
    PERFORM pg_temp.expect_o2c_failure('Empty order confirmation', '23514', FORMAT(
        'UPDATE sales.sales_order SET status = %L WHERE order_id = %s', 'CONFIRMED', orders[1]));
    PERFORM pg_temp.expect_o2c_failure('Confirmed header change', '23514', FORMAT(
        'UPDATE sales.sales_order SET currency_code = %L WHERE order_id = %s', 'USD', orders[3]));
    PERFORM pg_temp.expect_o2c_failure('Confirmed header deletion', '23514', FORMAT(
        'DELETE FROM sales.sales_order WHERE order_id = %s', orders[3]));
    PERFORM pg_temp.expect_o2c_failure('Confirmed line change', '23514', FORMAT(
        'UPDATE sales.sales_order_line SET quantity = 4 WHERE order_line_id = %s', unissued_line));
    PERFORM pg_temp.expect_o2c_failure('Move line to another order', '23514', FORMAT(
        'UPDATE sales.sales_order_line SET order_id = %s WHERE order_line_id = %s', orders[1], draft_line));
    PERFORM pg_temp.expect_o2c_failure('Repeated line number', '23505', FORMAT(line_statement, orders[2], 1, chair_key, 1, 2500));
    PERFORM pg_temp.expect_o2c_failure('Zero line number', '23514', FORMAT(line_statement, orders[2], 0, chair_key, 1, 2500));
    PERFORM pg_temp.expect_o2c_failure('Zero line quantity', '23514', FORMAT(line_statement, orders[2], 2, chair_key, 0, 2500));
    PERFORM pg_temp.expect_o2c_failure('Negative unit price', '23514', FORMAT(line_statement, orders[2], 2, chair_key, 1, -1));
    PERFORM pg_temp.expect_o2c_failure('Non-sellable item', '23514', FORMAT(line_statement, orders[2], 2, non_sellable_key, 1, 2500));
    PERFORM pg_temp.expect_o2c_failure('Inactive item', '23514', FORMAT(line_statement, orders[2], 2, inactive_key, 1, 2500));
    PERFORM pg_temp.expect_o2c_failure('Draft stock issue', '23514', FORMAT(receipt_statement,
        'O2C-BAD-DRAFT', 'SALE_ISSUE', store_key, chair_key, draft_line, '2026-11-14', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Issue before order', '23514', FORMAT(receipt_statement,
        'O2C-BAD-DATE', 'SALE_ISSUE', store_key, chair_key, unissued_line, '2026-11-09', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Issue mismatched item', '23503', FORMAT(receipt_statement,
        'O2C-BAD-ITEM', 'SALE_ISSUE', store_key, desk_key, unissued_line, '2026-11-14', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Issue without order line', '23514', FORMAT(receipt_statement,
        'O2C-BAD-NOLINE', 'SALE_ISSUE', store_key, chair_key, 'NULL', '2026-11-14', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Receipt with order line', '23514', FORMAT(receipt_statement,
        'O2C-BAD-RECEIPT', 'RECEIPT', store_key, chair_key, unissued_line, '2026-11-14', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Receipt of zero units', '23514', FORMAT(receipt_statement,
        'O2C-BAD-ZERO', 'RECEIPT', store_key, chair_key, 'NULL', '2026-11-14', 0, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Receipt without source document', '23514', FORMAT(receipt_statement,
        'O2C-BAD-NORECEIPT', 'RECEIPT', store_key, chair_key, 'NULL', '2026-11-14', 1, stock_employee_key));
    PERFORM pg_temp.expect_o2c_failure('Duplicate receipt line', '23505', FORMAT(
        'INSERT INTO inventory.goods_receipt_line (receipt_id,line_no,item_id,quantity) VALUES (%s,1,%s,5)',
        store_receipt_key, chair_key));
    PERFORM pg_temp.expect_o2c_failure('Direct modification of stock balance', '55000',
        'UPDATE inventory.stock_balance SET quantity_on_hand = quantity_on_hand + 10');
    PERFORM pg_temp.expect_o2c_failure('Issue dated before receipt', '23514', FORMAT(receipt_statement,
        'O2C-BAD-FUTURE-IN', 'SALE_ISSUE', warehouse_key, chair_key, unissued_line, '2026-11-10', 1, stock_employee_key),
        'Insufficient stock');
    PERFORM pg_temp.expect_o2c_failure('Backdated issue breaks later stock', '23514', FORMAT(receipt_statement,
        'O2C-BAD-HISTORY', 'SALE_ISSUE', warehouse_key, chair_key, unissued_line, '2026-11-12', 1, stock_employee_key),
        'Insufficient stock');
    PERFORM pg_temp.expect_o2c_failure('Insufficient stock', '23514', FORMAT(receipt_statement,
        'O2C-BAD-STOCK', 'SALE_ISSUE', store_key, chair_key, unissued_line, '2026-11-14', 2, employee_key),
        'Insufficient stock');
    PERFORM pg_temp.expect_o2c_failure('Issue above ordered quantity', '23514', FORMAT(receipt_statement,
        'O2C-BAD-OVERISSUE', 'SALE_ISSUE', store_key, chair_key, partial_line, '2026-11-14', 2, employee_key),
        'Stock issues exceed the order line quantity');
    PERFORM pg_temp.expect_o2c_failure('Invoice before full shipment', '23514', FORMAT(invoice_statement,
        'O2C-BAD-EARLY-INV', orders[4], '2026-11-14', '2026-11-30', employee_key));
    PERFORM pg_temp.expect_o2c_failure('Invoice due before issue date', '23514', FORMAT(invoice_statement,
        'O2C-BAD-DUE', orders[5], '2026-11-14', '2026-11-13', employee_key));
    PERFORM pg_temp.expect_o2c_failure('Second invoice for same order', '23505', FORMAT(invoice_statement,
        'O2C-BAD-SECOND', orders[5], '2026-11-14', '2026-11-30', employee_key));
    PERFORM pg_temp.expect_o2c_failure('Payment without invoice', '23503', FORMAT(payment_statement,
        'O2C-BAD-MISSING', -1, '2026-11-14', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Payment dated before invoice', '23514', FORMAT(payment_statement,
        'O2C-BAD-PAYDATE', unpaid_invoice, '2026-11-13', 1, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Zero payment', '23514', FORMAT(payment_statement,
        'O2C-BAD-PAYZERO', unpaid_invoice, '2026-11-14', 0, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Overpayment by one cent', '23514', FORMAT(payment_statement,
        'O2C-BAD-OVERPAY', partial_invoice, '2026-11-19', 3500.01, employee_key));
    PERFORM pg_temp.expect_o2c_failure('Posted movement deletion', '23514',
        'DELETE FROM inventory.inventory_movement WHERE movement_no = ''O2C-EX-I01''');
    PERFORM pg_temp.expect_o2c_failure('Posted invoice change', '23514', FORMAT(
        'UPDATE sales.customer_invoice SET total_amount = 1 WHERE invoice_id = %s', unpaid_invoice));
    PERFORM pg_temp.expect_o2c_failure('Posted payment change', '23514',
        'UPDATE sales.customer_payment SET amount = 1 WHERE payment_no = ''O2C-EX-P01''');

    IF (SELECT COUNT(*) FROM sales.sales_order WHERE order_no LIKE 'O2C-EX-%') <> 10
       OR (SELECT COUNT(*) FROM sales.customer_invoice WHERE invoice_no LIKE 'O2C-EX-%') <> 5
       OR (SELECT COUNT(*) FROM sales.customer_payment WHERE payment_no LIKE 'O2C-EX-%') <> 6 THEN
        RAISE EXCEPTION 'Unexpected number of O2C example rows';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM inventory.goods_receipt AS receipt
        JOIN inventory.goods_receipt_line AS received USING (receipt_id)
        JOIN inventory.inventory_movement AS stock_in ON stock_in.receipt_line_id = received.receipt_line_id
        JOIN inventory.inventory_movement AS stock_out ON stock_out.location_id = stock_in.location_id
             AND stock_out.item_id = stock_in.item_id AND stock_out.moved_on >= stock_in.moved_on
        JOIN sales.sales_order_line AS line ON line.order_line_id = stock_out.order_line_id
        JOIN sales.sales_order AS sale ON sale.order_id = line.order_id
        JOIN public.customer AS customer ON customer.customer_id = sale.customer_id
        JOIN sales.customer_invoice AS invoice ON invoice.order_id = sale.order_id
        JOIN sales.customer_payment AS payment ON payment.invoice_id = invoice.invoice_id
        WHERE receipt.receipt_no = 'O2C-EX-R01' AND sale.order_no = 'O2C-EX-07'
          AND customer.customer_type = 'BIREYSEL'
          AND sale.created_by = employee_key AND stock_out.recorded_by = stock_employee_key
          AND invoice.issued_by = finance_employee_key AND payment.recorded_by = finance_employee_key
    ) THEN
        RAISE EXCEPTION 'Individual customer and cross-role receipt-to-cash case is missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM (VALUES ('O2C-EX-INV-05', 2500.00, 0.00, 2500.00),
                              ('O2C-EX-INV-06', 5000.00, 1500.00, 3500.00),
                              ('O2C-EX-INV-07', 2500.00, 2500.00, 0.00),
                              ('O2C-EX-INV-08', 120.00, 120.00, 0.00),
                              ('O2C-EX-INV-09', 0.01, 0.01, 0.00))
            AS expected(invoice_no, total_amount, paid_amount, balance_due)
        LEFT JOIN sales.customer_invoice_balance AS actual USING (invoice_no)
        WHERE (actual.total_amount, actual.paid_amount, actual.balance_due)
              IS DISTINCT FROM (expected.total_amount, expected.paid_amount, expected.balance_due)
    ) THEN
        RAISE EXCEPTION 'Unexpected invoice total or payment balance';
    END IF;
END;
$$;

COMMIT;

SELECT sale.order_no,
       CASE
           WHEN sale.status = 'DRAFT' AND ordered.line_count = 0 THEN 'EMPTY DRAFT'
           WHEN sale.status = 'DRAFT' THEN 'DRAFT WITH LINES'
           WHEN issued.quantity = 0 THEN 'CONFIRMED UNISSUED'
           WHEN issued.quantity < ordered.quantity THEN 'PARTIALLY ISSUED'
           WHEN balance.invoice_id IS NULL THEN 'FULLY ISSUED NOT INVOICED'
           WHEN balance.paid_amount = 0 THEN 'INVOICED UNPAID'
           WHEN balance.balance_due > 0 THEN 'PARTIALLY PAID'
           ELSE 'PAID IN FULL'
       END AS example_state,
       ordered.line_count, ordered.quantity AS ordered_qty, issued.quantity AS issued_qty,
       sale.currency_code, balance.invoice_no,
       balance.total_amount, balance.paid_amount, balance.balance_due,
       (SELECT COUNT(*) FROM sales.customer_payment AS payment WHERE payment.invoice_id = balance.invoice_id) AS payment_count
FROM sales.sales_order AS sale
LEFT JOIN sales.customer_invoice_balance AS balance USING (order_no)
CROSS JOIN LATERAL (
    SELECT COUNT(*) AS line_count, COALESCE(SUM(quantity), 0) AS quantity
    FROM sales.sales_order_line WHERE order_id = sale.order_id
) AS ordered
CROSS JOIN LATERAL (
    SELECT COALESCE(SUM(movement.quantity), 0) AS quantity
    FROM inventory.inventory_movement AS movement
    JOIN sales.sales_order_line AS line USING (order_line_id)
    WHERE line.order_id = sale.order_id
) AS issued
WHERE sale.order_no LIKE 'O2C-EX-%'
ORDER BY sale.order_no;
