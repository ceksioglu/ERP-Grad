-- ============================================================================
-- MISY4901 Retail ERP Graduation Project
-- Subsystem: Purchase-to-Pay (P2P) Module Schema & Integration Script
-- File: database/sql/p2p_schema.sql
-- Role: Senior PostgreSQL Database Architect (P2P Module Lead)
-- Compatibility: PostgreSQL 14+ (Verified for pgAdmin 4 & psql)
-- ============================================================================
-- Architecture & Repository Integration Notes:
-- 1. Alignment with Core Masters (public.*):
--    - References master entities established in db_init.sql:
--      public.department, public.employee, public.supplier, public.item
-- 2. Schema Strategy:
--    - Creates and isolates operational tables inside the 'purchasing' schema,
--      mirroring the 'sales' schema in O2C and 'production' in P2M.
-- 3. Stock & Inventory Interface (inventory.*):
--    - Idempotently ensures inventory.stock_location exists (matching o2c-database.sql).
--    - Replaces the placeholder unlinked inventory.goods_receipt with a fully
--      auditable, PO-linked receiving flow (purchasing.goods_receipt & lines).
-- 4. Full Enterprise P2P Lifecycle:
--    Requisition (PR) -> Purchase Order (PO) -> Goods Receipt (GR) ->
--    Supplier Invoice (Bill) -> 3-Way Match Verification -> Supplier Payment & Allocations
-- ============================================================================

BEGIN;

SET client_encoding = 'UTF8';

-- ----------------------------------------------------------------------------
-- 0. SCHEMA DEFINITION & SHARED INTERFACES
-- ----------------------------------------------------------------------------

-- Ensure required schemas exist
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS purchasing;

-- Idempotently clean existing purchasing objects for repeatable runs
DROP SCHEMA IF EXISTS purchasing CASCADE;
CREATE SCHEMA purchasing;

-- Ensure stock location table exists (shared with O2C and P2M)
CREATE TABLE IF NOT EXISTS inventory.stock_location (
    location_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    location_code VARCHAR(24)  NOT NULL UNIQUE,
    location_name VARCHAR(100) NOT NULL,
    location_type VARCHAR(12)  NOT NULL CHECK (location_type IN ('STORE', 'WAREHOUSE'))
);

-- Seed baseline stock locations if not already present
INSERT INTO inventory.stock_location (location_code, location_name, location_type)
VALUES
    ('WH-CENTRAL',   'Merkez Lojistik Deposu',      'WAREHOUSE'),
    ('STORE-IST-01', 'Karaköy Perakende Mağazası',  'STORE'),
    ('STORE-ANK-01', 'Çankaya Perakende Mağazası',  'STORE'),
    ('STORE-IZM-01', 'Alsancak Perakende Mağazası', 'STORE'),
    ('WH-BURSA',     'Bursa Bölge Dağıtım Deposu',  'WAREHOUSE')
ON CONFLICT (location_code) DO NOTHING;


-- ============================================================================
-- 1. PURCHASE REQUISITION (İç Satın Alma Talebi)
-- ============================================================================

CREATE TABLE purchasing.purchase_requisition (
    requisition_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requisition_no    VARCHAR(24)  NOT NULL UNIQUE,
    department_id     INTEGER      NOT NULL REFERENCES public.department (department_id),
    requested_by      INTEGER      NOT NULL REFERENCES public.employee (employee_id),
    requisition_date  DATE         NOT NULL DEFAULT CURRENT_DATE,
    required_by_date  DATE         NOT NULL,
    priority          VARCHAR(10)  NOT NULL DEFAULT 'MEDIUM'
                      CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH', 'URGENT')),
    status            VARCHAR(15)  NOT NULL DEFAULT 'DRAFT'
                      CHECK (status IN ('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'CLOSED', 'CANCELLED')),
    approved_by       INTEGER      REFERENCES public.employee (employee_id),
    approved_at       TIMESTAMPTZ,
    justification     TEXT,
    notes             TEXT,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_pr_required_date CHECK (required_by_date >= requisition_date),
    CONSTRAINT chk_pr_approval_consistency CHECK (
        (status = 'APPROVED' AND approved_by IS NOT NULL AND approved_at IS NOT NULL) OR
        (status <> 'APPROVED')
    )
);

CREATE TABLE purchasing.purchase_requisition_line (
    requisition_line_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    requisition_id       INTEGER        NOT NULL REFERENCES purchasing.purchase_requisition (requisition_id) ON DELETE CASCADE,
    line_no              INTEGER        NOT NULL CHECK (line_no > 0),
    item_id              INTEGER        NOT NULL REFERENCES public.item (item_id),
    quantity             NUMERIC(12,3)  NOT NULL CHECK (quantity > 0 AND quantity <> 'NaN'::numeric),
    estimated_unit_cost  NUMERIC(12,2)  CHECK (estimated_unit_cost >= 0 AND estimated_unit_cost <> 'NaN'::numeric),
    line_total           NUMERIC(22,2)  GENERATED ALWAYS AS (ROUND(quantity * COALESCE(estimated_unit_cost, 0), 2)) STORED,
    notes                TEXT,

    UNIQUE (requisition_id, line_no),
    UNIQUE (requisition_line_id, item_id)
);

CREATE INDEX ix_pr_dept ON purchasing.purchase_requisition (department_id);
CREATE INDEX ix_pr_requester ON purchasing.purchase_requisition (requested_by);
CREATE INDEX ix_pr_line_item ON purchasing.purchase_requisition_line (item_id);


-- ============================================================================
-- 2. PURCHASE ORDER (Satın Alma Siparişi)
-- ============================================================================

CREATE TABLE purchasing.purchase_order (
    order_id                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    po_no                   VARCHAR(24)  NOT NULL UNIQUE,
    requisition_id          INTEGER      REFERENCES purchasing.purchase_requisition (requisition_id),
    supplier_id             INTEGER      NOT NULL REFERENCES public.supplier (supplier_id),
    order_date              DATE         NOT NULL DEFAULT CURRENT_DATE,
    expected_delivery_date  DATE         NOT NULL,
    payment_terms_days      INTEGER      NOT NULL DEFAULT 30 CHECK (payment_terms_days >= 0),
    currency_code           VARCHAR(3)   NOT NULL DEFAULT 'TRY' CHECK (currency_code ~ '^[A-Z]{3}$'),
    created_by              INTEGER      NOT NULL REFERENCES public.employee (employee_id),
    approved_by             INTEGER      REFERENCES public.employee (employee_id),
    status                  VARCHAR(20)  NOT NULL DEFAULT 'DRAFT'
                            CHECK (status IN ('DRAFT', 'APPROVED', 'SENT', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED', 'CANCELLED')),
    shipping_address        TEXT,
    notes                   TEXT,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_po_delivery_date CHECK (expected_delivery_date >= order_date)
);

CREATE TABLE purchasing.purchase_order_line (
    order_line_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id             INTEGER        NOT NULL REFERENCES purchasing.purchase_order (order_id) ON DELETE CASCADE,
    line_no              INTEGER        NOT NULL CHECK (line_no > 0),
    requisition_line_id  INTEGER        REFERENCES purchasing.purchase_requisition_line (requisition_line_id),
    item_id              INTEGER        NOT NULL REFERENCES public.item (item_id),
    ordered_quantity     NUMERIC(12,3)  NOT NULL CHECK (ordered_quantity > 0 AND ordered_quantity <> 'NaN'::numeric),
    unit_price           NUMERIC(12,2)  NOT NULL CHECK (unit_price >= 0 AND unit_price <> 'NaN'::numeric),
    line_total           NUMERIC(22,2)  GENERATED ALWAYS AS (ROUND(ordered_quantity * unit_price, 2)) STORED,
    notes                TEXT,

    UNIQUE (order_id, line_no),
    UNIQUE (order_line_id, item_id)
);

CREATE INDEX ix_po_supplier ON purchasing.purchase_order (supplier_id);
CREATE INDEX ix_po_date ON purchasing.purchase_order (order_date);
CREATE INDEX ix_po_line_item ON purchasing.purchase_order_line (item_id);


-- ============================================================================
-- 3. GOODS RECEIPT & QUALITY INSPECTION (Mal Kabul & Kalite Kontrol)
-- ============================================================================

CREATE TABLE purchasing.goods_receipt (
    receipt_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_no        VARCHAR(24)  NOT NULL UNIQUE,
    order_id          INTEGER      NOT NULL REFERENCES purchasing.purchase_order (order_id),
    supplier_id       INTEGER      NOT NULL REFERENCES public.supplier (supplier_id),
    location_id       INTEGER      NOT NULL REFERENCES inventory.stock_location (location_id),
    delivery_note_no  VARCHAR(50)  NOT NULL, -- İrsaliye No / Vendor Packing Slip
    received_on       DATE         NOT NULL DEFAULT CURRENT_DATE,
    received_by       INTEGER      NOT NULL REFERENCES public.employee (employee_id),
    inspected_by      INTEGER      REFERENCES public.employee (employee_id),
    status            VARCHAR(15)  NOT NULL DEFAULT 'RECEIVED'
                      CHECK (status IN ('RECEIVED', 'INSPECTED', 'POSTED', 'CANCELLED')),
    notes             TEXT,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchasing.goods_receipt_line (
    receipt_line_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    receipt_id         INTEGER        NOT NULL REFERENCES purchasing.goods_receipt (receipt_id) ON DELETE CASCADE,
    line_no            INTEGER        NOT NULL CHECK (line_no > 0),
    order_line_id      INTEGER        NOT NULL,
    item_id            INTEGER        NOT NULL REFERENCES public.item (item_id),
    received_quantity  NUMERIC(12,3)  NOT NULL CHECK (received_quantity > 0 AND received_quantity <> 'NaN'::numeric),
    accepted_quantity  NUMERIC(12,3)  NOT NULL CHECK (accepted_quantity >= 0 AND accepted_quantity <> 'NaN'::numeric),
    rejected_quantity  NUMERIC(12,3)  NOT NULL DEFAULT 0.000 CHECK (rejected_quantity >= 0 AND rejected_quantity <> 'NaN'::numeric),
    rejection_reason   TEXT,
    notes              TEXT,

    UNIQUE (receipt_id, line_no),
    UNIQUE (receipt_line_id, item_id),
    CONSTRAINT chk_gr_qty_balance CHECK (accepted_quantity + rejected_quantity = received_quantity),
    CONSTRAINT chk_gr_rejection_reason CHECK (rejected_quantity = 0 OR (rejected_quantity > 0 AND rejection_reason IS NOT NULL)),
    FOREIGN KEY (order_line_id, item_id) REFERENCES purchasing.purchase_order_line (order_line_id, item_id)
);

CREATE INDEX ix_gr_order ON purchasing.goods_receipt (order_id);
CREATE INDEX ix_gr_supplier ON purchasing.goods_receipt (supplier_id);
CREATE INDEX ix_gr_location ON purchasing.goods_receipt (location_id);
CREATE INDEX ix_gr_line_po_line ON purchasing.goods_receipt_line (order_line_id);


-- ============================================================================
-- 4. SUPPLIER INVOICE (Satıcı Faturası)
-- ============================================================================

CREATE TABLE purchasing.supplier_invoice (
    invoice_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_no        VARCHAR(50)    NOT NULL, -- Fatura No (e.g. GIB e-Fatura / e-Arşiv)
    supplier_id       INTEGER        NOT NULL REFERENCES public.supplier (supplier_id),
    order_id          INTEGER        NOT NULL REFERENCES purchasing.purchase_order (order_id),
    invoice_date      DATE           NOT NULL,
    due_date          DATE           NOT NULL,
    currency_code     VARCHAR(3)     NOT NULL DEFAULT 'TRY' CHECK (currency_code ~ '^[A-Z]{3}$'),
    subtotal_amount   NUMERIC(22,2)  NOT NULL CHECK (subtotal_amount >= 0 AND subtotal_amount <> 'NaN'::numeric),
    tax_amount        NUMERIC(22,2)  NOT NULL DEFAULT 0.00 CHECK (tax_amount >= 0 AND tax_amount <> 'NaN'::numeric),
    total_amount      NUMERIC(22,2)  NOT NULL CHECK (total_amount > 0 AND total_amount <> 'NaN'::numeric),
    recorded_by       INTEGER        NOT NULL REFERENCES public.employee (employee_id),
    status            VARCHAR(25)    NOT NULL DEFAULT 'RECEIVED'
                      CHECK (status IN ('RECEIVED', 'MATCHED', 'APPROVED_FOR_PAYMENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED', 'DISPUTED')),
    notes             TEXT,
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (supplier_id, invoice_no),
    CONSTRAINT chk_sinv_dates CHECK (due_date >= invoice_date),
    CONSTRAINT chk_sinv_total_sum CHECK (total_amount = subtotal_amount + tax_amount)
);

CREATE TABLE purchasing.supplier_invoice_line (
    invoice_line_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id        INTEGER        NOT NULL REFERENCES purchasing.supplier_invoice (invoice_id) ON DELETE CASCADE,
    line_no           INTEGER        NOT NULL CHECK (line_no > 0),
    order_line_id     INTEGER        NOT NULL,
    receipt_line_id   INTEGER,
    item_id           INTEGER        NOT NULL REFERENCES public.item (item_id),
    billed_quantity   NUMERIC(12,3)  NOT NULL CHECK (billed_quantity > 0 AND billed_quantity <> 'NaN'::numeric),
    unit_price        NUMERIC(12,2)  NOT NULL CHECK (unit_price >= 0 AND unit_price <> 'NaN'::numeric),
    line_total        NUMERIC(22,2)  GENERATED ALWAYS AS (ROUND(billed_quantity * unit_price, 2)) STORED,
    tax_rate          NUMERIC(5,2)   NOT NULL DEFAULT 20.00 CHECK (tax_rate >= 0),
    notes             TEXT,

    UNIQUE (invoice_id, line_no),
    FOREIGN KEY (order_line_id, item_id) REFERENCES purchasing.purchase_order_line (order_line_id, item_id),
    FOREIGN KEY (receipt_line_id, item_id) REFERENCES purchasing.goods_receipt_line (receipt_line_id, item_id)
);

CREATE INDEX ix_sinv_supplier ON purchasing.supplier_invoice (supplier_id);
CREATE INDEX ix_sinv_order ON purchasing.supplier_invoice (order_id);
CREATE INDEX ix_sinv_due_date ON purchasing.supplier_invoice (due_date);


-- ============================================================================
-- 5. THREE-WAY MATCHING (3 Yönlü Eşleştirme & Denetim)
-- ============================================================================

CREATE TABLE purchasing.three_way_match (
    match_id                 INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    match_no                 VARCHAR(32)    NOT NULL UNIQUE,
    invoice_line_id          INTEGER        NOT NULL REFERENCES purchasing.supplier_invoice_line (invoice_line_id),
    receipt_line_id          INTEGER        NOT NULL REFERENCES purchasing.goods_receipt_line (receipt_line_id),
    order_line_id            INTEGER        NOT NULL REFERENCES purchasing.purchase_order_line (order_line_id),
    matched_on               DATE           NOT NULL DEFAULT CURRENT_DATE,
    matched_by               INTEGER        NOT NULL REFERENCES public.employee (employee_id),
    ordered_quantity         NUMERIC(12,3)  NOT NULL,
    received_quantity        NUMERIC(12,3)  NOT NULL, -- accepted quantity
    billed_quantity          NUMERIC(12,3)  NOT NULL,
    po_unit_price            NUMERIC(12,2)  NOT NULL,
    invoice_unit_price       NUMERIC(12,2)  NOT NULL,
    quantity_variance        NUMERIC(12,3)  GENERATED ALWAYS AS (billed_quantity - received_quantity) STORED,
    price_variance           NUMERIC(12,2)  GENERATED ALWAYS AS (invoice_unit_price - po_unit_price) STORED,
    amount_variance          NUMERIC(22,2)  GENERATED ALWAYS AS (ROUND((billed_quantity * invoice_unit_price) - (received_quantity * po_unit_price), 2)) STORED,
    match_status             VARCHAR(25)    NOT NULL
                             CHECK (match_status IN ('EXACT_MATCH', 'WITHIN_TOLERANCE', 'QUANTITY_MISMATCH', 'PRICE_MISMATCH', 'REJECTED')),
    is_approved_for_payment  BOOLEAN        NOT NULL DEFAULT FALSE,
    variance_notes           TEXT,
    created_at               TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (invoice_line_id, receipt_line_id)
);

CREATE INDEX ix_3wm_po_line ON purchasing.three_way_match (order_line_id);
CREATE INDEX ix_3wm_gr_line ON purchasing.three_way_match (receipt_line_id);
CREATE INDEX ix_3wm_inv_line ON purchasing.three_way_match (invoice_line_id);


-- ============================================================================
-- 6. SUPPLIER PAYMENT & ALLOCATION (Tedarikçi Ödemeleri & Mahsup)
-- ============================================================================

CREATE TABLE purchasing.supplier_payment (
    payment_id      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_no      VARCHAR(32)    NOT NULL UNIQUE,
    supplier_id     INTEGER        NOT NULL REFERENCES public.supplier (supplier_id),
    payment_date    DATE           NOT NULL DEFAULT CURRENT_DATE,
    payment_method  VARCHAR(20)    NOT NULL
                    CHECK (payment_method IN ('BANK_TRANSFER', 'EFT', 'CHECK', 'CREDIT_CARD', 'CASH')),
    bank_reference  VARCHAR(64),
    currency_code   VARCHAR(3)     NOT NULL DEFAULT 'TRY' CHECK (currency_code ~ '^[A-Z]{3}$'),
    total_paid      NUMERIC(22,2)  NOT NULL CHECK (total_paid > 0 AND total_paid <> 'NaN'::numeric),
    recorded_by     INTEGER        NOT NULL REFERENCES public.employee (employee_id),
    status          VARCHAR(12)    NOT NULL DEFAULT 'POSTED'
                    CHECK (status IN ('DRAFT', 'POSTED', 'VOID')),
    notes           TEXT,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE purchasing.supplier_payment_allocation (
    allocation_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id        INTEGER        NOT NULL REFERENCES purchasing.supplier_payment (payment_id) ON DELETE CASCADE,
    invoice_id        INTEGER        NOT NULL REFERENCES purchasing.supplier_invoice (invoice_id),
    allocated_amount  NUMERIC(22,2)  NOT NULL CHECK (allocated_amount > 0 AND allocated_amount <> 'NaN'::numeric),
    notes             TEXT,

    UNIQUE (payment_id, invoice_id)
);

CREATE INDEX ix_spay_supplier ON purchasing.supplier_payment (supplier_id);
CREATE INDEX ix_spay_date ON purchasing.supplier_payment (payment_date);
CREATE INDEX ix_spay_alloc_inv ON purchasing.supplier_payment_allocation (invoice_id);


-- ============================================================================
-- 7. BUSINESS VIEWS (Analitik ve Operasyonel Görünümler)
-- ============================================================================

-- 7.1 Dynamic 3-Way Match Audit View
CREATE OR REPLACE VIEW purchasing.v_three_way_match_audit AS
SELECT
    po.po_no,
    sup.supplier_name,
    pol.line_no AS po_line_no,
    itm.item_code,
    itm.item_name,
    pol.ordered_quantity,
    pol.unit_price AS po_unit_price,
    gr.receipt_no,
    gr.delivery_note_no,
    grl.received_quantity,
    grl.accepted_quantity,
    grl.rejected_quantity,
    grl.rejection_reason,
    inv.invoice_no,
    inv.invoice_date,
    sil.billed_quantity,
    sil.unit_price AS billed_unit_price,
    ROUND(sil.billed_quantity - grl.accepted_quantity, 3) AS quantity_variance,
    ROUND(sil.unit_price - pol.unit_price, 2) AS price_variance,
    ROUND((sil.billed_quantity * sil.unit_price) - (grl.accepted_quantity * pol.unit_price), 2) AS total_variance_amount,
    CASE
        WHEN sil.billed_quantity = grl.accepted_quantity AND sil.unit_price = pol.unit_price THEN 'EXACT_MATCH'
        WHEN sil.billed_quantity <= grl.accepted_quantity AND sil.unit_price = pol.unit_price THEN 'EXACT_PRICE_PARTIAL_QTY'
        WHEN sil.billed_quantity > grl.accepted_quantity THEN 'OVERBILLED_QTY_MISMATCH'
        WHEN sil.unit_price > pol.unit_price THEN 'PRICE_MISMATCH'
        ELSE 'VARIANCE_REVIEW'
    END AS computed_match_status
FROM purchasing.supplier_invoice_line sil
JOIN purchasing.supplier_invoice inv ON inv.invoice_id = sil.invoice_id
JOIN purchasing.purchase_order po ON po.order_id = inv.order_id
JOIN purchasing.purchase_order_line pol ON pol.order_line_id = sil.order_line_id
JOIN public.item itm ON itm.item_id = sil.item_id
JOIN public.supplier sup ON sup.supplier_id = inv.supplier_id
LEFT JOIN purchasing.goods_receipt_line grl ON grl.receipt_line_id = sil.receipt_line_id
LEFT JOIN purchasing.goods_receipt gr ON gr.receipt_id = grl.receipt_id;

-- 7.2 Supplier Invoice Balance View (Parallels sales.customer_invoice_balance)
CREATE OR REPLACE VIEW purchasing.supplier_invoice_balance AS
SELECT
    inv.invoice_id,
    inv.invoice_no,
    inv.supplier_id,
    sup.supplier_name,
    po.po_no,
    inv.invoice_date,
    inv.due_date,
    inv.currency_code,
    inv.subtotal_amount,
    inv.tax_amount,
    inv.total_amount,
    COALESCE(SUM(alloc.allocated_amount), 0.00) AS paid_amount,
    ROUND(inv.total_amount - COALESCE(SUM(alloc.allocated_amount), 0.00), 2) AS balance_due,
    CASE
        WHEN COALESCE(SUM(alloc.allocated_amount), 0.00) >= inv.total_amount THEN 'PAID'
        WHEN COALESCE(SUM(alloc.allocated_amount), 0.00) > 0 THEN 'PARTIALLY_PAID'
        ELSE 'UNPAID'
    END AS payment_status
FROM purchasing.supplier_invoice inv
JOIN public.supplier sup ON sup.supplier_id = inv.supplier_id
JOIN purchasing.purchase_order po ON po.order_id = inv.order_id
LEFT JOIN purchasing.supplier_payment_allocation alloc ON alloc.invoice_id = inv.invoice_id
GROUP BY
    inv.invoice_id, inv.invoice_no, inv.supplier_id, sup.supplier_name, po.po_no,
    inv.invoice_date, inv.due_date, inv.currency_code, inv.subtotal_amount, inv.tax_amount, inv.total_amount;

-- 7.3 Purchase Order Fulfillment Status View
CREATE OR REPLACE VIEW purchasing.v_po_fulfillment_status AS
SELECT
    po.order_id,
    po.po_no,
    po.supplier_id,
    sup.supplier_name,
    pol.order_line_id,
    pol.line_no,
    pol.item_id,
    itm.item_code,
    itm.item_name,
    pol.ordered_quantity,
    COALESCE(SUM(grl.accepted_quantity), 0.000) AS received_quantity,
    COALESCE(SUM(grl.rejected_quantity), 0.000) AS rejected_quantity,
    COALESCE(SUM(sil.billed_quantity), 0.000) AS billed_quantity,
    ROUND(pol.ordered_quantity - COALESCE(SUM(grl.accepted_quantity), 0.000), 3) AS pending_receipt_quantity,
    CASE
        WHEN COALESCE(SUM(grl.accepted_quantity), 0.000) >= pol.ordered_quantity THEN 'FULLY_RECEIVED'
        WHEN COALESCE(SUM(grl.accepted_quantity), 0.000) > 0 THEN 'PARTIALLY_RECEIVED'
        ELSE 'PENDING'
    END AS fulfillment_status
FROM purchasing.purchase_order po
JOIN public.supplier sup ON sup.supplier_id = po.supplier_id
JOIN purchasing.purchase_order_line pol ON pol.order_id = po.order_id
JOIN public.item itm ON itm.item_id = pol.item_id
LEFT JOIN purchasing.goods_receipt_line grl ON grl.order_line_id = pol.order_line_id
LEFT JOIN purchasing.supplier_invoice_line sil ON sil.order_line_id = pol.order_line_id
GROUP BY
    po.order_id, po.po_no, po.supplier_id, sup.supplier_name, pol.order_line_id,
    pol.line_no, pol.item_id, itm.item_code, itm.item_name, pol.ordered_quantity;


-- ============================================================================
-- 8. INTEGRITY TRIGGERS & BUSINESS LOGIC
-- ============================================================================

-- 8.1 Guard Purchasable Items on Purchase Orders
CREATE OR REPLACE FUNCTION purchasing.guard_po_line()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.item
        WHERE item_id = NEW.item_id AND is_purchasable AND is_active
    ) THEN
        RAISE EXCEPTION 'Item ID % must be active and flagged as purchasable (is_purchasable = true)', NEW.item_id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_po_line
BEFORE INSERT OR UPDATE ON purchasing.purchase_order_line
FOR EACH ROW EXECUTE FUNCTION purchasing.guard_po_line();

-- 8.2 Guard Payment Allocation against Invoice Balance and Invoice Date
CREATE OR REPLACE FUNCTION purchasing.guard_payment_allocation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    target_invoice_total NUMERIC(22,2);
    target_invoice_date  DATE;
    target_payment_date  DATE;
    total_allocated      NUMERIC(22,2);
BEGIN
    SELECT total_amount, invoice_date
    INTO target_invoice_total, target_invoice_date
    FROM purchasing.supplier_invoice
    WHERE invoice_id = NEW.invoice_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Referenced supplier invoice ID % does not exist', NEW.invoice_id
            USING ERRCODE = '23503';
    END IF;

    SELECT payment_date
    INTO target_payment_date
    FROM purchasing.supplier_payment
    WHERE payment_id = NEW.payment_id;

    IF target_payment_date < target_invoice_date THEN
        RAISE EXCEPTION 'Payment date (%) cannot precede invoice date (%)', target_payment_date, target_invoice_date
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(SUM(allocated_amount), 0.00)
    INTO total_allocated
    FROM purchasing.supplier_payment_allocation
    WHERE invoice_id = NEW.invoice_id
      AND allocation_id <> COALESCE(NEW.allocation_id, -1);

    total_allocated := total_allocated + NEW.allocated_amount;

    IF total_allocated > target_invoice_total THEN
        RAISE EXCEPTION 'Total payment allocation (%) exceeds invoice total amount (%) for invoice ID %',
            total_allocated, target_invoice_total, NEW.invoice_id
            USING ERRCODE = '23514';
    END IF;

    -- Update invoice payment status automatically
    IF total_allocated >= target_invoice_total THEN
        UPDATE purchasing.supplier_invoice SET status = 'PAID' WHERE invoice_id = NEW.invoice_id;
    ELSE
        UPDATE purchasing.supplier_invoice SET status = 'PARTIALLY_PAID' WHERE invoice_id = NEW.invoice_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_payment_allocation
BEFORE INSERT OR UPDATE ON purchasing.supplier_payment_allocation
FOR EACH ROW EXECUTE FUNCTION purchasing.guard_payment_allocation();


-- ============================================================================
-- 9. REALISTIC RETAIL SAMPLE DATA (Gerçekçi Perakende Örnek Veri Seti)
-- ============================================================================
-- The scenario models 5 realistic retail procurement cycles for Anadolu Mobilya:
-- 1. Oak Wood procurement from Kuzey Orman (Full receipt, exact 3WM, full payment)
-- 2. MDF Sheet procurement from Anadolu Levha (Partial acceptance, rejection handling, exact bill)
-- 3. Steel Handles from Doğu Metal (Store direct delivery, exact match, partial payment)
-- 4. Assembly Screws & Varnish from Ege Hırdavat (Sarf malzeme, full flow settled)
-- 5. Upholstered Seats from Bursa Döşemelik (Multi-invoice payment settlement)
-- ============================================================================

DO $$
DECLARE
    -- Personnel keys
    emp_gm INTEGER;
    emp_sales INTEGER;
    emp_prod INTEGER;
    emp_buyer INTEGER;
    emp_acct INTEGER;
    emp_qc INTEGER;

    -- Department keys
    dept_urt INTEGER;
    dept_sat INTEGER;
    dept_stn INTEGER;
    dept_muh INTEGER;
    dept_dep INTEGER;

    -- Supplier keys
    sup_kuzey INTEGER;
    sup_anadolu INTEGER;
    sup_ege INTEGER;
    sup_marmara INTEGER;
    sup_bursa INTEGER;
    sup_dogu INTEGER;

    -- Item keys
    item_oak INTEGER;
    item_mdf INTEGER;
    item_handle INTEGER;
    item_screws INTEGER;
    item_varnish INTEGER;
    item_seats INTEGER;

    -- Location keys
    loc_wh_central INTEGER;
    loc_store_ist INTEGER;
    loc_wh_bursa INTEGER;

    -- Transaction IDs
    pr_id1 INTEGER; pr_id2 INTEGER; pr_id3 INTEGER; pr_id4 INTEGER; pr_id5 INTEGER;
    prl_id1 INTEGER; prl_id2 INTEGER; prl_id3 INTEGER; prl_id4 INTEGER; prl_id5 INTEGER; prl_id6 INTEGER;

    po_id1 INTEGER; po_id2 INTEGER; po_id3 INTEGER; po_id4 INTEGER; po_id5 INTEGER;
    pol_id1 INTEGER; pol_id2 INTEGER; pol_id3 INTEGER; pol_id4 INTEGER; pol_id5 INTEGER; pol_id6 INTEGER;

    gr_id1 INTEGER; gr_id2 INTEGER; gr_id3 INTEGER; gr_id4 INTEGER; gr_id5 INTEGER;
    grl_id1 INTEGER; grl_id2 INTEGER; grl_id3 INTEGER; grl_id4 INTEGER; grl_id5 INTEGER; grl_id6 INTEGER;

    inv_id1 INTEGER; inv_id2 INTEGER; inv_id3 INTEGER; inv_id4 INTEGER; inv_id5 INTEGER;
    invl_id1 INTEGER; invl_id2 INTEGER; invl_id3 INTEGER; invl_id4 INTEGER; invl_id5 INTEGER; invl_id6 INTEGER;

    pay_id1 INTEGER; pay_id2 INTEGER; pay_id3 INTEGER; pay_id4 INTEGER; pay_id5 INTEGER;

BEGIN
    -- ------------------------------------------------------------------------
    -- Resolve Foreign Key References from db_init.sql Masters
    -- ------------------------------------------------------------------------
    SELECT employee_id INTO STRICT emp_gm    FROM public.employee WHERE employee_no = 'E-0001';
    SELECT employee_id INTO STRICT emp_sales FROM public.employee WHERE employee_no = 'E-0002';
    SELECT employee_id INTO STRICT emp_prod  FROM public.employee WHERE employee_no = 'E-0003';
    SELECT employee_id INTO STRICT emp_buyer FROM public.employee WHERE employee_no = 'E-0004';
    SELECT employee_id INTO STRICT emp_acct  FROM public.employee WHERE employee_no = 'E-0006';
    SELECT employee_id INTO STRICT emp_qc    FROM public.employee WHERE employee_no = 'E-0007';

    SELECT department_id INTO STRICT dept_urt FROM public.department WHERE department_code = 'URT';
    SELECT department_id INTO STRICT dept_sat FROM public.department WHERE department_code = 'SAT';
    SELECT department_id INTO STRICT dept_stn FROM public.department WHERE department_code = 'STN';
    SELECT department_id INTO STRICT dept_muh FROM public.department WHERE department_code = 'MUH';
    SELECT department_id INTO STRICT dept_dep FROM public.department WHERE department_code = 'DEP';

    SELECT supplier_id INTO STRICT sup_kuzey   FROM public.supplier WHERE supplier_code = 'T-0001';
    SELECT supplier_id INTO STRICT sup_anadolu FROM public.supplier WHERE supplier_code = 'T-0002';
    SELECT supplier_id INTO STRICT sup_ege     FROM public.supplier WHERE supplier_code = 'T-0003';
    SELECT supplier_id INTO STRICT sup_marmara FROM public.supplier WHERE supplier_code = 'T-0004';
    SELECT supplier_id INTO STRICT sup_bursa   FROM public.supplier WHERE supplier_code = 'T-0005';
    SELECT supplier_id INTO STRICT sup_dogu    FROM public.supplier WHERE supplier_code = 'T-0006';

    SELECT item_id INTO STRICT item_oak     FROM public.item WHERE item_code = 'HM-0001';
    SELECT item_id INTO STRICT item_mdf     FROM public.item WHERE item_code = 'HM-0002';
    SELECT item_id INTO STRICT item_handle  FROM public.item WHERE item_code = 'BL-0001';
    SELECT item_id INTO STRICT item_screws  FROM public.item WHERE item_code = 'SM-0001';
    SELECT item_id INTO STRICT item_varnish FROM public.item WHERE item_code = 'SM-0002';
    SELECT item_id INTO STRICT item_seats   FROM public.item WHERE item_code = 'BL-0002';

    SELECT location_id INTO STRICT loc_wh_central FROM inventory.stock_location WHERE location_code = 'WH-CENTRAL';
    SELECT location_id INTO STRICT loc_store_ist  FROM inventory.stock_location WHERE location_code = 'STORE-IST-01';
    SELECT location_id INTO STRICT loc_wh_bursa   FROM inventory.stock_location WHERE location_code = 'WH-BURSA';


    -- ------------------------------------------------------------------------
    -- 9.1 Insert Purchase Requisitions (PR)
    -- ------------------------------------------------------------------------
    -- PR 1: Production requesting solid oak timber
    INSERT INTO purchasing.purchase_requisition
        (requisition_no, department_id, requested_by, requisition_date, required_by_date, priority, status, approved_by, approved_at, justification)
    VALUES
        ('PR-2026-0001', dept_urt, emp_prod, DATE '2026-11-01', DATE '2026-11-15', 'HIGH', 'APPROVED', emp_gm, TIMESTAMPTZ '2026-11-01 14:30:00+03', 'Masif meşe yemek masası siparişleri için acil hammadde ihtiyacı')
    RETURNING requisition_id INTO pr_id1;

    INSERT INTO purchasing.purchase_requisition_line (requisition_id, line_no, item_id, quantity, estimated_unit_cost, notes)
    VALUES (pr_id1, 1, item_oak, 10.000, 38500.00, 'Kurutulmuş 30mm meşe kereste')
    RETURNING requisition_line_id INTO prl_id1;

    -- PR 2: Warehouse requesting MDF panels
    INSERT INTO purchasing.purchase_requisition
        (requisition_no, department_id, requested_by, requisition_date, required_by_date, priority, status, approved_by, approved_at, justification)
    VALUES
        ('PR-2026-0002', dept_dep, emp_qc, DATE '2026-11-03', DATE '2026-11-18', 'MEDIUM', 'APPROVED', emp_gm, TIMESTAMPTZ '2026-11-03 16:00:00+03', 'Dolap gövdesi ve raf üretimi için emniyet stoku tamamlama')
    RETURNING requisition_id INTO pr_id2;

    INSERT INTO purchasing.purchase_requisition_line (requisition_id, line_no, item_id, quantity, estimated_unit_cost, notes)
    VALUES (pr_id2, 1, item_mdf, 50.000, 1250.00, '18mm 210x280cm MDF levha')
    RETURNING requisition_line_id INTO prl_id2;

    -- PR 3: Purchasing requesting stainless steel handles
    INSERT INTO purchasing.purchase_requisition
        (requisition_no, department_id, requested_by, requisition_date, required_by_date, priority, status, approved_by, approved_at, justification)
    VALUES
        ('PR-2026-0003', dept_stn, emp_buyer, DATE '2026-11-05', DATE '2026-11-20', 'MEDIUM', 'APPROVED', emp_gm, TIMESTAMPTZ '2026-11-05 11:15:00+03', 'Karaköy mağazası yedek parça ve montaj stoku')
    RETURNING requisition_id INTO pr_id3;

    INSERT INTO purchasing.purchase_requisition_line (requisition_id, line_no, item_id, quantity, estimated_unit_cost, notes)
    VALUES (pr_id3, 1, item_handle, 500.000, 18.50, '128mm paslanmaz kulp')
    RETURNING requisition_line_id INTO prl_id3;

    -- PR 4: Production requesting screws and varnish
    INSERT INTO purchasing.purchase_requisition
        (requisition_no, department_id, requested_by, requisition_date, required_by_date, priority, status, approved_by, approved_at, justification)
    VALUES
        ('PR-2026-0004', dept_urt, emp_prod, DATE '2026-11-07', DATE '2026-11-22', 'URGENT', 'APPROVED', emp_gm, TIMESTAMPTZ '2026-11-07 09:45:00+03', 'Haftalık montaj ve cila sarf malzeme ihtiyacı')
    RETURNING requisition_id INTO pr_id4;

    INSERT INTO purchasing.purchase_requisition_line (requisition_id, line_no, item_id, quantity, estimated_unit_cost, notes)
    VALUES
        (pr_id4, 1, item_screws, 100.000, 95.00, 'Ahşap vidası 4x40mm (200lük paket)'),
        (pr_id4, 2, item_varnish, 30.000, 210.00, 'Su bazlı mat vernik')
    RETURNING requisition_line_id INTO prl_id4;
    SELECT requisition_line_id INTO prl_id5 FROM purchasing.purchase_requisition_line WHERE requisition_id = pr_id4 AND line_no = 2;

    -- PR 5: Warehouse requesting chair seats
    INSERT INTO purchasing.purchase_requisition
        (requisition_no, department_id, requested_by, requisition_date, required_by_date, priority, status, approved_by, approved_at, justification)
    VALUES
        ('PR-2026-0005', dept_dep, emp_qc, DATE '2026-11-10', DATE '2026-11-25', 'HIGH', 'APPROVED', emp_gm, TIMESTAMPTZ '2026-11-10 15:20:00+03', 'Model S-100 sandalye montaj serisi için oturak bileşeni')
    RETURNING requisition_id INTO pr_id5;

    INSERT INTO purchasing.purchase_requisition_line (requisition_id, line_no, item_id, quantity, estimated_unit_cost, notes)
    VALUES (pr_id5, 1, item_seats, 100.000, 120.00, 'Döşemelik kumaş kaplı sünger oturak')
    RETURNING requisition_line_id INTO prl_id6;


    -- ------------------------------------------------------------------------
    -- 9.2 Insert Purchase Orders (PO)
    -- ------------------------------------------------------------------------
    -- PO 1: Oak wood to Kuzey Orman (T-0001)
    INSERT INTO purchasing.purchase_order
        (po_no, requisition_id, supplier_id, order_date, expected_delivery_date, payment_terms_days, currency_code, created_by, approved_by, status, shipping_address, notes)
    VALUES
        ('PO-2026-0001', pr_id1, sup_kuzey, DATE '2026-11-02', DATE '2026-11-12', 45, 'TRY', emp_buyer, emp_gm, 'RECEIVED', 'Anadolu Mobilya Merkez Depo, Kastamonu Yolu 12. Km', 'Vade: 45 gün, nakliye tedarikçiye ait')
    RETURNING order_id INTO po_id1;

    INSERT INTO purchasing.purchase_order_line (order_id, line_no, requisition_line_id, item_id, ordered_quantity, unit_price, notes)
    VALUES (po_id1, 1, prl_id1, item_oak, 10.000, 38000.00, 'Pazarlık sonrası birim fiyat 38,000 TRY')
    RETURNING order_line_id INTO pol_id1;

    -- PO 2: MDF panels to Anadolu Levha (T-0002)
    INSERT INTO purchasing.purchase_order
        (po_no, requisition_id, supplier_id, order_date, expected_delivery_date, payment_terms_days, currency_code, created_by, approved_by, status, shipping_address, notes)
    VALUES
        ('PO-2026-0002', pr_id2, sup_anadolu, DATE '2026-11-04', DATE '2026-11-15', 30, 'TRY', emp_buyer, emp_gm, 'RECEIVED', 'Anadolu Mobilya Merkez Depo, Kayseri Yolu', 'Vade: 30 gün')
    RETURNING order_id INTO po_id2;

    INSERT INTO purchasing.purchase_order_line (order_id, line_no, requisition_line_id, item_id, ordered_quantity, unit_price, notes)
    VALUES (po_id2, 1, prl_id2, item_mdf, 50.000, 1200.00, 'Toplu alım iskontosu uygulandı')
    RETURNING order_line_id INTO pol_id2;

    -- PO 3: Handles to Doğu Metal (T-0006)
    INSERT INTO purchasing.purchase_order
        (po_no, requisition_id, supplier_id, order_date, expected_delivery_date, payment_terms_days, currency_code, created_by, approved_by, status, shipping_address, notes)
    VALUES
        ('PO-2026-0003', pr_id3, sup_dogu, DATE '2026-11-06', DATE '2026-11-18', 30, 'TRY', emp_buyer, emp_gm, 'RECEIVED', 'Karaköy Mağaza Teslimat Adresi', 'Doğrudan mağaza deposuna sevk')
    RETURNING order_id INTO po_id3;

    INSERT INTO purchasing.purchase_order_line (order_id, line_no, requisition_line_id, item_id, ordered_quantity, unit_price, notes)
    VALUES (po_id3, 1, prl_id3, item_handle, 500.000, 18.00, 'Özel krom kaplama')
    RETURNING order_line_id INTO pol_id3;

    -- PO 4: Screws & Varnish to Ege Hırdavat (T-0003)
    INSERT INTO purchasing.purchase_order
        (po_no, requisition_id, supplier_id, order_date, expected_delivery_date, payment_terms_days, currency_code, created_by, approved_by, status, shipping_address, notes)
    VALUES
        ('PO-2026-0004', pr_id4, sup_ege, DATE '2026-11-08', DATE '2026-11-17', 30, 'TRY', emp_buyer, emp_gm, 'RECEIVED', 'Merkez Depo Atölye Girişi', 'Haftalık sarf ikmali')
    RETURNING order_id INTO po_id4;

    INSERT INTO purchasing.purchase_order_line (order_id, line_no, requisition_line_id, item_id, ordered_quantity, unit_price, notes)
    VALUES
        (po_id4, 1, prl_id4, item_screws, 100.000, 90.00, 'Paket başı 90.00 TRY'),
        (po_id4, 2, prl_id5, item_varnish, 30.000, 200.00, 'Litre başı 200.00 TRY')
    RETURNING order_line_id INTO pol_id4;
    SELECT order_line_id INTO pol_id5 FROM purchasing.purchase_order_line WHERE order_id = po_id4 AND line_no = 2;

    -- PO 5: Chair seats to Bursa Döşemelik (T-0005)
    INSERT INTO purchasing.purchase_order
        (po_no, requisition_id, supplier_id, order_date, expected_delivery_date, payment_terms_days, currency_code, created_by, approved_by, status, shipping_address, notes)
    VALUES
        ('PO-2026-0005', pr_id5, sup_bursa, DATE '2026-11-11', DATE '2026-11-20', 45, 'TRY', emp_buyer, emp_gm, 'PARTIALLY_RECEIVED', 'Bursa Bölge Depo', 'Kumaş kodu: Gri Melanj')
    RETURNING order_id INTO po_id5;

    INSERT INTO purchasing.purchase_order_line (order_id, line_no, requisition_line_id, item_id, ordered_quantity, unit_price, notes)
    VALUES (po_id5, 1, prl_id6, item_seats, 100.000, 115.00, 'Sözleşme fiyatı')
    RETURNING order_line_id INTO pol_id6;


    -- ------------------------------------------------------------------------
    -- 9.3 Insert Goods Receipts & Inspections (GR)
    -- ------------------------------------------------------------------------
    -- GR 1: 10 M3 Oak wood fully received & accepted at Central WH
    INSERT INTO purchasing.goods_receipt
        (receipt_no, order_id, supplier_id, location_id, delivery_note_no, received_on, received_by, inspected_by, status, notes)
    VALUES
        ('GR-2026-0001', po_id1, sup_kuzey, loc_wh_central, 'IRS-KZY-2026-8812', DATE '2026-11-10', emp_qc, emp_qc, 'POSTED', 'Nem ölçümü yapıldı (%10-12 standart içi), eksiksiz kabul')
    RETURNING receipt_id INTO gr_id1;

    INSERT INTO purchasing.goods_receipt_line (receipt_id, line_no, order_line_id, item_id, received_quantity, accepted_quantity, rejected_quantity, rejection_reason, notes)
    VALUES (gr_id1, 1, pol_id1, item_oak, 10.000, 10.000, 0.000, NULL, '10 m3 birinci sınıf meşe kereste depolandı')
    RETURNING receipt_line_id INTO grl_id1;

    -- GR 2: 50 MDF sheets received; 48 accepted, 2 rejected (damaged edge)
    INSERT INTO purchasing.goods_receipt
        (receipt_no, order_id, supplier_id, location_id, delivery_note_no, received_on, received_by, inspected_by, status, notes)
    VALUES
        ('GR-2026-0002', po_id2, sup_anadolu, loc_wh_central, 'IRS-AND-2026-4431', DATE '2026-11-14', emp_qc, emp_qc, 'POSTED', 'Palet köşesi hasarlı geldi, 2 plaka fire/ret')
    RETURNING receipt_id INTO gr_id2;

    INSERT INTO purchasing.goods_receipt_line (receipt_id, line_no, order_line_id, item_id, received_quantity, accepted_quantity, rejected_quantity, rejection_reason, notes)
    VALUES (gr_id2, 1, pol_id2, item_mdf, 50.000, 48.000, 2.000, 'Taşıma sırasında kenar kırığı ve nem deformasyonu', '48 levha rafa alındı, 2 levha iade sahasında')
    RETURNING receipt_line_id INTO grl_id2;

    -- GR 3: 500 handles received & accepted at Istanbul store
    INSERT INTO purchasing.goods_receipt
        (receipt_no, order_id, supplier_id, location_id, delivery_note_no, received_on, received_by, inspected_by, status, notes)
    VALUES
        ('GR-2026-0003', po_id3, sup_dogu, loc_store_ist, 'IRS-DGU-2026-9022', DATE '2026-11-16', emp_sales, emp_qc, 'POSTED', 'Karaköy mağaza mal kabulü yapıldı')
    RETURNING receipt_id INTO gr_id3;

    INSERT INTO purchasing.goods_receipt_line (receipt_id, line_no, order_line_id, item_id, received_quantity, accepted_quantity, rejected_quantity, rejection_reason, notes)
    VALUES (gr_id3, 1, pol_id3, item_handle, 500.000, 500.000, 0.000, NULL, 'Kromaj kontrolü yapıldı, çizik yok')
    RETURNING receipt_line_id INTO grl_id3;

    -- GR 4: Screws & Varnish received at Central WH
    INSERT INTO purchasing.goods_receipt
        (receipt_no, order_id, supplier_id, location_id, delivery_note_no, received_on, received_by, inspected_by, status, notes)
    VALUES
        ('GR-2026-0004', po_id4, sup_ege, loc_wh_central, 'IRS-EGE-2026-1190', DATE '2026-11-15', emp_qc, emp_qc, 'POSTED', 'Sarf depo kabulü tamamlandı')
    RETURNING receipt_id INTO gr_id4;

    INSERT INTO purchasing.goods_receipt_line (receipt_id, line_no, order_line_id, item_id, received_quantity, accepted_quantity, rejected_quantity, rejection_reason, notes)
    VALUES
        (gr_id4, 1, pol_id4, item_screws, 100.000, 100.000, 0.000, NULL, '100 paket tam'),
        (gr_id4, 2, pol_id5, item_varnish, 30.000, 30.000, 0.000, NULL, 'Tenekeler sağlam, sızdırma yok')
    RETURNING receipt_line_id INTO grl_id4;
    SELECT receipt_line_id INTO grl_id5 FROM purchasing.goods_receipt_line WHERE receipt_id = gr_id4 AND line_no = 2;

    -- GR 5: First partial delivery of chair seats (60 units: 58 accepted, 2 rejected)
    INSERT INTO purchasing.goods_receipt
        (receipt_no, order_id, supplier_id, location_id, delivery_note_no, received_on, received_by, inspected_by, status, notes)
    VALUES
        ('GR-2026-0005', po_id5, sup_bursa, loc_wh_bursa, 'IRS-BRS-2026-5501', DATE '2026-11-18', emp_qc, emp_qc, 'POSTED', '1. parti 60 adet teslim alındı, kalan 40 adet sonraki parti')
    RETURNING receipt_id INTO gr_id5;

    INSERT INTO purchasing.goods_receipt_line (receipt_id, line_no, order_line_id, item_id, received_quantity, accepted_quantity, rejected_quantity, rejection_reason, notes)
    VALUES (gr_id5, 1, pol_id5, item_seats, 60.000, 58.000, 2.000, 'Kumaş dikişinde sökük ve leke tespit edildi', '58 adet montaja sevk edildi, 2 adet iade tutanağı tutuldu')
    RETURNING receipt_line_id INTO grl_id6;


    -- ------------------------------------------------------------------------
    -- 9.4 Insert Supplier Invoices (Vendor Bills)
    -- ------------------------------------------------------------------------
    -- Inv 1: Kuzey Orman for 10 M3 Oak wood (380,000 + 76,000 VAT = 456,000 TRY)
    INSERT INTO purchasing.supplier_invoice
        (invoice_no, supplier_id, order_id, invoice_date, due_date, currency_code, subtotal_amount, tax_amount, total_amount, recorded_by, status, notes)
    VALUES
        ('FAT-KZY-2026-0101', sup_kuzey, po_id1, DATE '2026-11-11', DATE '2026-12-26', 'TRY', 380000.00, 76000.00, 456000.00, emp_acct, 'RECEIVED', 'e-Fatura: GIB2026000000101')
    RETURNING invoice_id INTO inv_id1;

    INSERT INTO purchasing.supplier_invoice_line (invoice_id, line_no, order_line_id, receipt_line_id, item_id, billed_quantity, unit_price, tax_rate, notes)
    VALUES (inv_id1, 1, pol_id1, grl_id1, item_oak, 10.000, 38000.00, 20.00, '10 m3 meşe tahta faturası')
    RETURNING invoice_line_id INTO invl_id1;

    -- Inv 2: Anadolu Levha (Billed accepted quantity: 48 MDF @ 1,200 = 57,600 + 11,520 VAT = 69,120 TRY)
    INSERT INTO purchasing.supplier_invoice
        (invoice_no, supplier_id, order_id, invoice_date, due_date, currency_code, subtotal_amount, tax_amount, total_amount, recorded_by, status, notes)
    VALUES
        ('FAT-AND-2026-0201', sup_anadolu, po_id2, DATE '2026-11-15', DATE '2026-12-15', 'TRY', 57600.00, 11520.00, 69120.00, emp_acct, 'RECEIVED', 'Tedarikçi ret verilen 2 adedi düşerek 48 adet faturalandırdı')
    RETURNING invoice_id INTO inv_id2;

    INSERT INTO purchasing.supplier_invoice_line (invoice_id, line_no, order_line_id, receipt_line_id, item_id, billed_quantity, unit_price, tax_rate, notes)
    VALUES (inv_id2, 1, pol_id2, grl_id2, item_mdf, 48.000, 1200.00, 20.00, '48 adet net kabul edilen MDF levha')
    RETURNING invoice_line_id INTO invl_id2;

    -- Inv 3: Doğu Metal for 500 handles (9,000 + 1,800 VAT = 10,800 TRY)
    INSERT INTO purchasing.supplier_invoice
        (invoice_no, supplier_id, order_id, invoice_date, due_date, currency_code, subtotal_amount, tax_amount, total_amount, recorded_by, status, notes)
    VALUES
        ('FAT-DGU-2026-0301', sup_dogu, po_id3, DATE '2026-11-17', DATE '2026-12-17', 'TRY', 9000.00, 1800.00, 10800.00, emp_acct, 'RECEIVED', '500 adet kulp bedeli')
    RETURNING invoice_id INTO inv_id3;

    INSERT INTO purchasing.supplier_invoice_line (invoice_id, line_no, order_line_id, receipt_line_id, item_id, billed_quantity, unit_price, tax_rate, notes)
    VALUES (inv_id3, 1, pol_id3, grl_id3, item_handle, 500.000, 18.00, 20.00, '500 adet çekmece kulbu')
    RETURNING invoice_line_id INTO invl_id3;

    -- Inv 4: Ege Hırdavat for Screws & Varnish (9,000 + 6,000 = 15,000 subtotal + 3,000 VAT = 18,000 TRY)
    INSERT INTO purchasing.supplier_invoice
        (invoice_no, supplier_id, order_id, invoice_date, due_date, currency_code, subtotal_amount, tax_amount, total_amount, recorded_by, status, notes)
    VALUES
        ('FAT-EGE-2026-0401', sup_ege, po_id4, DATE '2026-11-16', DATE '2026-12-16', 'TRY', 15000.00, 3000.00, 18000.00, emp_acct, 'RECEIVED', 'Vida ve vernik ortak fatura')
    RETURNING invoice_id INTO inv_id4;

    INSERT INTO purchasing.supplier_invoice_line (invoice_id, line_no, order_line_id, receipt_line_id, item_id, billed_quantity, unit_price, tax_rate, notes)
    VALUES
        (inv_id4, 1, pol_id4, grl_id4, item_screws, 100.000, 90.00, 20.00, '100 paket vida'),
        (inv_id4, 2, pol_id5, grl_id5, item_varnish, 30.000, 200.00, 20.00, '30 lt mat vernik')
    RETURNING invoice_line_id INTO invl_id4;
    SELECT invoice_line_id INTO invl_id5 FROM purchasing.supplier_invoice_line WHERE invoice_id = inv_id4 AND line_no = 2;

    -- Inv 5: Bursa Döşemelik for partial delivery (58 accepted seats @ 115 = 6,670 + 1,334 VAT = 8,004 TRY)
    INSERT INTO purchasing.supplier_invoice
        (invoice_no, supplier_id, order_id, invoice_date, due_date, currency_code, subtotal_amount, tax_amount, total_amount, recorded_by, status, notes)
    VALUES
        ('FAT-BRS-2026-0501', sup_bursa, po_id5, DATE '2026-11-19', DATE '2027-01-03', 'TRY', 6670.00, 1334.00, 8004.00, emp_acct, 'RECEIVED', '1. parti teslimat faturası')
    RETURNING invoice_id INTO inv_id5;

    INSERT INTO purchasing.supplier_invoice_line (invoice_id, line_no, order_line_id, receipt_line_id, item_id, billed_quantity, unit_price, tax_rate, notes)
    VALUES (inv_id5, 1, pol_id6, grl_id6, item_seats, 58.000, 115.00, 20.00, '58 adet kabul edilen oturak faturası')
    RETURNING invoice_line_id INTO invl_id6;


    -- ------------------------------------------------------------------------
    -- 9.5 Perform Three-Way Matching (3 Yönlü Doğrulama Kayıtları)
    -- ------------------------------------------------------------------------
    -- Match 1: PO 1 <-> GR 1 <-> Inv 1 (Exact Match, 10 M3 @ 38,000)
    INSERT INTO purchasing.three_way_match
        (match_no, invoice_line_id, receipt_line_id, order_line_id, matched_on, matched_by, ordered_quantity, received_quantity, billed_quantity, po_unit_price, invoice_unit_price, match_status, is_approved_for_payment, variance_notes)
    VALUES
        ('3WM-2026-0001', invl_id1, grl_id1, pol_id1, DATE '2026-11-12', emp_buyer, 10.000, 10.000, 10.000, 38000.00, 38000.00, 'EXACT_MATCH', TRUE, 'Miktar ve fiyat tam eşleşti. Ödeme onayı verildi.');

    -- Match 2: PO 2 <-> GR 2 <-> Inv 2 (48 accepted vs 48 billed @ 1,200)
    INSERT INTO purchasing.three_way_match
        (match_no, invoice_line_id, receipt_line_id, order_line_id, matched_on, matched_by, ordered_quantity, received_quantity, billed_quantity, po_unit_price, invoice_unit_price, match_status, is_approved_for_payment, variance_notes)
    VALUES
        ('3WM-2026-0002', invl_id2, grl_id2, pol_id2, DATE '2026-11-16', emp_buyer, 50.000, 48.000, 48.000, 1200.00, 1200.00, 'EXACT_MATCH', TRUE, '2 hasarlı ürün fatura edilmedi. Kabul edilen 48 adet onaylandı.');

    -- Match 3: PO 3 <-> GR 3 <-> Inv 3 (Exact Match, 500 handles @ 18)
    INSERT INTO purchasing.three_way_match
        (match_no, invoice_line_id, receipt_line_id, order_line_id, matched_on, matched_by, ordered_quantity, received_quantity, billed_quantity, po_unit_price, invoice_unit_price, match_status, is_approved_for_payment, variance_notes)
    VALUES
        ('3WM-2026-0003', invl_id3, grl_id3, pol_id3, DATE '2026-11-18', emp_buyer, 500.000, 500.000, 500.000, 18.00, 18.00, 'EXACT_MATCH', TRUE, 'Mağaza teslimatı tam ve eksiksiz.');

    -- Match 4: PO 4 <-> GR 4 <-> Inv 4 (Screws & Varnish exact matches)
    INSERT INTO purchasing.three_way_match
        (match_no, invoice_line_id, receipt_line_id, order_line_id, matched_on, matched_by, ordered_quantity, received_quantity, billed_quantity, po_unit_price, invoice_unit_price, match_status, is_approved_for_payment, variance_notes)
    VALUES
        ('3WM-2026-0004', invl_id4, grl_id4, pol_id4, DATE '2026-11-17', emp_buyer, 100.000, 100.000, 100.000, 90.00, 90.00, 'EXACT_MATCH', TRUE, 'Ahşap vidası tam mutabakat.'),
        ('3WM-2026-0005', invl_id5, grl_id5, pol_id5, DATE '2026-11-17', emp_buyer, 30.000, 30.000, 30.000, 200.00, 200.00, 'EXACT_MATCH', TRUE, 'Vernik tam mutabakat.');

    -- Match 5: PO 5 <-> GR 5 <-> Inv 5 (58 accepted vs 58 billed @ 115)
    INSERT INTO purchasing.three_way_match
        (match_no, invoice_line_id, receipt_line_id, order_line_id, matched_on, matched_by, ordered_quantity, received_quantity, billed_quantity, po_unit_price, invoice_unit_price, match_status, is_approved_for_payment, variance_notes)
    VALUES
        ('3WM-2026-0006', invl_id6, grl_id6, pol_id6, DATE '2026-11-20', emp_buyer, 100.000, 58.000, 58.000, 115.00, 115.00, 'EXACT_MATCH', TRUE, '1. parti 58 adet oturak faturası onaylandı. Kalan 40 adet bekleniyor.');

    -- Mark invoices as approved for payment
    UPDATE purchasing.supplier_invoice SET status = 'APPROVED_FOR_PAYMENT'
    WHERE invoice_id IN (inv_id1, inv_id2, inv_id3, inv_id4, inv_id5);


    -- ------------------------------------------------------------------------
    -- 9.6 Insert Supplier Payments & Allocations
    -- ------------------------------------------------------------------------
    -- Payment 1: Full settlement of Kuzey Orman Invoice 1 (456,000 TRY via EFT)
    INSERT INTO purchasing.supplier_payment
        (payment_no, supplier_id, payment_date, payment_method, bank_reference, currency_code, total_paid, recorded_by, status, notes)
    VALUES
        ('PAY-2026-0001', sup_kuzey, DATE '2026-12-20', 'EFT', 'TR-ISBK-20261220-9941', 'TRY', 456000.00, emp_acct, 'POSTED', 'İş Bankası kurumsal EFT ile tam ödeme')
    RETURNING payment_id INTO pay_id1;

    INSERT INTO purchasing.supplier_payment_allocation (payment_id, invoice_id, allocated_amount, notes)
    VALUES (pay_id1, inv_id1, 456000.00, 'FAT-KZY-2026-0101 kapandı');

    -- Payment 2: Full settlement of Anadolu Levha Invoice 2 (69,120 TRY via Bank Transfer)
    INSERT INTO purchasing.supplier_payment
        (payment_no, supplier_id, payment_date, payment_method, bank_reference, currency_code, total_paid, recorded_by, status, notes)
    VALUES
        ('PAY-2026-0002', sup_anadolu, DATE '2026-12-10', 'BANK_TRANSFER', 'TR-GARN-20261210-4412', 'TRY', 69120.00, emp_acct, 'POSTED', 'Garanti BBVA havale')
    RETURNING payment_id INTO pay_id2;

    INSERT INTO purchasing.supplier_payment_allocation (payment_id, invoice_id, allocated_amount, notes)
    VALUES (pay_id2, inv_id2, 69120.00, 'FAT-AND-2026-0201 kapandı');

    -- Payment 3: PARTIAL settlement of Doğu Metal Invoice 3 (5,000 of 10,800 TRY via Credit Card)
    -- Leaving 5,800 TRY open balance!
    INSERT INTO purchasing.supplier_payment
        (payment_no, supplier_id, payment_date, payment_method, bank_reference, currency_code, total_paid, recorded_by, status, notes)
    VALUES
        ('PAY-2026-0003', sup_dogu, DATE '2026-11-25', 'CREDIT_CARD', 'POS-YKBNK-20261125-881', 'TRY', 5000.00, emp_acct, 'POSTED', 'Kurumsal şirket kredi kartı ile 1. kısmi taksit')
    RETURNING payment_id INTO pay_id3;

    INSERT INTO purchasing.supplier_payment_allocation (payment_id, invoice_id, allocated_amount, notes)
    VALUES (pay_id3, inv_id3, 5000.00, 'FAT-DGU-2026-0301 kısmi ödeme (Kalan: 5,800 TRY)');

    -- Payment 4: Full settlement of Ege Hırdavat Invoice 4 (18,000 TRY via Bank Transfer)
    INSERT INTO purchasing.supplier_payment
        (payment_no, supplier_id, payment_date, payment_method, bank_reference, currency_code, total_paid, recorded_by, status, notes)
    VALUES
        ('PAY-2026-0004', sup_ege, DATE '2026-12-05', 'BANK_TRANSFER', 'TR-AKBK-20261205-1209', 'TRY', 18000.00, emp_acct, 'POSTED', 'Akbank kurumsal transfer')
    RETURNING payment_id INTO pay_id4;

    INSERT INTO purchasing.supplier_payment_allocation (payment_id, invoice_id, allocated_amount, notes)
    VALUES (pay_id4, inv_id4, 18000.00, 'FAT-EGE-2026-0401 kapandı');

    -- Payment 5: Full settlement of Bursa Döşemelik Invoice 5 (8,004 TRY)
    INSERT INTO purchasing.supplier_payment
        (payment_no, supplier_id, payment_date, payment_method, bank_reference, currency_code, total_paid, recorded_by, status, notes)
    VALUES
        ('PAY-2026-0005', sup_bursa, DATE '2026-12-28', 'BANK_TRANSFER', 'TR-ZRT-20261228-7711', 'TRY', 8004.00, emp_acct, 'POSTED', 'Ziraat Bankası transferi')
    RETURNING payment_id INTO pay_id5;

    INSERT INTO purchasing.supplier_payment_allocation (payment_id, invoice_id, allocated_amount, notes)
    VALUES (pay_id5, inv_id5, 8004.00, 'FAT-BRS-2026-0501 tam ödeme');

END;
$$;

COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES (Doğrulama ve Raporlama Çıktıları)
-- Run these queries in pgAdmin to verify the successful execution of P2P cycle
-- ============================================================================

-- 1. Review 3-Way Match Audit Results
SELECT
    po_no,
    supplier_name,
    item_code,
    ordered_quantity,
    po_unit_price,
    delivery_note_no,
    accepted_quantity,
    rejected_quantity,
    invoice_no,
    billed_quantity,
    billed_unit_price,
    quantity_variance,
    price_variance,
    computed_match_status
FROM purchasing.v_three_way_match_audit
ORDER BY po_no;

-- 2. Review Supplier Invoices & Outstanding Balances
SELECT
    invoice_no,
    supplier_name,
    po_no,
    invoice_date,
    due_date,
    total_amount,
    paid_amount,
    balance_due,
    payment_status
FROM purchasing.supplier_invoice_balance
ORDER BY invoice_date;

-- 3. Review Purchase Order Fulfillment Status
SELECT
    po_no,
    supplier_name,
    item_code,
    item_name,
    ordered_quantity,
    received_quantity,
    rejected_quantity,
    billed_quantity,
    pending_receipt_quantity,
    fulfillment_status
FROM purchasing.v_po_fulfillment_status
ORDER BY po_no, line_no;
