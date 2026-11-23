SET client_encoding = 'UTF8';

CREATE SCHEMA core;
CREATE SCHEMA engineering;
CREATE SCHEMA planning;
CREATE SCHEMA production;

-- 1. CORE SCHEMA

CREATE TABLE core.unit_of_measure (
    uom_code VARCHAR(10) PRIMARY KEY,
    uom_name VARCHAR(50) NOT NULL
);

CREATE TABLE core.item_category (
    category_code VARCHAR(20) PRIMARY KEY,
    category_name VARCHAR(60) NOT NULL
);

-- department <-> employee are mutually dependent: department.manager_id
-- is added with ALTER TABLE after employee exists.
CREATE TABLE core.department (
    department_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_code VARCHAR(10)  NOT NULL UNIQUE,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT,
    location        VARCHAR(100),
    manager_id      INTEGER,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE core.employee (
    employee_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_no    VARCHAR(10)  NOT NULL UNIQUE,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    job_title      VARCHAR(100) NOT NULL,
    department_id  INTEGER NOT NULL REFERENCES core.department (department_id),
    supervisor_id  INTEGER REFERENCES core.employee (employee_id) ON DELETE SET NULL,
    email          VARCHAR(120) UNIQUE,
    phone          VARCHAR(20),
    hire_date      DATE NOT NULL,
    monthly_salary NUMERIC(12,2) CHECK (monthly_salary >= 0),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT employee_not_own_supervisor CHECK (supervisor_id IS NULL OR supervisor_id <> employee_id)
);

ALTER TABLE core.department
    ADD CONSTRAINT fk_department_manager
    FOREIGN KEY (manager_id) REFERENCES core.employee (employee_id) ON DELETE SET NULL;

CREATE TABLE core.customer (
    customer_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code  VARCHAR(10)  NOT NULL UNIQUE,
    customer_name  VARCHAR(150) NOT NULL,
    customer_type  VARCHAR(12)  NOT NULL CHECK (customer_type IN ('BIREYSEL', 'KURUMSAL')),
    tax_office     VARCHAR(60),
    tax_number     VARCHAR(11) UNIQUE,
    contact_person VARCHAR(100),
    email          VARCHAR(120),
    phone          VARCHAR(20),
    address        VARCHAR(250),
    city           VARCHAR(50),
    created_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE core.supplier (
    supplier_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_code      VARCHAR(10)  NOT NULL UNIQUE,
    supplier_name      VARCHAR(150) NOT NULL,
    tax_office         VARCHAR(60),
    tax_number         VARCHAR(11) UNIQUE,
    contact_person     VARCHAR(100),
    email              VARCHAR(120),
    phone              VARCHAR(20),
    address            VARCHAR(250),
    city               VARCHAR(50),
    payment_terms_days INTEGER CHECK (payment_terms_days >= 0),
    is_active          BOOLEAN NOT NULL DEFAULT TRUE
);

-- ITEM: an identifiable type of physical good.
CREATE TABLE core.item (
    item_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_code         VARCHAR(20)  NOT NULL UNIQUE,
    item_name         VARCHAR(150) NOT NULL,
    description       TEXT,
    category_code     VARCHAR(20) NOT NULL REFERENCES core.item_category (category_code),
    uom_code          VARCHAR(10) NOT NULL REFERENCES core.unit_of_measure (uom_code),
    is_purchasable    BOOLEAN NOT NULL DEFAULT FALSE,
    is_manufacturable BOOLEAN NOT NULL DEFAULT FALSE,
    is_consumable     BOOLEAN NOT NULL DEFAULT FALSE,
    is_sellable       BOOLEAN NOT NULL DEFAULT FALSE,
    is_serialized     BOOLEAN NOT NULL DEFAULT FALSE,   -- individual units tracked in production.item_unit
    standard_cost     NUMERIC(12,2) CHECK (standard_cost >= 0),
    list_price        NUMERIC(12,2) CHECK (list_price >= 0),
    reorder_level     NUMERIC(12,3) CHECK (reorder_level >= 0),
    lead_time_days    INTEGER CHECK (lead_time_days >= 0),
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT item_has_role CHECK (is_purchasable OR is_manufacturable OR is_consumable OR is_sellable),
    CONSTRAINT sellable_has_price CHECK (NOT is_sellable OR list_price IS NOT NULL)
);

-- Which suppliers can supply which purchasable items (many to many)
CREATE TABLE core.item_supplier (
    item_id            INTEGER NOT NULL REFERENCES core.item (item_id),
    supplier_id        INTEGER NOT NULL REFERENCES core.supplier (supplier_id),
    supplier_item_code VARCHAR(40),
    unit_price         NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    lead_time_days     INTEGER CHECK (lead_time_days >= 0),
    min_order_quantity NUMERIC(12,3) NOT NULL DEFAULT 1 CHECK (min_order_quantity > 0),
    is_preferred       BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (item_id, supplier_id)
);
-- business rule: at most one preferred supplier per item
CREATE UNIQUE INDEX uq_item_one_preferred_supplier
    ON core.item_supplier (item_id) WHERE is_preferred;

-- 2. ENGINEERING SCHEMA

-- Bill of materials header: one revision of the recipe for a manufacturable item
CREATE TABLE engineering.bom (
    bom_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        INTEGER NOT NULL REFERENCES core.item (item_id),
    revision       VARCHAR(10) NOT NULL,
    status         VARCHAR(10) NOT NULL DEFAULT 'TASLAK' CHECK (status IN ('TASLAK', 'ONAYLI', 'GECERSIZ')),
    base_quantity  NUMERIC(12,3) NOT NULL DEFAULT 1 CHECK (base_quantity > 0),
    effective_from DATE NOT NULL,
    effective_to   DATE,
    approved_by    INTEGER REFERENCES core.employee (employee_id),
    UNIQUE (item_id, revision),
    UNIQUE (bom_id, item_id),     -- target of composite FK from production_order
    CONSTRAINT bom_dates_ok CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT bom_approved_has_approver CHECK (status <> 'ONAYLI' OR approved_by IS NOT NULL)
);

CREATE TABLE engineering.bom_line (
    bom_line_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_id            INTEGER NOT NULL REFERENCES engineering.bom (bom_id) ON DELETE CASCADE,
    line_no           INTEGER NOT NULL CHECK (line_no > 0),
    component_item_id INTEGER NOT NULL REFERENCES core.item (item_id),
    quantity_per      NUMERIC(14,4) NOT NULL CHECK (quantity_per > 0),   -- per bom.base_quantity
    scrap_percent     NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (scrap_percent >= 0 AND scrap_percent < 100),
    UNIQUE (bom_id, line_no),
    UNIQUE (bom_id, component_item_id)
);

CREATE TABLE engineering.work_center (
    work_center_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    work_center_code       VARCHAR(15)  NOT NULL UNIQUE,
    work_center_name       VARCHAR(100) NOT NULL,
    department_id          INTEGER NOT NULL REFERENCES core.department (department_id),
    capacity_hours_per_day NUMERIC(5,2) NOT NULL CHECK (capacity_hours_per_day > 0),
    hourly_rate            NUMERIC(10,2) CHECK (hourly_rate >= 0),
    is_active              BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE engineering.routing (
    routing_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id    INTEGER NOT NULL REFERENCES core.item (item_id),
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
    setup_minutes         NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (setup_minutes >= 0),
    run_minutes_per_unit  NUMERIC(8,2) NOT NULL CHECK (run_minutes_per_unit >= 0),
    UNIQUE (routing_id, operation_no)
);

-- 3. PLANNING SCHEMA

CREATE TABLE planning.sales_order (
    sales_order_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no                VARCHAR(20) NOT NULL UNIQUE,
    customer_id             INTEGER NOT NULL REFERENCES core.customer (customer_id),
    order_date              DATE NOT NULL,
    requested_delivery_date DATE NOT NULL,
    status                  VARCHAR(12) NOT NULL DEFAULT 'TASLAK'
                            CHECK (status IN ('TASLAK', 'ONAYLANDI', 'URETIMDE', 'TAMAMLANDI', 'IPTAL')),
    created_by              INTEGER NOT NULL REFERENCES core.employee (employee_id),
    CONSTRAINT so_dates_ok CHECK (requested_delivery_date >= order_date)
);

CREATE TABLE planning.sales_order_line (
    sales_order_line_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sales_order_id      INTEGER NOT NULL REFERENCES planning.sales_order (sales_order_id) ON DELETE CASCADE,
    line_no             INTEGER NOT NULL CHECK (line_no > 0),
    item_id             INTEGER NOT NULL REFERENCES core.item (item_id),
    quantity            NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    unit_price          NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (sales_order_id, line_no)
);

CREATE TABLE planning.production_plan (
    production_plan_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_no            VARCHAR(20) NOT NULL UNIQUE,
    plan_name          VARCHAR(150) NOT NULL,
    period_start       DATE NOT NULL,
    period_end         DATE NOT NULL,
    status             VARCHAR(12) NOT NULL DEFAULT 'TASLAK' CHECK (status IN ('TASLAK', 'ONAYLANDI', 'KAPANDI')),
    created_by         INTEGER NOT NULL REFERENCES core.employee (employee_id),
    approved_by        INTEGER REFERENCES core.employee (employee_id),
    created_at         TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT plan_period_ok CHECK (period_end >= period_start),
    CONSTRAINT plan_approved_has_approver CHECK (status = 'TASLAK' OR approved_by IS NOT NULL)
);

-- sales_order_line_id NULL = dependent demand (e.g. table legs needed for tables)
CREATE TABLE planning.production_plan_line (
    production_plan_line_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_plan_id      INTEGER NOT NULL REFERENCES planning.production_plan (production_plan_id) ON DELETE CASCADE,
    line_no                 INTEGER NOT NULL CHECK (line_no > 0),
    item_id                 INTEGER NOT NULL REFERENCES core.item (item_id),
    sales_order_line_id     INTEGER REFERENCES planning.sales_order_line (sales_order_line_id),
    planned_quantity        NUMERIC(12,3) NOT NULL CHECK (planned_quantity > 0),
    planned_start_date      DATE NOT NULL,
    planned_finish_date     DATE NOT NULL,
    UNIQUE (production_plan_id, line_no),
    UNIQUE (production_plan_line_id, item_id),    -- target of composite FK from production_order
    CONSTRAINT ppl_dates_ok CHECK (planned_finish_date >= planned_start_date)
);

-- MRP result: component demand generated from the BOM of each plan line
CREATE TABLE planning.material_requirement (
    material_requirement_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_plan_line_id INTEGER NOT NULL REFERENCES planning.production_plan_line (production_plan_line_id) ON DELETE CASCADE,
    component_item_id       INTEGER NOT NULL REFERENCES core.item (item_id),
    gross_requirement       NUMERIC(14,4) NOT NULL CHECK (gross_requirement >= 0),
    on_hand_quantity        NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (on_hand_quantity >= 0),  -- snapshot at planning time
    net_requirement         NUMERIC(14,4) GENERATED ALWAYS AS (GREATEST(gross_requirement - on_hand_quantity, 0)) STORED,
    needed_by_date          DATE NOT NULL,
    UNIQUE (production_plan_line_id, component_item_id)
);

-- 4. PRODUCTION SCHEMA

CREATE TABLE production.production_order (
    production_order_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_no                VARCHAR(20) NOT NULL UNIQUE,
    production_plan_line_id INTEGER NOT NULL,
    item_id                 INTEGER NOT NULL REFERENCES core.item (item_id),
    bom_id                  INTEGER NOT NULL,
    routing_id              INTEGER NOT NULL,
    planned_quantity        NUMERIC(12,3) NOT NULL CHECK (planned_quantity > 0),
    status                  VARCHAR(12) NOT NULL DEFAULT 'PLANLANDI'
                            CHECK (status IN ('PLANLANDI', 'SERBEST', 'DEVAM_EDIYOR', 'TAMAMLANDI', 'IPTAL')),
    planned_start_date      DATE NOT NULL,
    planned_finish_date     DATE NOT NULL,
    actual_start_date       DATE,
    actual_finish_date      DATE,
    responsible_employee_id INTEGER NOT NULL REFERENCES core.employee (employee_id),
    UNIQUE (production_order_id, item_id),        -- target of composite FK from item_unit
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
    CONSTRAINT po_completed_has_finish CHECK (status <> 'TAMAMLANDI' OR actual_finish_date IS NOT NULL)
);

-- Components required by an order (snapshot of the BOM explosion at release)
CREATE TABLE production.production_order_component (
    production_order_component_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id           INTEGER NOT NULL REFERENCES production.production_order (production_order_id) ON DELETE CASCADE,
    component_item_id             INTEGER NOT NULL REFERENCES core.item (item_id),
    required_quantity             NUMERIC(14,4) NOT NULL CHECK (required_quantity > 0),
    UNIQUE (production_order_id, component_item_id)
);

CREATE TABLE production.production_order_operation (
    production_order_operation_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id           INTEGER NOT NULL REFERENCES production.production_order (production_order_id) ON DELETE CASCADE,
    routing_operation_id          INTEGER NOT NULL REFERENCES engineering.routing_operation (routing_operation_id),
    planned_setup_minutes         NUMERIC(10,2) NOT NULL CHECK (planned_setup_minutes >= 0),
    planned_run_minutes           NUMERIC(10,2) NOT NULL CHECK (planned_run_minutes >= 0),
    status                        VARCHAR(12) NOT NULL DEFAULT 'BEKLIYOR'
                                  CHECK (status IN ('BEKLIYOR', 'DEVAM_EDIYOR', 'TAMAMLANDI')),
    operator_id                   INTEGER REFERENCES core.employee (employee_id),
    UNIQUE (production_order_id, routing_operation_id)
);

-- Material issued from stock to an order; must be a component of THAT order
CREATE TABLE production.material_issue (
    material_issue_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id INTEGER NOT NULL,
    component_item_id   INTEGER NOT NULL,
    quantity            NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    issued_by           INTEGER NOT NULL REFERENCES core.employee (employee_id),
    issued_at           TIMESTAMP NOT NULL,
    CONSTRAINT fk_issue_order_component FOREIGN KEY (production_order_id, component_item_id)
        REFERENCES production.production_order_component (production_order_id, component_item_id)
);

-- Finished quantity received into stock from an order
CREATE TABLE production.production_receipt (
    production_receipt_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    production_order_id   INTEGER NOT NULL REFERENCES production.production_order (production_order_id),
    quantity              NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    received_by           INTEGER NOT NULL REFERENCES core.employee (employee_id),
    inspected_by          INTEGER REFERENCES core.employee (employee_id),
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

-- 5. BUSINESS-RULE TRIGGERS

-- Generic: the item referenced by NEW.<TG_ARGV[0]> must have role flag TG_ARGV[1]
CREATE FUNCTION core.assert_item_role() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_item_id INTEGER;
    v_ok      BOOLEAN;
BEGIN
    v_item_id := (to_jsonb(NEW) ->> TG_ARGV[0])::INTEGER;
    EXECUTE format('SELECT %I FROM core.item WHERE item_id = $1', TG_ARGV[1])
        INTO v_ok USING v_item_id;
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'Item % does not have the required role "%" (table %.%)',
            v_item_id, TG_ARGV[1], TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

-- A BOM may not list its own parent item as a component
CREATE FUNCTION engineering.assert_component_not_parent() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_parent INTEGER;
BEGIN
    SELECT item_id INTO v_parent FROM engineering.bom WHERE bom_id = NEW.bom_id;
    IF v_parent = NEW.component_item_id THEN
        RAISE EXCEPTION 'BOM % lists its own parent item % as a component', NEW.bom_id, v_parent
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_item_supplier_purchasable
    BEFORE INSERT OR UPDATE OF item_id ON core.item_supplier
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_purchasable');

CREATE TRIGGER trg_bom_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON engineering.bom
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_manufacturable');

CREATE TRIGGER trg_bom_line_consumable
    BEFORE INSERT OR UPDATE OF component_item_id ON engineering.bom_line
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('component_item_id', 'is_consumable');

CREATE TRIGGER trg_bom_line_not_parent
    BEFORE INSERT OR UPDATE OF bom_id, component_item_id ON engineering.bom_line
    FOR EACH ROW EXECUTE FUNCTION engineering.assert_component_not_parent();

CREATE TRIGGER trg_routing_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON engineering.routing
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_manufacturable');

CREATE TRIGGER trg_so_line_sellable
    BEFORE INSERT OR UPDATE OF item_id ON planning.sales_order_line
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_sellable');

CREATE TRIGGER trg_plan_line_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON planning.production_plan_line
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_manufacturable');

CREATE TRIGGER trg_po_manufacturable
    BEFORE INSERT OR UPDATE OF item_id ON production.production_order
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_manufacturable');

CREATE TRIGGER trg_item_unit_serialized
    BEFORE INSERT OR UPDATE OF item_id ON production.item_unit
    FOR EACH ROW EXECUTE FUNCTION core.assert_item_role('item_id', 'is_serialized');

-- 6. INDEXES ON FOREIGN-KEY COLUMNS

CREATE INDEX ix_employee_department      ON core.employee (department_id);
CREATE INDEX ix_employee_supervisor      ON core.employee (supervisor_id);
CREATE INDEX ix_item_category            ON core.item (category_code);
CREATE INDEX ix_item_uom                 ON core.item (uom_code);
CREATE INDEX ix_item_supplier_supplier   ON core.item_supplier (supplier_id);
CREATE INDEX ix_bom_line_component       ON engineering.bom_line (component_item_id);
CREATE INDEX ix_work_center_department   ON engineering.work_center (department_id);
CREATE INDEX ix_routing_op_work_center   ON engineering.routing_operation (work_center_id);
CREATE INDEX ix_so_customer              ON planning.sales_order (customer_id);
CREATE INDEX ix_so_line_item             ON planning.sales_order_line (item_id);
CREATE INDEX ix_plan_line_item           ON planning.production_plan_line (item_id);
CREATE INDEX ix_plan_line_so_line        ON planning.production_plan_line (sales_order_line_id);
CREATE INDEX ix_mat_req_component        ON planning.material_requirement (component_item_id);
CREATE INDEX ix_po_plan_line             ON production.production_order (production_plan_line_id);
CREATE INDEX ix_po_bom                   ON production.production_order (bom_id);
CREATE INDEX ix_po_routing               ON production.production_order (routing_id);
CREATE INDEX ix_po_responsible           ON production.production_order (responsible_employee_id);
CREATE INDEX ix_po_component_item        ON production.production_order_component (component_item_id);
CREATE INDEX ix_po_operation_routing_op  ON production.production_order_operation (routing_operation_id);
CREATE INDEX ix_material_issue_component ON production.material_issue (production_order_id, component_item_id);
CREATE INDEX ix_receipt_order            ON production.production_receipt (production_order_id);
CREATE INDEX ix_item_unit_order          ON production.item_unit (production_order_id, item_id);

-- 7. SAMPLE DATA

-- 7.1 Lookups -----------------------------------------------------------
INSERT INTO core.unit_of_measure (uom_code, uom_name) VALUES
('ADET', 'Adet'), ('KG', 'Kilogram'), ('LT', 'Litre'), ('M', 'Metre'),
('M2', 'Metrekare'), ('M3', 'Metreküp'), ('PAKET', 'Paket'), ('TAKIM', 'Takım');

INSERT INTO core.item_category (category_code, category_name) VALUES
('HAMMADDE', 'Hammadde'), ('YARI_MAMUL', 'Yarı Mamul'), ('BILESEN', 'Bileşen'),
('SARF_MALZEME', 'Sarf Malzeme'), ('MAMUL', 'Mamul');

-- 7.2 Departments, employees --------------------------------------------
INSERT INTO core.department (department_code, department_name, description, location) VALUES
('YON', 'Yönetim',           'Genel yönetim ve strateji.',                                               'İdari Bina - 3. Kat'),
('URT', 'Üretim',            'Kesim, montaj, zımpara ve boya işlemlerinin yapıldığı ve planlandığı birim.', 'Atölye Binası - Zemin Kat'),
('SAT', 'Satış',             'Müşteri siparişlerinin alınması ve teklif hazırlanması.',                  'İdari Bina - 1. Kat'),
('STN', 'Satın Alma',        'Hammadde ve bileşenlerin tedarikçilerden temin edilmesi.',                 'İdari Bina - 1. Kat'),
('MUH', 'Muhasebe',          'Fatura, tahsilat, ödeme ve maliyet muhasebesi.',                           'İdari Bina - 2. Kat'),
('KKT', 'Kalite Kontrol',    'Gelen malzeme ve mamul ürünlerin kalite denetimi.',                        'Atölye Binası - Zemin Kat'),
('DEP', 'Depo ve Sevkiyat',  'Hammadde, yarı mamul ve mamul stoklarının yönetimi ve sevkiyat.',          'Depo Binası');

INSERT INTO core.employee (employee_no, first_name, last_name, job_title, department_id, email, phone, hire_date, monthly_salary)
SELECT v.employee_no, v.first_name, v.last_name, v.job_title, d.department_id, v.email, v.phone, v.hire_date::date, v.salary
FROM (VALUES
 ('E-0001', 'Mehmet',  'Yılmaz', 'Genel Müdür',                 'YON', 'mehmet.yilmaz@anadolumobilya.com.tr',  '0532 111 22 33', '2012-03-01', 95000.00),
 ('E-0002', 'Ayşe',    'Demir',  'Satış Müdürü',                'SAT', 'ayse.demir@anadolumobilya.com.tr',     '0533 222 33 44', '2016-09-15', 62000.00),
 ('E-0003', 'Mustafa', 'Çelik',  'Üretim Şefi',                 'URT', 'mustafa.celik@anadolumobilya.com.tr',  '0535 333 44 55', '2014-05-20', 58000.00),
 ('E-0004', 'Fatma',   'Şahin',  'Satın Alma Uzmanı',           'STN', 'fatma.sahin@anadolumobilya.com.tr',    '0536 444 55 66', '2019-02-11', 45000.00),
 ('E-0005', 'Hasan',   'Öztürk', 'Marangoz Ustası',             'URT', 'hasan.ozturk@anadolumobilya.com.tr',   '0537 555 66 77', '2015-11-02', 40000.00),
 ('E-0006', 'Zeynep',  'Kaya',   'Muhasebe Uzmanı',             'MUH', 'zeynep.kaya@anadolumobilya.com.tr',    '0538 666 77 88', '2020-06-08', 43000.00),
 ('E-0007', 'İbrahim', 'Aydın',  'Kalite Kontrol Uzmanı',       'KKT', 'ibrahim.aydin@anadolumobilya.com.tr',  '0539 777 88 99', '2021-01-18', 41000.00),
 ('E-0008', 'Burcu',   'Kılıç',  'Üretim Planlama Uzmanı',      'URT', 'burcu.kilic@anadolumobilya.com.tr',    '0530 888 99 00', '2022-04-04', 47000.00),
 ('E-0009', 'Osman',   'Taş',    'Depo Sorumlusu',              'DEP', 'osman.tas@anadolumobilya.com.tr',      '0531 999 00 11', '2018-08-13', 39000.00)
) AS v(employee_no, first_name, last_name, job_title, dept_code, email, phone, hire_date, salary)
JOIN core.department d ON d.department_code = v.dept_code;

UPDATE core.employee e SET supervisor_id = s.employee_id
FROM (VALUES
 ('E-0002', 'E-0001'), ('E-0003', 'E-0001'), ('E-0004', 'E-0001'), ('E-0006', 'E-0001'),
 ('E-0007', 'E-0001'), ('E-0005', 'E-0003'), ('E-0008', 'E-0003'), ('E-0009', 'E-0003')
) AS m(emp_no, sup_no)
JOIN core.employee s ON s.employee_no = m.sup_no
WHERE e.employee_no = m.emp_no;

UPDATE core.department d SET manager_id = e.employee_id
FROM (VALUES
 ('YON', 'E-0001'), ('SAT', 'E-0002'), ('URT', 'E-0003'), ('STN', 'E-0004'),
 ('MUH', 'E-0006'), ('KKT', 'E-0007'), ('DEP', 'E-0009')
) AS m(dept_code, emp_no)
JOIN core.employee e ON e.employee_no = m.emp_no
WHERE d.department_code = m.dept_code;

-- 7.3 Customers, suppliers ----------------------------------------------
INSERT INTO core.customer (customer_code, customer_name, customer_type, tax_office, tax_number, contact_person, email, phone, address, city, created_date) VALUES
('M-0001', 'Güneş Otel İşletmeleri A.Ş.',        'KURUMSAL', 'Muratpaşa', '1234567890',  'Serkan Arslan', 'satinalma@gunesotel.com.tr',  '0242 311 40 50', 'Lara Caddesi No: 45',                      'Antalya',  '2023-02-10'),
('M-0002', 'Boğaziçi Kafe ve Restoran Ltd. Şti.','KURUMSAL', 'Beşiktaş',  '2345678901',  'Elif Koç',      'info@bogazicikafe.com.tr',    '0212 258 61 72', 'Çırağan Caddesi No: 12',                   'İstanbul', '2023-05-22'),
('M-0003', 'Ankara Eğitim Kurumları A.Ş.',       'KURUMSAL', 'Çankaya',   '3456789012',  'Burak Tunç',    'idari@ankaraegitim.com.tr',   '0312 425 33 18', 'Tunalı Hilmi Caddesi No: 88',              'Ankara',   '2024-01-15'),
('M-0004', 'Ali Veli Kara',                       'BIREYSEL', 'Karşıyaka', '12345678901', 'Ali Veli Kara', 'aliveli.kara@example.com',    '0541 234 56 78', 'Atatürk Mahallesi 1203. Sokak No: 7',      'İzmir',    '2024-03-04'),
('M-0005', 'Selin Yıldız',                        'BIREYSEL', 'Nilüfer',   '23456789012', 'Selin Yıldız',  'selin.yildiz@example.com',    '0542 345 67 89', 'Özlüce Mahallesi Gül Sokak No: 3',         'Bursa',    '2024-06-19'),
('M-0006', 'Karadeniz Ofis Çözümleri Ltd. Şti.', 'KURUMSAL', 'Ortahisar', '4567890123',  'Murat Başaran', 'murat@karadenizofis.com.tr',  '0462 322 90 14', 'Kalkınma Mahallesi Sanayi Sokak No: 21',   'Trabzon',  '2024-09-30');

INSERT INTO core.supplier (supplier_code, supplier_name, tax_office, tax_number, contact_person, email, phone, address, city, payment_terms_days) VALUES
('T-0001', 'Kuzey Orman Ürünleri San. ve Tic. A.Ş.',      'Kastamonu', '5678901234', 'Recep Aksoy',  'satis@kuzeyorman.com.tr',      '0366 214 55 60', 'Organize Sanayi Bölgesi 3. Cadde No: 5',        'Kastamonu', 45),
('T-0002', 'Anadolu Levha ve Kaplama Ltd. Şti.',           'Kayseri',   '6789012345', 'Gül Erdoğan',  'siparis@anadolulevha.com.tr',  '0352 336 78 90', 'Hacılar Sanayi Sitesi B Blok No: 14',           'Kayseri',   30),
('T-0003', 'Ege Hırdavat ve Bağlantı Elemanları A.Ş.',     'Bornova',   '7890123456', 'Tolga Karaca', 'tolga@egehirdavat.com.tr',     '0232 462 11 25', 'Işıkkent Sanayi Caddesi No: 62',                'İzmir',     30),
('T-0004', 'Marmara Boya ve Kimya San. Tic. Ltd. Şti.',    'Gebze',     '8901234567', 'Nur Özkan',    'nur.ozkan@marmaraboya.com.tr', '0262 644 20 37', 'Gebze Organize Sanayi Bölgesi 7. Sokak No: 9',  'Kocaeli',   60),
('T-0005', 'Bursa Döşemelik Kumaş ve Sünger A.Ş.',         'Osmangazi', '9012345678', 'Cemal Polat',  'cemal@bursakumas.com.tr',      '0224 261 47 83', 'Merinos Sanayi Bölgesi Tekstil Sokak No: 18',   'Bursa',     45),
('T-0006', 'Doğu Metal Mobilya Aksesuarları Ltd. Şti.',    'Ostim',     '0123456789', 'Sibel Yurt',   'sibel@dogumetal.com.tr',       '0312 354 92 06', 'Ostim Sanayi Sitesi 1234. Sokak No: 31',        'Ankara',    30);

-- 7.4 Items ---------------------------------------------------------------
INSERT INTO core.item
(item_code, item_name, description, category_code, uom_code,
 is_purchasable, is_manufacturable, is_consumable, is_sellable, is_serialized,
 standard_cost, list_price, reorder_level, lead_time_days) VALUES
('HM-0001', 'Masif Meşe Tahta 30 mm',
 'Kurutulmuş, kalibre edilmiş masif meşe tahta; masa ve sandalye iskeleti üretiminde kullanılır.',
 'HAMMADDE', 'M3', TRUE, FALSE, TRUE, FALSE, FALSE, 38500.00, NULL, 5.000, 14),
('HM-0002', 'MDF Levha 18 mm (210x280 cm)',
 'Yüksek yoğunluklu lif levha; dolap gövdesi ve raf yapımında kullanılır.',
 'HAMMADDE', 'ADET', TRUE, FALSE, TRUE, TRUE, FALSE, 1250.00, 1650.00, 20.000, 7),
('BL-0001', 'Çekmece Kulbu - Paslanmaz Çelik 128 mm',
 'Paslanmaz çelik çekmece ve kapak kulbu; montaj sırasında takılır, yedek parça olarak da satılır.',
 'BILESEN', 'ADET', TRUE, FALSE, TRUE, TRUE, FALSE, 18.50, 35.00, 200.000, 10),
('SM-0001', 'Ahşap Vidası 4x40 mm (200''lü paket)',
 'Çinko kaplama havşa başlı ahşap vidası; montajda tüketilir.',
 'SARF_MALZEME', 'PAKET', TRUE, FALSE, TRUE, FALSE, FALSE, 95.00, NULL, 50.000, 5),
('SM-0002', 'Su Bazlı Mat Vernik',
 'Mobilya yüzeyleri için çevre dostu, kokusuz, su bazlı mat vernik.',
 'SARF_MALZEME', 'LT', TRUE, FALSE, TRUE, FALSE, FALSE, 210.00, NULL, 40.000, 12),
('YM-0001', 'Masif Meşe Masa Ayağı 72 cm',
 'İşlenmiş ve zımparalanmış meşe masa ayağı; masa montajında kullanılır, yedek parça olarak da satılır.',
 'YARI_MAMUL', 'ADET', FALSE, TRUE, TRUE, TRUE, FALSE, 145.00, 290.00, 40.000, 3),
('BL-0002', 'Döşemelik Sandalye Oturağı',
 'Sünger dolgulu, kumaş kaplı sandalye oturağı; bazen dışarıdan hazır alınır, bazen atölyede üretilir.',
 'BILESEN', 'ADET', TRUE, TRUE, TRUE, FALSE, FALSE, 120.00, NULL, 60.000, 4),
('MM-0001', 'Meşe Yemek Masası 180x90 cm',
 'Masif meşe yemek masası; sipariş üzerine ölçü ve renk seçenekleriyle üretilir.',
 'MAMUL', 'ADET', FALSE, TRUE, FALSE, TRUE, TRUE, 4200.00, 9800.00, 0.000, 21),
('MM-0002', 'Döşemeli Yemek Sandalyesi Model S-100',
 'Meşe iskeletli, kumaş döşemeli yemek sandalyesi.',
 'MAMUL', 'ADET', FALSE, TRUE, FALSE, TRUE, FALSE, 950.00, 2250.00, 0.000, 14),
('MM-0003', 'Çalışma Masası 140x70 cm',
 'MDF gövdeli, 2 çekmeceli ofis çalışma masası.',
 'MAMUL', 'ADET', FALSE, TRUE, FALSE, TRUE, TRUE, 2100.00, 4950.00, 0.000, 10);

INSERT INTO core.item_supplier (item_id, supplier_id, supplier_item_code, unit_price, lead_time_days, min_order_quantity, is_preferred)
SELECT i.item_id, s.supplier_id, v.sup_item_code, v.price, v.lead, v.moq, v.pref
FROM (VALUES
 ('HM-0001', 'T-0001', 'KOP-MES-30',    38500.00, 14, 2.000,   TRUE),
 ('HM-0002', 'T-0002', 'AL-MDF-18',      1250.00,  7, 10.000,  TRUE),
 ('BL-0001', 'T-0006', 'DM-KLP-128',       18.50, 10, 100.000, TRUE),
 ('BL-0001', 'T-0003', 'EH-KLP-128',       19.75,  7, 200.000, FALSE),
 ('SM-0001', 'T-0003', 'EH-VDS-4X40',      95.00,  5, 20.000,  TRUE),
 ('SM-0002', 'T-0004', 'MB-VRN-SB-MAT',   210.00, 12, 20.000,  TRUE),
 ('BL-0002', 'T-0005', 'BK-OTR-STD',      120.00, 10, 50.000,  TRUE)
) AS v(item_code, sup_code, sup_item_code, price, lead, moq, pref)
JOIN core.item i     ON i.item_code     = v.item_code
JOIN core.supplier s ON s.supplier_code = v.sup_code;

-- 7.5 Engineering: BOMs, work centers, routings -------------------------
INSERT INTO engineering.bom (item_id, revision, status, base_quantity, effective_from, approved_by)
SELECT i.item_id, 'A', 'ONAYLI', 1, DATE '2026-01-01', e.employee_id
FROM core.item i
CROSS JOIN core.employee e
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
JOIN core.item p        ON p.item_code = v.parent_code
JOIN engineering.bom b  ON b.item_id = p.item_id AND b.revision = 'A'
JOIN core.item c        ON c.item_code = v.comp_code;

INSERT INTO engineering.work_center (work_center_code, work_center_name, department_id, capacity_hours_per_day, hourly_rate)
SELECT v.code, v.name, d.department_id, v.capacity, v.rate
FROM (VALUES
 ('WC-KESIM',   'Kesim Atölyesi',        'URT', 16.00, 600.00),
 ('WC-ZIMPARA', 'Zımpara Hattı',         'URT',  8.00, 350.00),
 ('WC-MONTAJ',  'Montaj Atölyesi',       'URT', 24.00, 450.00),
 ('WC-BOYA',    'Boya ve Vernik Kabini', 'URT',  8.00, 500.00),
 ('WC-KALITE',  'Kalite Kontrol İstasyonu','KKT', 8.00, 400.00)
) AS v(code, name, dept_code, capacity, rate)
JOIN core.department d ON d.department_code = v.dept_code;

INSERT INTO engineering.routing (item_id, revision, status)
SELECT i.item_id, 'A', 'ONAYLI'
FROM core.item i
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
JOIN core.item i                ON i.item_code = v.item_code
JOIN engineering.routing r      ON r.item_id = i.item_id AND r.revision = 'A'
JOIN engineering.work_center w  ON w.work_center_code = v.wc_code;

-- 7.6 Planning: sales orders, production plan, MRP -----------------------
INSERT INTO planning.sales_order (order_no, customer_id, order_date, requested_delivery_date, status, created_by)
SELECT v.order_no, c.customer_id, v.order_date::date, v.delivery::date, v.status, e.employee_id
FROM (VALUES
 ('SO-2026-0001', 'M-0001', '2026-10-12', '2026-12-15', 'ONAYLANDI', 'E-0002'),
 ('SO-2026-0002', 'M-0003', '2026-10-20', '2026-12-30', 'ONAYLANDI', 'E-0002'),
 ('SO-2026-0003', 'M-0004', '2026-10-28', '2026-12-10', 'ONAYLANDI', 'E-0002')
) AS v(order_no, cust_code, order_date, delivery, status, emp_no)
JOIN core.customer c ON c.customer_code = v.cust_code
JOIN core.employee e ON e.employee_no   = v.emp_no;

INSERT INTO planning.sales_order_line (sales_order_id, line_no, item_id, quantity, unit_price)
SELECT so.sales_order_id, v.line_no, i.item_id, v.qty, v.price
FROM (VALUES
 ('SO-2026-0001', 1, 'MM-0002', 40, 2250.00),
 ('SO-2026-0001', 2, 'MM-0001', 10, 9800.00),
 ('SO-2026-0002', 1, 'MM-0003', 25, 4950.00),
 ('SO-2026-0003', 1, 'MM-0001',  1, 9800.00)
) AS v(order_no, line_no, item_code, qty, price)
JOIN planning.sales_order so ON so.order_no  = v.order_no
JOIN core.item i             ON i.item_code  = v.item_code;

INSERT INTO planning.production_plan (plan_no, plan_name, period_start, period_end, status, created_by, approved_by, created_at)
SELECT 'PP-2026-11', 'Kasım-Aralık 2026 Üretim Planı', DATE '2026-10-26', DATE '2026-12-18',
       'ONAYLANDI', c.employee_id, a.employee_id, TIMESTAMP '2026-10-23 14:00'
FROM core.employee c, core.employee a
WHERE c.employee_no = 'E-0008' AND a.employee_no = 'E-0003';

INSERT INTO planning.production_plan_line (production_plan_id, line_no, item_id, sales_order_line_id, planned_quantity, planned_start_date, planned_finish_date)
SELECT pp.production_plan_id, v.line_no, i.item_id, sol.sales_order_line_id, v.qty, v.start_date::date, v.finish_date::date
FROM (VALUES
 (1, 'MM-0002', 'SO-2026-0001', 1,    40, '2026-11-16', '2026-12-04'),
 (2, 'MM-0001', 'SO-2026-0001', 2,    10, '2026-11-09', '2026-12-04'),
 (3, 'MM-0003', 'SO-2026-0002', 1,    25, '2026-11-23', '2026-12-18'),
 (4, 'MM-0001', 'SO-2026-0003', 1,     1, '2026-10-29', '2026-11-04'),
 (5, 'YM-0001', NULL,           NULL, 44, '2026-10-27', '2026-11-03'),   -- dependent demand: legs for 11 tables
 (6, 'BL-0002', NULL,           NULL, 40, '2026-11-04', '2026-11-20')    -- dependent demand: seats for 40 chairs
) AS v(line_no, item_code, so_no, so_line_no, qty, start_date, finish_date)
JOIN planning.production_plan pp ON pp.plan_no = 'PP-2026-11'
JOIN core.item i                 ON i.item_code = v.item_code
LEFT JOIN planning.sales_order so       ON so.order_no = v.so_no
LEFT JOIN planning.sales_order_line sol ON sol.sales_order_id = so.sales_order_id AND sol.line_no = v.so_line_no;

-- MRP explosion
INSERT INTO planning.material_requirement (production_plan_line_id, component_item_id, gross_requirement, on_hand_quantity, needed_by_date)
SELECT ppl.production_plan_line_id, bl.component_item_id,
       ROUND(ppl.planned_quantity / b.base_quantity * bl.quantity_per * (1 + bl.scrap_percent / 100), 4),
       oh.on_hand, ppl.planned_start_date
FROM planning.production_plan_line ppl
JOIN engineering.bom b       ON b.item_id = ppl.item_id AND b.revision = 'A'
JOIN engineering.bom_line bl ON bl.bom_id = b.bom_id
JOIN core.item ci            ON ci.item_id = bl.component_item_id
JOIN (VALUES
 ('HM-0001', 2.5000), ('HM-0002', 30.0000), ('BL-0001', 120.0000), ('SM-0001', 40.0000),
 ('SM-0002', 25.0000), ('YM-0001', 10.0000), ('BL-0002', 5.0000)
) AS oh(item_code, on_hand) ON oh.item_code = ci.item_code;

-- 7.7 Production: orders, components, operations, issues, receipts, units
INSERT INTO production.production_order
(order_no, production_plan_line_id, item_id, bom_id, routing_id, planned_quantity, status,
 planned_start_date, planned_finish_date, actual_start_date, actual_finish_date, responsible_employee_id)
SELECT v.order_no, ppl.production_plan_line_id, ppl.item_id, b.bom_id, r.routing_id, ppl.planned_quantity, v.status,
       ppl.planned_start_date, ppl.planned_finish_date, v.act_start::date, v.act_finish::date, e.employee_id
FROM (VALUES
 ('UE-2026-0001', 5, 'TAMAMLANDI',  '2026-10-27', '2026-11-03', 'E-0005'),
 ('UE-2026-0002', 4, 'TAMAMLANDI',  '2026-10-29', '2026-11-04', 'E-0005'),
 ('UE-2026-0003', 6, 'DEVAM_EDIYOR','2026-11-04', NULL,         'E-0005'),
 ('UE-2026-0004', 1, 'PLANLANDI',   NULL,         NULL,         'E-0003'),
 ('UE-2026-0005', 2, 'PLANLANDI',   NULL,         NULL,         'E-0003'),
 ('UE-2026-0006', 3, 'PLANLANDI',   NULL,         NULL,         'E-0003')
) AS v(order_no, plan_line_no, status, act_start, act_finish, resp_no)
JOIN planning.production_plan_line ppl ON ppl.line_no = v.plan_line_no
JOIN engineering.bom b                 ON b.item_id = ppl.item_id AND b.revision = 'A'
JOIN engineering.routing r             ON r.item_id = ppl.item_id AND r.revision = 'A'
JOIN core.employee e                   ON e.employee_no = v.resp_no;

INSERT INTO production.production_order_component (production_order_id, component_item_id, required_quantity)
SELECT po.production_order_id, bl.component_item_id,
       ROUND(po.planned_quantity / b.base_quantity * bl.quantity_per * (1 + bl.scrap_percent / 100), 4)
FROM production.production_order po
JOIN engineering.bom b       ON b.bom_id = po.bom_id
JOIN engineering.bom_line bl ON bl.bom_id = b.bom_id;

INSERT INTO production.production_order_operation
(production_order_id, routing_operation_id, planned_setup_minutes, planned_run_minutes, status, operator_id)
SELECT s.production_order_id, s.routing_operation_id, s.setup_minutes, s.run_minutes, s.op_status,
       CASE WHEN s.op_status <> 'BEKLIYOR'
            THEN (SELECT employee_id FROM core.employee WHERE employee_no = 'E-0005') END
FROM (
    SELECT po.production_order_id, ro.routing_operation_id, ro.setup_minutes,
           ro.run_minutes_per_unit * po.planned_quantity AS run_minutes,
           CASE WHEN po.status = 'TAMAMLANDI'                              THEN 'TAMAMLANDI'
                WHEN po.status = 'DEVAM_EDIYOR' AND ro.operation_no = 10   THEN 'TAMAMLANDI'
                WHEN po.status = 'DEVAM_EDIYOR' AND ro.operation_no = 20   THEN 'DEVAM_EDIYOR'
                ELSE 'BEKLIYOR' END AS op_status
    FROM production.production_order po
    JOIN engineering.routing_operation ro ON ro.routing_id = po.routing_id
) s;

-- Warehouse issues all components for the three orders that have started
INSERT INTO production.material_issue (production_order_id, component_item_id, quantity, issued_by, issued_at)
SELECT c.production_order_id, c.component_item_id, c.required_quantity, e.employee_id, v.issued_at::timestamp
FROM production.production_order_component c
JOIN production.production_order po ON po.production_order_id = c.production_order_id
JOIN (VALUES
 ('UE-2026-0001', '2026-10-27 08:30'),
 ('UE-2026-0002', '2026-10-29 08:30'),
 ('UE-2026-0003', '2026-11-04 08:15')
) AS v(order_no, issued_at) ON v.order_no = po.order_no
JOIN core.employee e ON e.employee_no = 'E-0009';

INSERT INTO production.production_receipt (production_order_id, quantity, received_by, inspected_by, received_at, notes)
SELECT po.production_order_id, po.planned_quantity, r.employee_id, k.employee_id, v.received_at::timestamp, v.notes
FROM (VALUES
 ('UE-2026-0001', '2026-11-03 16:45', '44 adet meşe masa ayağı kalite kontrolden geçti ve depoya girdi.'),
 ('UE-2026-0002', '2026-11-04 17:10', 'Yemek masası kalite kontrolden geçti ve depoya girdi.')
) AS v(order_no, received_at, notes)
JOIN production.production_order po ON po.order_no = v.order_no
JOIN core.employee r ON r.employee_no = 'E-0009'
JOIN core.employee k ON k.employee_no = 'E-0007';

-- MM-0001 is serialized
INSERT INTO production.item_unit (item_id, production_order_id, serial_number, status)
SELECT po.item_id, po.production_order_id, 'MM1-2026-000001', 'STOKTA'
FROM production.production_order po
WHERE po.order_no = 'UE-2026-0002';
