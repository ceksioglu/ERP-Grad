# Retail ERP Order to Cash Logical Model

Task 2 draft for team review. The model follows a retail sale from the customer order through stock issue, invoicing, and payment. It uses shared customer, item, employee, and inventory records across the ERP cycles. The Plan to Manufacture (P2M) module builds on the same records and stock ledger; see `p2m-logical-model.md`.

## Relations and Keys

| Relation | Primary key | Foreign keys and principal attributes |
| --- | --- | --- |
| `Customer` | `customer_id` | Customer code, name, billing and contact information |
| `Employee` | `employee_id` | Employee reference shared with H2R |
| `ItemCategory` | `category_id` | Category code, category name |
| `Item` | `item_id` | `category_id` → `ItemCategory`, item code, name, unit of measure, applicable roles |
| `StockLocation` | `location_id` | Location code, name, location type such as store or warehouse |
| `GoodsReceipt` | `receipt_id` | `supplier_id` → `Supplier`, `location_id` → `StockLocation`, `received_by` → `Employee`, receipt number and receipt date |
| `GoodsReceiptLine` | `receipt_line_id` | `receipt_id` → `GoodsReceipt`, `item_id` → `Item`, line number and quantity |
| `SalesOrder` | `order_id` | `customer_id` → `Customer`, `created_by` → `Employee`, order number, order date, status, currency |
| `SalesOrderLine` | `order_line_id` | `order_id` → `SalesOrder`, `item_id` → `Item`, line number, ordered quantity, agreed unit price |
| `InventoryMovement` | `movement_id` | `item_id` → `Item`, `location_id` → `StockLocation`, `recorded_by` → `Employee`, `order_line_id` → `SalesOrderLine` for a sales issue or `receipt_line_id` → `GoodsReceiptLine` for a receipt, movement type, date, quantity |
| `CustomerInvoice` | `invoice_id` | `order_id` → `SalesOrder`, `issued_by` → `Employee`, invoice number, issue date, due date, invoiced total |
| `CustomerPayment` | `payment_id` | `invoice_id` → `CustomerInvoice`, `recorded_by` → `Employee`, payment reference, received date, amount |

`Item` identifies a type of physical good. A desk model or a chair model has one item record regardless of how many units are stocked. An item can have multiple roles, such as purchasable and sellable, at the same time.

## Cardinalities and Business Rules

- A customer can place many orders. Each order belongs to one customer and is recorded by one employee. An order needs at least one line before confirmation.
- Each order line references one sellable item. The pair `(order_id, line_number)` is unique. Quantity is positive and the agreed unit price is nonnegative.
- A sales line can have zero or more stock issues, including issues from different locations. Each issue references one line and uses that line's item. The total issued quantity cannot exceed the ordered quantity. P2P receipts and O2C issues use the same movement ledger, with the direction determined by the movement type.
- Each goods receipt line creates one inbound stock movement. The per-location item balance is derived from the ledger. The balance must stay nonnegative at the end of every business date, including after backdated transactions.
- The proposed first version allows one invoice per order after the ordered quantities have been issued. Each invoice can receive zero or more payments, including partial payments. Invoice and payment amounts are positive and use the order currency. Order and invoice numbers are unique. The due date is on or after the invoice date.
- The invoice's customer comes from its order. The paid total is the sum of its payments and the outstanding balance is the invoiced total minus the paid total.

## Example Transaction

The demo creates an individual customer who orders two units at 2,500 TRY each. A goods receipt posts 10 units to the store ledger. The store issues two against the order line and leaves eight units in stock. A payment of 2,000 TRY leaves 3,000 TRY outstanding on the 5,000 TRY invoice. A second payment of 3,000 TRY closes the balance.

## Team Review Before the Physical Model

- Agree on shared item and location keys and the P2P/O2C movement ledger. Confirm how purchase receipts and sales issues identify their source records.
- Confirm whether split invoicing, returns, credit notes, taxes, discounts, and overpayments belong in the first version. Those choices affect invoice lines, stock movements, and payment allocation.
- Once the logical model is agreed, map the relations to PostgreSQL types, constraints, and indexes. Use the agreed schema to implement and test the shared database, then document the tables and attributes in the project data dictionary.

## Proposed Shared Integration Contract

| Area | Proposed standard | O2C application |
| --- | --- | --- |
| Master identity | Keep one `public.item`, `public.employee`, `public.department`, `public.customer`, and `public.supplier` in the initial shared database. Use generated integer PKs for FKs. Resolve fixture and migration records by unique business codes such as `item_code`, `employee_no`, `customer_code`, and `supplier_code`. | Orders and stock movements already use the shared IDs. Map any future schema move by business code before switching references. |
| Product and location | Keep one `inventory.stock_location` with a unique `location_code` and a `STORE` or `WAREHOUSE` type. Standardize item categories, base units, and purchasable and sellable flags across cycles. Propose category and unit lookup tables as a shared migration. | Keep item and location IDs unchanged through ordering, receipt, and sales issue. Continue checking that sales items are active and sellable. |
| Employee and department | H2R owns employee identity and dated position and department assignments. P2P and O2C retain employee FKs for each action. Use the transaction date for historical assignment lookup. | Keep `created_by`, `recorded_by`, and `issued_by` on the existing sales objects. Join H2R assignments for departmental reporting once the shared H2R model is available. |
| P2P receipt and sales issue | P2P supplies the approved purchase order and purchase-order line. Add `inventory.goods_receipt_line.purchase_order_line_id` once the P2P table is agreed. Enforce matching item and supplier, receipt timing, and cumulative quantity against the approved order. | Use the current receipt-line trigger as the single path to inbound stock. Sales issues continue to reference `sales.sales_order_line` in the same `inventory.inventory_movement` ledger. |
| Movement integrity | Use positive quantities in the item base unit. Movement type sets direction through `inventory.signed_quantity`: `RECEIPT` and `PROD_RECEIPT` add stock, `SALE_ISSUE` and `PROD_ISSUE` remove it. One receipt line posts one `RECEIPT`. A `SALE_ISSUE` references the matching sales order line. Use the effective date for the daily nonnegative stock rule and derive balances from movements. | The prototype enforces one receipt posting per line, rejects negative daily stock, and exposes `inventory.stock_balance` for reads. |
| Dates and amounts | Use `DATE` for business dates and `NUMERIC(12,3)` for quantities. Use `NUMERIC(12,2)` for unit prices and `NUMERIC(22,2)` for document amounts and payments. Persist the three-letter currency code on each order and carry it into related invoices and payments. | Retain the current numeric types, order currency, and positive payment rule. P2P and O2C each balance their own invoices. |

Create shared masters first, then module tables, then cross-module keys and triggers that require both source and target tables. Apply seed data and test scripts last. Activity Set 1 runs in its own database. P2M installs into the same database after O2C and posts production issues and receipts to the shared ledger.

For acceptance, H2R supplies distinct sales, warehouse, and finance employees. P2P orders and receives 10 units of one item at one location. The receipt posts exactly one movement for the line. O2C sells 2 units from that location and leaves 8 in stock, issues a 5,000 TRY invoice, and closes it with payments of 2,000 TRY and 3,000 TRY. Verify that a mismatched receipt item, repeat posting, premature stock issue, and an unknown employee are rejected. The current prototype verifies the receipt-to-cash segment. The purchase-order FK and dated H2R assignments are integration dependencies.

## PostgreSQL Prototype

Use a fresh test database. Run `db_init.sql`, then `o2c-database.sql`, then `o2c-demo.sql`. To include manufacturing, run `p2m-database.sql` after `o2c-database.sql`; the O2C demo and business cases pass with or without it. The first file provides the current `public.customer`, `public.employee`, `public.supplier`, and `public.item` tables. The O2C prototype adds the `sales` and `inventory` schemas. The demo verifies the full flow and rolls back its records. Run `o2c-business-cases.sql` once to preserve the example set.

| Physical object | Purpose and constraints |
| --- | --- |
| `sales.sales_order` | Holds the customer, author, date, and currency. A draft can be confirmed after it has at least one line. |
| `sales.sales_order_line` | Stores the sellable item, quantity, and agreed price. Lines become fixed once the order is confirmed. |
| `inventory.stock_location` | Identifies a store or warehouse by its unique location code. |
| `inventory.goods_receipt` and `inventory.goods_receipt_line` | Capture the supplier, location, business date, receiving employee, and quantities. Each line posts one inbound movement. |
| `inventory.inventory_movement` | Records a stock receipt or a sales issue. Sales issues reference the matching order line and item. When P2M is installed it also records production issues and receipts, each linked to its source document. |
| `inventory.stock_key` | Serializes postings for the same item at the same location. |
| `inventory.stock_balance` | Read-only view of inbound less outbound movements per location and item, signed by `inventory.signed_quantity`. Any outbound movement is rejected if it would make any date's ending stock negative. |
| `sales.customer_invoice` | Stores one invoice per fully issued order. The total is the sum of the rounded line amounts. |
| `sales.customer_payment` | Records full or partial payments in the order currency. The prototype rejects payments over the open balance. |
| `sales.customer_invoice_balance` | Shows the billed amount, total paid, and balance due. |

The prototype uses `public.item` from `db_init.sql` and `inventory.stock_location` as the shared identifiers. The goods receipt is a proposed interface for the P2P module. Mapping the receipt line to Ziyad's purchase-order line and agreeing on the final master schema still require the team's design. Returns, credits, tax, and discounts remain open design decisions.

## Business Rule Examples

Run `o2c-business-cases.sql` once after the prototype in a dedicated test database. It keeps the valid rows and runs rejected operations inside isolated checks. There are 10 orders, 5 invoices, and 6 payments in the example set.

| Order | What the example demonstrates |
| --- | --- |
| `O2C-EX-01` and `O2C-EX-02` | A draft may have zero or more lines. An empty draft fails confirmation. |
| `O2C-EX-03` and `O2C-EX-04` | A confirmed order may await shipment or be partially issued. Partial issue does not yet permit invoicing. |
| `O2C-EX-10` | A fully issued order may await invoicing. The last available unit can be issued and leaves zero stock at that location. |
| `O2C-EX-05` | A fully issued order may have an unpaid invoice with the entire amount outstanding. |
| `O2C-EX-06` | One order line may be issued from two locations. A free line contributes zero to the invoice. Two partial payments leave a balance of 3,500 TRY. |
| `O2C-EX-07` and `O2C-EX-08` | An individual customer buys from stock originally posted by a goods receipt. Sales, stock, and finance use separate employees. An invoice can be due and paid on its issue date, and another invoice can be settled with two payments in EUR. |
| `O2C-EX-09` | A fractional quantity of 0.001 metre and a 0.01 TRY invoice and payment are accepted. |

The rejected cases cover direct balance edits, receipts without a source line, duplicate receipts, stock issues before the corresponding receipt, stock issues that make a later balance negative, order confirmation and immutability, invalid line values and products, invoice timing and duplication, payment dates and amounts, and changes to posted records. An overpayment of 0.01 above the remaining balance is rejected.

## P2M Integration

`p2m-database.sql` installs after this prototype in the same database. It uses `public.*` masters, plans against `sales.sales_order_line` (same item, confirmed order), and adds the `PROD_ISSUE` and `PROD_RECEIPT` movement types with their source columns to `inventory.inventory_movement`. The integrity rules proposed earlier as `p2m-integrity-guards.sql` are built into `p2m-database.sql`: issues are capped at the required component quantity and receipts at the planned quantity. `p2m-business-cases.sql` checks the P2M rules and shows a manufactured table being shipped, invoiced and paid through O2C. See `p2m-logical-model.md` and `p2m-data-dictionary.md`.

## Individual O2C Review

| Deliverable | Review evidence |
| --- | --- |
| Activity Set 1 | The submitted `elemental_erp_activity_set_1.sql` runs in a separate database and creates five standalone tables with five records each. |
| Logical and physical model | This document, `o2c-er-diagram.svg`, and `o2c-database.sql` describe the O2C tables and the prototype's shared inventory links. |
| End-to-end demo | `o2c-demo.sql` creates a new customer, posts a receipt, confirms and ships a sales order, invoices the sale, and settles the balance. Demo rows roll back at the end. |
| Example data and integrity tests | `o2c-business-cases.sql` preserves 10 orders, 5 invoices, and 6 payments and checks 36 rejected operations. |
| Data dictionary | `o2c-data-dictionary.md` describes 121 fields in 16 tables and views, including baseline master data. |

Keep the proposal for shared item, stock location, and employee keys on the team meeting agenda. Review the purchase-order line to goods-receipt line and H2R assignment links with the group before integrating the cycles. The individual O2C prototype uses the current baseline while those decisions are pending.
