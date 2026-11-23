CREATE TABLE employee (
    employee_id INTEGER PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20),
    job_title VARCHAR(100),
    hire_date DATE,
    salary NUMERIC(10,2)
);
INSERT INTO employee
(employee_id, first_name, last_name, email, phone, job_title, hire_date, salary)
VALUES
(1, 'Ahmet', 'Yilmaz', 'ahmet.yilmaz@company.com', '5551001001', 'Production Manager', '2021-03-15', 65000.00),
(2, 'Elif', 'Kaya', 'elif.kaya@company.com', '5551001002', 'Sales Specialist', '2022-06-01', 48000.00),
(3, 'Mehmet', 'Demir', 'mehmet.demir@company.com', '5551001003', 'Procurement Specialist', '2020-11-10', 52000.00),
(4, 'Zeynep', 'Aydin', 'zeynep.aydin@company.com', '5551001004', 'HR Specialist', '2023-02-20', 47000.00),
(5, 'Can', 'Arslan', 'can.arslan@company.com', '5551001005', 'Warehouse Specialist', '2024-01-08', 45000.00);
SELECT * FROM employee;
CREATE TABLE department (
    department_id INTEGER PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    location VARCHAR(100),
    phone_extension VARCHAR(10),
    budget NUMERIC(12,2)
);
INSERT INTO department
(department_id, department_name, location, phone_extension, budget)
VALUES
(1, 'Production', 'Factory Floor', '101', 500000.00),
(2, 'Sales', 'Main Office', '102', 200000.00),
(3, 'Procurement', 'Main Office', '103', 250000.00),
(4, 'Human Resources', 'Main Office', '104', 150000.00),
(5, 'Warehouse', 'Warehouse Building', '105', 300000.00);
SELECT * FROM department;
CREATE TABLE customer (
    customer_id INTEGER PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    customer_type VARCHAR(30),
    email VARCHAR(100),
    phone VARCHAR(20),
    city VARCHAR(50),
    country VARCHAR(50)
);
INSERT INTO customer
(customer_id, customer_name, customer_type, email, phone, city, country)
VALUES
(1, 'Modern Home Design', 'Business', 'info@modernhome.com', '5552001001', 'Istanbul', 'Turkey'),
(2, 'Ayse Yildiz', 'Individual', 'ayse@example.com', '5552001002', 'Istanbul', 'Turkey'),
(3, 'Urban Living', 'Business', 'orders@urbanliving.com', '5552001003', 'Ankara', 'Turkey'),
(4, 'Kerem Acar', 'Individual', 'kerem@example.com', '5552001004', 'Izmir', 'Turkey'),
(5, 'Interior Concept', 'Business', 'sales@interiorconcept.com', '5552001005', 'Bursa', 'Turkey');
SELECT * FROM customer;
CREATE TABLE supplier (
    supplier_id INTEGER PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_name VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    city VARCHAR(50),
    country VARCHAR(50)
);
INSERT INTO supplier
(supplier_id, supplier_name, contact_name, email, phone, city, country)
VALUES
(1, 'Anadolu Timber', 'Ali Kaya', 'sales@anadolutimber.com', '5553001001', 'Bursa', 'Turkey'),
(2, 'Metal Works Ltd.', 'Ece Demir', 'info@metalworks.com', '5553001002', 'Istanbul', 'Turkey'),
(3, 'Premium Fabrics', 'Mert Aydin', 'orders@premiumfabrics.com', '5553001003', 'Izmir', 'Turkey'),
(4, 'Furniture Hardware Co.', 'Selin Arslan', 'sales@furniturehardware.com', '5553001004', 'Istanbul', 'Turkey'),
(5, 'Eco Paint Supplies', 'Burak Celik', 'info@ecopaint.com', '5553001005', 'Ankara', 'Turkey');
SELECT * FROM supplier;
CREATE TABLE item (
    item_id INTEGER PRIMARY KEY,
    item_code VARCHAR(30) NOT NULL UNIQUE,
    item_name VARCHAR(100) NOT NULL,
    item_description VARCHAR(255),
    item_category VARCHAR(50),
    unit_of_measure VARCHAR(20),
    purchase_price NUMERIC(10,2),
    sales_price NUMERIC(10,2),
    is_purchasable BOOLEAN NOT NULL,
    is_manufacturable BOOLEAN NOT NULL,
    is_consumable BOOLEAN NOT NULL,
    is_sellable BOOLEAN NOT NULL
);
INSERT INTO item
(item_id, item_code, item_name, item_description, item_category,
 unit_of_measure, purchase_price, sales_price,
 is_purchasable, is_manufacturable, is_consumable, is_sellable)
VALUES
(1, 'RAW-OAK-001', 'Oak Wood Panel',
 'Oak wood panel used in furniture production',
 'Raw Material', 'piece', 1200.00, NULL,
 TRUE, FALSE, TRUE, FALSE),

(2, 'COMP-LEG-001', 'Wooden Table Leg',
 'Wooden leg component used in table production',
 'Component', 'piece', 250.00, 400.00,
 TRUE, TRUE, TRUE, TRUE),

(3, 'RAW-FAB-001', 'Upholstery Fabric',
 'Fabric used for upholstered furniture',
 'Raw Material', 'meter', 180.00, NULL,
 TRUE, FALSE, TRUE, FALSE),

(4, 'FG-TABLE-001', 'Oak Dining Table',
 'Finished make-to-order oak dining table',
 'Finished Good', 'piece', NULL, 12500.00,
 FALSE, TRUE, FALSE, TRUE),

(5, 'FG-CHAIR-001', 'Dining Chair',
 'Finished wooden dining chair',
 'Finished Good', 'piece', NULL, 3500.00,
 FALSE, TRUE, FALSE, TRUE);
 SELECT * FROM item;