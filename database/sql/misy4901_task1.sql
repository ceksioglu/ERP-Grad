-- 1. Create Tables

CREATE TABLE employee (
    employee_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    hire_date DATE
);

CREATE TABLE department (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    location VARCHAR(100)
);

CREATE TABLE customer (
    customer_id SERIAL PRIMARY KEY,
    company_name VARCHAR(100) NOT NULL,
    contact_name VARCHAR(100),
    phone VARCHAR(20)
);

CREATE TABLE supplier (
    supplier_id SERIAL PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact_email VARCHAR(100),
    phone VARCHAR(20)
);

CREATE TABLE item (
    item_id SERIAL PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL,
    is_purchased BOOLEAN DEFAULT FALSE,
    is_manufactured BOOLEAN DEFAULT FALSE,
    is_consumed BOOLEAN DEFAULT FALSE,
    is_sold BOOLEAN DEFAULT FALSE
);

-- 2. Insert at least 5 records into each table

INSERT INTO employee (first_name, last_name, email, hire_date) VALUES
('John', 'Doe', 'john.doe@example.com', '2023-01-15'),
('Jane', 'Smith', 'jane.smith@example.com', '2023-02-01'),
('Ali', 'Yilmaz', 'ali.yilmaz@example.com', '2023-03-10'),
('Sara', 'Ahmed', 'sara.ahmed@example.com', '2023-04-05'),
('Michael', 'Brown', 'michael.b@example.com', '2023-05-12');

INSERT INTO department (department_name, location) VALUES
('Production', 'Building A'),
('Sales', 'Building B'),
('HR', 'Building B'),
('Purchasing', 'Building A'),
('Finance', 'Building C');

INSERT INTO customer (company_name, contact_name, phone) VALUES
('Modern Home Design', 'Alice Green', '+1234567890'),
('Office Comfort Ltd.', 'Bob White', '+1234567891'),
('Decor Plus', 'Charlie Black', '+1234567892'),
('Urban Living', 'Diana Prince', '+1234567893'),
('Elite Furnishings', 'Evan Wright', '+1234567894');

INSERT INTO supplier (supplier_name, contact_email, phone) VALUES
('Timber Supplies Co.', 'info@timbersupplies.com', '+9876543210'),
('Hardware Express', 'sales@hardwareexpress.com', '+9876543211'),
('Paint & Varnish Ltd.', 'contact@paintvarnish.com', '+9876543212'),
('Fabric Wholesale', 'support@fabricwholesale.com', '+9876543213'),
('Global Wood Tools', 'orders@globalwood.com', '+9876543214');

INSERT INTO item (item_name, is_purchased, is_manufactured, is_consumed, is_sold) VALUES
('Wood Plank (Oak)', TRUE, FALSE, TRUE, FALSE),
('Dining Chair', FALSE, TRUE, FALSE, TRUE),
('Screws (Pack of 100)', TRUE, FALSE, TRUE, FALSE),
('Wood Varnish 5L', TRUE, FALSE, TRUE, FALSE),
('Custom Wooden Table', FALSE, TRUE, FALSE, TRUE);