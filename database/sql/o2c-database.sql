BEGIN;

CREATE SCHEMA sales;
CREATE SCHEMA inventory;

CREATE TABLE sales.sales_order (
    order_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no      VARCHAR(24) NOT NULL UNIQUE,
    customer_id   INTEGER NOT NULL REFERENCES public.customer (customer_id),
    ordered_on    DATE NOT NULL,
    currency_code VARCHAR(3) NOT NULL CHECK (currency_code ~ '^[A-Z]{3}$'),
    created_by    INTEGER NOT NULL REFERENCES public.employee (employee_id),
    status        VARCHAR(12) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'CONFIRMED'))
);

CREATE TABLE sales.sales_order_line (
    order_line_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      INTEGER NOT NULL REFERENCES sales.sales_order (order_id),
    line_no       INTEGER NOT NULL CHECK (line_no > 0),
    item_id       INTEGER NOT NULL REFERENCES public.item (item_id),
    quantity      NUMERIC(12,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0 AND unit_price <> 'NaN'::numeric),
    UNIQUE (order_id, line_no),
    UNIQUE (order_line_id, item_id)
);

CREATE TABLE inventory.stock_location (
    location_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_code VARCHAR(24) NOT NULL UNIQUE,
    location_name VARCHAR(100) NOT NULL,
    location_type VARCHAR(12) NOT NULL CHECK (location_type IN ('STORE', 'WAREHOUSE'))
);

CREATE TABLE inventory.stock_key (
    location_id INTEGER NOT NULL REFERENCES inventory.stock_location (location_id),
    item_id     INTEGER NOT NULL REFERENCES public.item (item_id),
    PRIMARY KEY (location_id, item_id)
);

CREATE TABLE inventory.goods_receipt (
    receipt_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_no  VARCHAR(24) NOT NULL UNIQUE,
    supplier_id INTEGER NOT NULL REFERENCES public.supplier (supplier_id),
    location_id INTEGER NOT NULL REFERENCES inventory.stock_location (location_id),
    received_on DATE NOT NULL,
    received_by INTEGER NOT NULL REFERENCES public.employee (employee_id)
);

CREATE TABLE inventory.goods_receipt_line (
    receipt_line_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_id      INTEGER NOT NULL REFERENCES inventory.goods_receipt (receipt_id),
    line_no         INTEGER NOT NULL CHECK (line_no > 0),
    item_id         INTEGER NOT NULL REFERENCES public.item (item_id),
    quantity        NUMERIC(12,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    UNIQUE (receipt_id, line_no)
);

CREATE TABLE inventory.inventory_movement (
    movement_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    movement_no   VARCHAR(32) NOT NULL UNIQUE,
    movement_type VARCHAR(12) NOT NULL CHECK (movement_type IN ('RECEIPT', 'SALE_ISSUE')),
    location_id   INTEGER NOT NULL REFERENCES inventory.stock_location (location_id),
    item_id       INTEGER NOT NULL REFERENCES public.item (item_id),
    order_line_id INTEGER,
    receipt_line_id INTEGER UNIQUE REFERENCES inventory.goods_receipt_line (receipt_line_id),
    moved_on      DATE NOT NULL,
    quantity      NUMERIC(12,3) NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    recorded_by   INTEGER NOT NULL REFERENCES public.employee (employee_id),
    FOREIGN KEY (order_line_id, item_id) REFERENCES sales.sales_order_line (order_line_id, item_id),
    CHECK ((movement_type = 'SALE_ISSUE' AND order_line_id IS NOT NULL AND receipt_line_id IS NULL)
        OR (movement_type = 'RECEIPT' AND receipt_line_id IS NOT NULL AND order_line_id IS NULL))
);

CREATE TABLE sales.customer_invoice (
    invoice_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_no   VARCHAR(24) NOT NULL UNIQUE,
    order_id     INTEGER NOT NULL UNIQUE REFERENCES sales.sales_order (order_id),
    issued_on    DATE NOT NULL,
    due_on       DATE NOT NULL CHECK (due_on >= issued_on),
    total_amount NUMERIC(22,2) NOT NULL CHECK (total_amount > 0 AND total_amount <> 'NaN'::numeric),
    issued_by    INTEGER NOT NULL REFERENCES public.employee (employee_id)
);

CREATE TABLE sales.customer_payment (
    payment_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_no  VARCHAR(32) NOT NULL UNIQUE,
    invoice_id  INTEGER NOT NULL REFERENCES sales.customer_invoice (invoice_id),
    received_on DATE NOT NULL,
    amount      NUMERIC(22,2) NOT NULL CHECK (amount > 0 AND amount <> 'NaN'::numeric),
    recorded_by INTEGER NOT NULL REFERENCES public.employee (employee_id)
);

CREATE INDEX ix_sales_order_customer ON sales.sales_order (customer_id);
CREATE INDEX ix_inventory_movement_line ON inventory.inventory_movement (order_line_id);
CREATE INDEX ix_inventory_movement_stock_date ON inventory.inventory_movement (location_id, item_id, moved_on);
CREATE INDEX ix_customer_payment_invoice ON sales.customer_payment (invoice_id);

CREATE FUNCTION sales.guard_order() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'DRAFT' THEN
            RAISE EXCEPTION 'Create the order as a draft before confirming it' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'CONFIRMED' THEN
            RAISE EXCEPTION 'A confirmed order cannot be deleted' USING ERRCODE = '23514';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status = 'CONFIRMED' AND NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'A confirmed order cannot be changed' USING ERRCODE = '23514';
    END IF;
    IF OLD.status = 'DRAFT' AND NEW.status = 'CONFIRMED' AND NOT EXISTS (
        SELECT 1 FROM sales.sales_order_line WHERE order_id = OLD.order_id
    ) THEN
        RAISE EXCEPTION 'An order needs at least one line before confirmation' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_order BEFORE INSERT OR UPDATE OR DELETE ON sales.sales_order
FOR EACH ROW EXECUTE FUNCTION sales.guard_order();

CREATE FUNCTION sales.guard_order_line() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    target_order_id INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.order_id, NEW.order_line_id) <> (OLD.order_id, OLD.order_line_id) THEN
        RAISE EXCEPTION 'An order line cannot change its identity or order' USING ERRCODE = '23514';
    END IF;

    target_order_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    UPDATE sales.sales_order SET status = status WHERE order_id = target_order_id AND status = 'DRAFT';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order lines can only be edited for a draft order' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.item WHERE item_id = NEW.item_id AND is_sellable AND is_active) THEN
        RAISE EXCEPTION 'The item must be active and sellable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_order_line BEFORE INSERT OR UPDATE OR DELETE ON sales.sales_order_line
FOR EACH ROW EXECUTE FUNCTION sales.guard_order_line();

CREATE FUNCTION sales.lock_confirmed_order(target_order_id INTEGER, event_date DATE) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sales.sales_order
    SET status = status
    WHERE order_id = target_order_id AND status = 'CONFIRMED' AND ordered_on <= event_date;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'A confirmed order on or before the event date is required' USING ERRCODE = '23514';
    END IF;
END;
$$;

CREATE FUNCTION inventory.apply_movement() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    target_order_id INTEGER;
    ordered_quantity NUMERIC;
    issued_quantity NUMERIC;
BEGIN
    IF NEW.movement_type = 'RECEIPT' THEN
        IF NOT EXISTS (
            SELECT 1 FROM inventory.goods_receipt_line AS line
            JOIN inventory.goods_receipt AS receipt USING (receipt_id)
            WHERE line.receipt_line_id = NEW.receipt_line_id
              AND (receipt.location_id, line.item_id, receipt.received_on, line.quantity, receipt.received_by)
                  = (NEW.location_id, NEW.item_id, NEW.moved_on, NEW.quantity, NEW.recorded_by)
        ) THEN
            RAISE EXCEPTION 'Stock receipt must match its goods receipt line' USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT order_id INTO target_order_id FROM sales.sales_order_line WHERE order_line_id = NEW.order_line_id;
        PERFORM sales.lock_confirmed_order(target_order_id, NEW.moved_on);
        SELECT quantity INTO ordered_quantity FROM sales.sales_order_line WHERE order_line_id = NEW.order_line_id;
        SELECT COALESCE(SUM(quantity), 0) INTO issued_quantity
        FROM inventory.inventory_movement WHERE order_line_id = NEW.order_line_id;
        IF issued_quantity > ordered_quantity THEN
            RAISE EXCEPTION 'Stock issues exceed the order line quantity' USING ERRCODE = '23514';
        END IF;
    END IF;

    INSERT INTO inventory.stock_key (location_id, item_id) VALUES (NEW.location_id, NEW.item_id)
    ON CONFLICT (location_id, item_id) DO UPDATE SET item_id = EXCLUDED.item_id;

    IF NEW.movement_type = 'SALE_ISSUE' AND EXISTS (
        SELECT 1 FROM (
            SELECT SUM(SUM(CASE WHEN movement_type = 'RECEIPT' THEN quantity ELSE -quantity END))
                   OVER (ORDER BY moved_on ROWS UNBOUNDED PRECEDING) AS end_of_day_balance
            FROM inventory.inventory_movement
            WHERE location_id = NEW.location_id AND item_id = NEW.item_id
            GROUP BY moved_on
        ) AS ledger WHERE ledger.end_of_day_balance < 0
    ) THEN
        RAISE EXCEPTION 'Insufficient stock at the selected location on a ledger date' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_apply_movement AFTER INSERT ON inventory.inventory_movement
FOR EACH ROW EXECUTE FUNCTION inventory.apply_movement();

CREATE FUNCTION inventory.post_goods_receipt_line() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.item WHERE item_id = NEW.item_id AND is_purchasable AND is_active) THEN
        RAISE EXCEPTION 'Received item must be active and purchasable' USING ERRCODE = '23514';
    END IF;
    INSERT INTO inventory.inventory_movement
        (movement_no, movement_type, location_id, item_id, receipt_line_id, moved_on, quantity, recorded_by)
    SELECT 'GR:' || NEW.receipt_line_id, 'RECEIPT', receipt.location_id, NEW.item_id, NEW.receipt_line_id,
           receipt.received_on, NEW.quantity, receipt.received_by
    FROM inventory.goods_receipt AS receipt WHERE receipt.receipt_id = NEW.receipt_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_post_goods_receipt_line AFTER INSERT ON inventory.goods_receipt_line
FOR EACH ROW EXECUTE FUNCTION inventory.post_goods_receipt_line();

CREATE FUNCTION sales.prepare_invoice() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    PERFORM sales.lock_confirmed_order(NEW.order_id, NEW.issued_on);
    IF EXISTS (
        SELECT 1 FROM sales.sales_order_line AS line
        WHERE line.order_id = NEW.order_id AND line.quantity <> (
            SELECT COALESCE(SUM(movement.quantity), 0)
            FROM inventory.inventory_movement AS movement
            WHERE movement.order_line_id = line.order_line_id AND movement.moved_on <= NEW.issued_on
        )
    ) THEN
        RAISE EXCEPTION 'The order must be fully issued before invoicing' USING ERRCODE = '23514';
    END IF;

    SELECT SUM(ROUND(quantity * unit_price, 2)) INTO NEW.total_amount
    FROM sales.sales_order_line WHERE order_id = NEW.order_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prepare_invoice BEFORE INSERT ON sales.customer_invoice
FOR EACH ROW EXECUTE FUNCTION sales.prepare_invoice();

CREATE FUNCTION sales.guard_payment() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    invoice_total NUMERIC;
    invoice_date DATE;
    paid_total NUMERIC;
BEGIN
    UPDATE sales.customer_invoice SET total_amount = total_amount WHERE invoice_id = NEW.invoice_id
    RETURNING total_amount, issued_on INTO invoice_total, invoice_date;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'The payment must reference an existing invoice' USING ERRCODE = '23503';
    END IF;
    IF NEW.received_on < invoice_date THEN
        RAISE EXCEPTION 'The payment date cannot precede the invoice date' USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(SUM(amount), 0) INTO paid_total FROM sales.customer_payment WHERE invoice_id = NEW.invoice_id;
    IF paid_total > invoice_total THEN
        RAISE EXCEPTION 'The payment exceeds the outstanding balance' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_payment AFTER INSERT ON sales.customer_payment
FOR EACH ROW EXECUTE FUNCTION sales.guard_payment();

CREATE FUNCTION sales.guard_posted_record() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Posted records cannot be changed or deleted in this prototype' USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER trg_keep_stock_movement BEFORE UPDATE OR DELETE ON inventory.inventory_movement
FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();
CREATE TRIGGER trg_prevent_movement_truncate BEFORE TRUNCATE ON inventory.inventory_movement
FOR EACH STATEMENT EXECUTE FUNCTION sales.guard_posted_record();
CREATE TRIGGER trg_keep_goods_receipt BEFORE UPDATE OR DELETE ON inventory.goods_receipt
FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();
CREATE TRIGGER trg_keep_goods_receipt_line BEFORE UPDATE OR DELETE ON inventory.goods_receipt_line
FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();
CREATE TRIGGER trg_keep_invoice BEFORE UPDATE OR DELETE ON sales.customer_invoice
FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();
CREATE TRIGGER trg_keep_payment BEFORE UPDATE OR DELETE ON sales.customer_payment
FOR EACH ROW EXECUTE FUNCTION sales.guard_posted_record();

CREATE VIEW inventory.stock_balance AS
SELECT location_id, item_id,
       SUM(CASE WHEN movement_type = 'RECEIPT' THEN quantity ELSE -quantity END) AS quantity_on_hand
FROM inventory.inventory_movement
GROUP BY location_id, item_id;

CREATE VIEW sales.customer_invoice_balance AS
SELECT invoice.invoice_id,
       invoice.invoice_no,
       sale.order_no,
       sale.customer_id,
       sale.currency_code,
       invoice.total_amount,
       COALESCE(SUM(payment.amount), 0.00) AS paid_amount,
       invoice.total_amount - COALESCE(SUM(payment.amount), 0.00) AS balance_due
FROM sales.customer_invoice AS invoice
JOIN sales.sales_order AS sale ON sale.order_id = invoice.order_id
LEFT JOIN sales.customer_payment AS payment ON payment.invoice_id = invoice.invoice_id
GROUP BY invoice.invoice_id, sale.order_no, sale.customer_id, sale.currency_code;

COMMIT;
