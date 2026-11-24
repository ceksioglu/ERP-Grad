# O2C Data Dictionary

This dictionary describes the installed PostgreSQL prototype, including the baseline master records it uses. PK is a primary key, FK is a foreign key, UQ is a unique constraint, and CK is a check constraint. Constraint references below each table give the exact PostgreSQL definitions.

## `public.customer`

Shared sales customer.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `customer_id` | `integer` | Required, generated identity | PK 1 | Surrogate customer identifier |
| `customer_code` | `character varying(10)` | Required | UQ 2 | Stable business code |
| `customer_name` | `character varying(150)` | Required | — | Person name or company title |
| `customer_type` | `character varying(12)` | Required | CK 3 | Individual or corporate classification |
| `tax_office` | `character varying(60)` | Nullable | — | Registered tax office |
| `tax_number` | `character varying(11)` | Nullable | — | Tax or identity registration number |
| `contact_person` | `character varying(100)` | Nullable | — | Main contact for this customer |
| `email` | `character varying(120)` | Nullable | — | Contact email |
| `phone` | `character varying(20)` | Nullable | — | Contact phone |
| `address` | `character varying(250)` | Nullable | — | Street or billing address |
| `city` | `character varying(50)` | Nullable | — | Address city |
| `created_date` | `date` | Required, default `CURRENT_DATE` | — | Date the master record was created |
| `is_active` | `boolean` | Required, default `true` | — | Active master record flag |

1. `PRIMARY KEY (customer_id)`
2. `UNIQUE (customer_code)`
3. `CHECK (((customer_type)::text = ANY ((ARRAY['BIREYSEL'::character varying, 'KURUMSAL'::character varying])::text[])))`

## `public.department`

Organizational department from the baseline.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `department_id` | `integer` | Required, generated identity | PK 1 | Surrogate department identifier |
| `department_code` | `character varying(10)` | Required | UQ 2 | Stable department code |
| `department_name` | `character varying(100)` | Required | — | Department display name |
| `description` | `text` | Nullable | — | Organizational responsibilities |
| `location` | `character varying(100)` | Nullable | — | Office or facility name |
| `is_active` | `boolean` | Required, default `true` | — | Active department flag |

1. `PRIMARY KEY (department_id)`
2. `UNIQUE (department_code)`

## `public.employee`

Shared employee master for transaction actors.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `employee_id` | `integer` | Required, generated identity | PK 1 | Surrogate employee identifier |
| `employee_no` | `character varying(10)` | Required | UQ 3 | Employee reference number |
| `first_name` | `character varying(50)` | Required | — | Given name |
| `last_name` | `character varying(50)` | Required | — | Family name |
| `job_title` | `character varying(100)` | Required | — | Position title in the current baseline |
| `email` | `character varying(120)` | Nullable | UQ 2 | Work email |
| `phone` | `character varying(20)` | Nullable | — | Work phone |
| `hire_date` | `date` | Required | — | Employment start date |
| `monthly_salary` | `numeric(12,2)` | Nullable | CK 4 | Monthly compensation in the baseline |
| `is_active` | `boolean` | Required, default `true` | — | Active employee flag |

1. `PRIMARY KEY (employee_id)`
2. `UNIQUE (email)`
3. `UNIQUE (employee_no)`
4. `CHECK ((monthly_salary >= (0)::numeric))`

## `public.item`

Product type shared by purchasing, stock, and sales.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `item_id` | `integer` | Required, generated identity | PK 1 | Surrogate item identifier |
| `item_code` | `character varying(20)` | Required | UQ 2 | Stock code |
| `item_name` | `character varying(150)` | Required | — | Product display name |
| `description` | `text` | Nullable | — | Product details |
| `item_category` | `character varying(30)` | Required | CK 4 | Classification code in the baseline |
| `unit_of_measure` | `character varying(10)` | Required | CK 9 | Unit applied to movement and order quantities |
| `is_purchasable` | `boolean` | Required, default `false` | CK 3 | Can be acquired from a supplier |
| `is_manufacturable` | `boolean` | Required, default `false` | CK 3 | Can be manufactured |
| `is_consumable` | `boolean` | Required, default `false` | CK 3 | Can be consumed in production |
| `is_sellable` | `boolean` | Required, default `false` | CK 3, CK 10 | Can appear on a sales order line |
| `is_serialized` | `boolean` | Required, default `false` | — | Signals a product intended for unit-level tracking |
| `standard_cost` | `numeric(12,2)` | Nullable | CK 8 | Reference cost per unit |
| `list_price` | `numeric(12,2)` | Nullable | CK 6, CK 10 | Reference selling price per unit |
| `reorder_level` | `numeric(12,3)` | Nullable | CK 7 | Reference replenishment threshold |
| `lead_time_days` | `integer` | Nullable | CK 5 | Reference lead time in days |
| `is_active` | `boolean` | Required, default `true` | — | Active item flag |

1. `PRIMARY KEY (item_id)`
2. `UNIQUE (item_code)`
3. `CHECK ((is_purchasable OR is_manufacturable OR is_consumable OR is_sellable))`
4. `CHECK (((item_category)::text = ANY ((ARRAY['HAMMADDE'::character varying, 'YARI_MAMUL'::character varying, 'BILESEN'::character varying, 'SARF_MALZEME'::character varying, 'MAMUL'::character varying])::text[])))`
5. `CHECK ((lead_time_days >= 0))`
6. `CHECK ((list_price >= (0)::numeric))`
7. `CHECK ((reorder_level >= (0)::numeric))`
8. `CHECK ((standard_cost >= (0)::numeric))`
9. `CHECK (((unit_of_measure)::text = ANY ((ARRAY['ADET'::character varying, 'KG'::character varying, 'LT'::character varying, 'M'::character varying, 'M2'::character varying, 'M3'::character varying, 'PAKET'::character varying, 'TAKIM'::character varying])::text[])))`
10. `CHECK (((NOT is_sellable) OR (list_price IS NOT NULL)))`

## `public.supplier`

Supplier master used by the goods receipt.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `supplier_id` | `integer` | Required, generated identity | PK 1 | Surrogate supplier identifier |
| `supplier_code` | `character varying(10)` | Required | UQ 2 | Stable vendor code |
| `supplier_name` | `character varying(150)` | Required | — | Registered supplier name |
| `tax_office` | `character varying(60)` | Nullable | — | Registered tax office |
| `tax_number` | `character varying(11)` | Nullable | — | Tax registration number |
| `contact_person` | `character varying(100)` | Nullable | — | Primary supplier contact |
| `email` | `character varying(120)` | Nullable | — | Contact email |
| `phone` | `character varying(20)` | Nullable | — | Contact phone |
| `address` | `character varying(250)` | Nullable | — | Supplier street address |
| `city` | `character varying(50)` | Nullable | — | Address city |
| `payment_terms_days` | `integer` | Nullable | CK 3 | Supplier payment term in days |
| `is_active` | `boolean` | Required, default `true` | — | Active supplier flag |

1. `PRIMARY KEY (supplier_id)`
2. `UNIQUE (supplier_code)`
3. `CHECK ((payment_terms_days >= 0))`

## `inventory.stock_location`

Shared store or warehouse for inbound and outbound stock.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `location_id` | `integer` | Required, generated identity | PK 1 | Surrogate stock-location identifier |
| `location_code` | `character varying(24)` | Required | UQ 2 | Stable store or warehouse code |
| `location_name` | `character varying(100)` | Required | — | Location display name |
| `location_type` | `character varying(12)` | Required | CK 3 | Store or warehouse classification |

1. `PRIMARY KEY (location_id)`
2. `UNIQUE (location_code)`
3. `CHECK (((location_type)::text = ANY ((ARRAY['STORE'::character varying, 'WAREHOUSE'::character varying])::text[])))`

## `inventory.stock_key`

Concurrency key for one item at one location.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `location_id` | `integer` | Required | PK 1, FK 3 | Location side of the stock lock key |
| `item_id` | `integer` | Required | PK 1, FK 2 | Item side of the stock lock key |

1. `PRIMARY KEY (location_id, item_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (location_id) REFERENCES inventory.stock_location(location_id)`

## `inventory.goods_receipt`

Posted inbound receipt header.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `receipt_id` | `integer` | Required, generated identity | PK 1 | Surrogate goods receipt identifier |
| `receipt_no` | `character varying(24)` | Required | UQ 5 | Unique goods receipt number |
| `supplier_id` | `integer` | Required | FK 4 | Supplier that sent the goods |
| `location_id` | `integer` | Required | FK 2 | Destination store or warehouse |
| `received_on` | `date` | Required | — | Business date on which stock becomes available |
| `received_by` | `integer` | Required | FK 3 | Receiving employee |

1. `PRIMARY KEY (receipt_id)`
2. `FOREIGN KEY (location_id) REFERENCES inventory.stock_location(location_id)`
3. `FOREIGN KEY (received_by) REFERENCES public.employee(employee_id)`
4. `FOREIGN KEY (supplier_id) REFERENCES public.supplier(supplier_id)`
5. `UNIQUE (receipt_no)`

## `inventory.goods_receipt_line`

Quantity accepted for one item on a goods receipt.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `receipt_line_id` | `integer` | Required, generated identity | PK 1 | Surrogate receipt-line identifier |
| `receipt_id` | `integer` | Required | FK 3, UQ 4 | Parent goods receipt |
| `line_no` | `integer` | Required | UQ 4, CK 5 | Positive line number within the receipt |
| `item_id` | `integer` | Required | FK 2 | Received item |
| `quantity` | `numeric(12,3)` | Required | CK 6 | Accepted quantity in the item unit |

1. `PRIMARY KEY (receipt_line_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (receipt_id) REFERENCES inventory.goods_receipt(receipt_id)`
4. `UNIQUE (receipt_id, line_no)`
5. `CHECK ((line_no > 0))`
6. `CHECK (((quantity > (0)::numeric) AND (quantity <> 'NaN'::numeric)))`

## `inventory.inventory_movement`

Append-only shared stock ledger.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `movement_id` | `integer` | Required, generated identity | PK 1 | Surrogate movement identifier |
| `movement_no` | `character varying(32)` | Required | UQ 7 | Unique movement reference |
| `movement_type` | `character varying(12)` | Required | CK 9, CK 10 | Receipt or sales issue; P2M adds `PROD_RECEIPT` and `PROD_ISSUE` (see `p2m-data-dictionary.md`) |
| `location_id` | `integer` | Required | FK 3 | Location affected by the movement |
| `item_id` | `integer` | Required | FK 2, FK 4 | Stock item affected by the movement |
| `order_line_id` | `integer` | Nullable | FK 4, CK 9 | Sales line for a sales issue |
| `receipt_line_id` | `integer` | Nullable | FK 5, UQ 8, CK 9 | Source document line for a receipt |
| `moved_on` | `date` | Required | — | Effective stock business date |
| `quantity` | `numeric(12,3)` | Required | CK 11 | Positive magnitude in the item unit |
| `recorded_by` | `integer` | Required | FK 6 | Employee who recorded the movement |

1. `PRIMARY KEY (movement_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (location_id) REFERENCES inventory.stock_location(location_id)`
4. `FOREIGN KEY (order_line_id, item_id) REFERENCES sales.sales_order_line(order_line_id, item_id)`
5. `FOREIGN KEY (receipt_line_id) REFERENCES inventory.goods_receipt_line(receipt_line_id)`
6. `FOREIGN KEY (recorded_by) REFERENCES public.employee(employee_id)`
7. `UNIQUE (movement_no)`
8. `UNIQUE (receipt_line_id)`
9. `CHECK (((((movement_type)::text = 'SALE_ISSUE'::text) AND (order_line_id IS NOT NULL) AND (receipt_line_id IS NULL)) OR (((movement_type)::text = 'RECEIPT'::text) AND (receipt_line_id IS NOT NULL) AND (order_line_id IS NULL))))`
10. `CHECK (((movement_type)::text = ANY ((ARRAY['RECEIPT'::character varying, 'SALE_ISSUE'::character varying])::text[])))`
11. `CHECK (((quantity > (0)::numeric) AND (quantity <> 'NaN'::numeric)))`

## `sales.sales_order`

Order header for an individual or corporate customer.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `order_id` | `integer` | Required, generated identity | PK 1 | Surrogate sales-order identifier |
| `order_no` | `character varying(24)` | Required | UQ 4 | Unique order number |
| `customer_id` | `integer` | Required | FK 3 | Customer placing the order |
| `ordered_on` | `date` | Required | — | Order business date |
| `currency_code` | `character varying(3)` | Required | CK 5 | Three-letter currency code used by the order, invoice, and payments |
| `created_by` | `integer` | Required | FK 2 | Sales employee entering the order |
| `status` | `character varying(12)` | Required, default `'DRAFT'::character varying` | CK 6 | Draft or confirmed order state |

1. `PRIMARY KEY (order_id)`
2. `FOREIGN KEY (created_by) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (customer_id) REFERENCES public.customer(customer_id)`
4. `UNIQUE (order_no)`
5. `CHECK (((currency_code)::text ~ '^[A-Z]{3}$'::text))`
6. `CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'CONFIRMED'::character varying])::text[])))`

## `sales.sales_order_line`

Quantity and agreed price for one sellable item.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `order_line_id` | `integer` | Required, generated identity | PK 1, UQ 5 | Surrogate order-line identifier |
| `order_id` | `integer` | Required | FK 3, UQ 4 | Parent sales order |
| `line_no` | `integer` | Required | UQ 4, CK 6 | Positive line number within the order |
| `item_id` | `integer` | Required | FK 2, UQ 5 | Sellable item |
| `quantity` | `numeric(12,3)` | Required | CK 7 | Quantity ordered in the item unit |
| `unit_price` | `numeric(12,2)` | Required | CK 8 | Agreed pre-tax price per unit in the order currency |

1. `PRIMARY KEY (order_line_id)`
2. `FOREIGN KEY (item_id) REFERENCES public.item(item_id)`
3. `FOREIGN KEY (order_id) REFERENCES sales.sales_order(order_id)`
4. `UNIQUE (order_id, line_no)`
5. `UNIQUE (order_line_id, item_id)`
6. `CHECK ((line_no > 0))`
7. `CHECK (((quantity > (0)::numeric) AND (quantity <> 'NaN'::numeric)))`
8. `CHECK (((unit_price >= (0)::numeric) AND (unit_price <> 'NaN'::numeric)))`

## `sales.customer_invoice`

Single invoice for an order that has been fully issued.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `invoice_id` | `integer` | Required, generated identity | PK 1 | Surrogate customer-invoice identifier |
| `invoice_no` | `character varying(24)` | Required | UQ 4 | Unique invoice number |
| `order_id` | `integer` | Required | FK 3, UQ 5 | Fully issued order being billed |
| `issued_on` | `date` | Required | CK 6 | Invoice issue date |
| `due_on` | `date` | Required | CK 6 | Payment due date |
| `total_amount` | `numeric(22,2)` | Required | CK 7 | Sum of rounded order-line amounts in the order currency |
| `issued_by` | `integer` | Required | FK 2 | Employee posting the invoice |

1. `PRIMARY KEY (invoice_id)`
2. `FOREIGN KEY (issued_by) REFERENCES public.employee(employee_id)`
3. `FOREIGN KEY (order_id) REFERENCES sales.sales_order(order_id)`
4. `UNIQUE (invoice_no)`
5. `UNIQUE (order_id)`
6. `CHECK ((due_on >= issued_on))`
7. `CHECK (((total_amount > (0)::numeric) AND (total_amount <> 'NaN'::numeric)))`

## `sales.customer_payment`

One payment allocated to one customer invoice.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `payment_id` | `integer` | Required, generated identity | PK 1 | Surrogate payment identifier |
| `payment_no` | `character varying(32)` | Required | UQ 4 | Unique payment reference |
| `invoice_id` | `integer` | Required | FK 2 | Invoice receiving the payment |
| `received_on` | `date` | Required | — | Date payment was received |
| `amount` | `numeric(22,2)` | Required | CK 5 | Positive amount in the invoice currency |
| `recorded_by` | `integer` | Required | FK 3 | Employee posting the payment |

1. `PRIMARY KEY (payment_id)`
2. `FOREIGN KEY (invoice_id) REFERENCES sales.customer_invoice(invoice_id)`
3. `FOREIGN KEY (recorded_by) REFERENCES public.employee(employee_id)`
4. `UNIQUE (payment_no)`
5. `CHECK (((amount > (0)::numeric) AND (amount <> 'NaN'::numeric)))`

## `inventory.stock_balance`

Read-only aggregate of posted movements by location and item.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `location_id` | `integer` | Derived | — | Location in the movement ledger |
| `item_id` | `integer` | Derived | — | Item in the movement ledger |
| `quantity_on_hand` | `numeric` | Derived | — | Inbound less outbound posted movements, signed by `inventory.signed_quantity` |

## `sales.customer_invoice_balance`

Read-only receivables view by invoice.

| Column | PostgreSQL type | Null and default | Keys and checks | Meaning |
| --- | --- | --- | --- | --- |
| `invoice_id` | `integer` | Derived | — | Invoice identifier |
| `invoice_no` | `character varying(24)` | Derived | — | Invoice number |
| `order_no` | `character varying(24)` | Derived | — | Order number |
| `customer_id` | `integer` | Derived | — | Customer from the sales order |
| `currency_code` | `character varying(3)` | Derived | — | Currency from the sales order |
| `total_amount` | `numeric(22,2)` | Derived | — | Invoice total |
| `paid_amount` | `numeric` | Derived | — | Sum of payments or zero |
| `balance_due` | `numeric` | Derived | — | Invoice total less total payments |

## Transaction Rules

- A sales order starts in draft and needs at least one line before confirmation. Confirmed orders and their lines are fixed. A sales line requires an active, sellable item.
- Each receipt line requires an active, purchasable item and automatically posts one inbound movement linked to its source. Receipt headers, receipt lines, and movements are retained as posted records.
- A sales issue references the matching item and confirmed order line. Cumulative issues cannot exceed the order quantity. Stock must remain nonnegative at the end of each business date, including dates affected by a backdated posting.
- The invoice date must cover all issues for the order. Each order has at most one invoice. The total is calculated from rounded line amounts.
- Payments use the order currency and may be partial. The payment date is on or after the invoice date and the total received cannot exceed the invoice total.
- `inventory.signed_quantity(movement_type, quantity)` gives each movement its direction: `RECEIPT` and `PROD_RECEIPT` add stock, every other type removes it. The stock view and the negative-stock check both use it.
- The two balance views are calculated from posted records. `inventory.stock_key` holds only the key used to serialize changes for the same item at the same location.

The prototype uses `public.item` and `inventory.stock_location` for the shared identifiers. The team must agree on the final master schema and connect purchase-order lines to goods receipts before full P2P integration. The baseline department has no FK from `public.employee`. When `p2m-database.sql` is installed, `inventory.inventory_movement` gains the `material_issue_id` and `production_receipt_id` columns and its two check constraints (`inventory_movement_type_check`, `inventory_movement_source_check`) are widened to the production movement types; `p2m-data-dictionary.md` lists the extended definitions.
