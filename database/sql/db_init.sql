CREATE TABLE department (
    department_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_code VARCHAR(10)  NOT NULL UNIQUE,
    department_name VARCHAR(100) NOT NULL,
    description     TEXT,
    location        VARCHAR(100),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

INSERT INTO department (department_code, department_name, description, location) VALUES
('URT', 'Üretim',          'Mobilyaların kesim, montaj, zımpara ve boya işlemlerinin yapıldığı birim.', 'Atölye Binası'),
('SAT', 'Satış',           'Müşteri siparişlerinin alınması ve teklif hazırlanması.',                    'İdari Bina'),
('STN', 'Satın Alma',      'Hammadde ve bileşenlerin tedarikçilerden temin edilmesi.',                   'İdari Bina'),
('MUH', 'Muhasebe',        'Fatura, tahsilat, ödeme ve maliyet muhasebesi işlemleri.',                   'İdari Bina'),
('KKT', 'Kalite Kontrol',  'Gelen malzeme ve mamul ürünlerin kalite denetimi.',                          'Atölye Binası'),
('DEP', 'Depo ve Sevkiyat','Hammadde, yarı mamul ve mamul stoklarının yönetimi ve sevkiyat.',            'Depo Binası');

CREATE TABLE employee (
    employee_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_no   VARCHAR(10)  NOT NULL UNIQUE,   -- sicil numarası
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    job_title     VARCHAR(100) NOT NULL,
    email         VARCHAR(120) UNIQUE,
    phone         VARCHAR(20),
    hire_date     DATE         NOT NULL,
    monthly_salary NUMERIC(12,2) CHECK (monthly_salary >= 0),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE
);

INSERT INTO employee (employee_no, first_name, last_name, job_title, email, phone, hire_date, monthly_salary) VALUES
('E-0001', 'Mehmet',  'Yılmaz',  'Genel Müdür',            'mehmet.yilmaz@anadolumobilya.com.tr',  '0532 111 22 33', '2012-03-01', 95000.00),
('E-0002', 'Ayşe',    'Demir',   'Satış Müdürü',           'ayse.demir@anadolumobilya.com.tr',     '0533 222 33 44', '2016-09-15', 62000.00),
('E-0003', 'Mustafa', 'Çelik',   'Üretim Şefi',            'mustafa.celik@anadolumobilya.com.tr',  '0535 333 44 55', '2014-05-20', 58000.00),
('E-0004', 'Fatma',   'Şahin',   'Satın Alma Uzmanı',      'fatma.sahin@anadolumobilya.com.tr',    '0536 444 55 66', '2019-02-11', 45000.00),
('E-0005', 'Hasan',   'Öztürk',  'Marangoz Ustası',        'hasan.ozturk@anadolumobilya.com.tr',   '0537 555 66 77', '2015-11-02', 40000.00),
('E-0006', 'Zeynep',  'Kaya',    'Muhasebe Uzmanı',        'zeynep.kaya@anadolumobilya.com.tr',    '0538 666 77 88', '2020-06-08', 43000.00),
('E-0007', 'İbrahim', 'Aydın',   'Kalite Kontrol Uzmanı',  'ibrahim.aydin@anadolumobilya.com.tr',  '0539 777 88 99', '2021-01-18', 41000.00);

CREATE TABLE customer (
    customer_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code  VARCHAR(10)  NOT NULL UNIQUE,
    customer_name  VARCHAR(150) NOT NULL,          -- firma unvanı veya ad soyad
    customer_type  VARCHAR(12)  NOT NULL CHECK (customer_type IN ('BIREYSEL', 'KURUMSAL')),
    tax_office     VARCHAR(60),                    -- vergi dairesi
    tax_number     VARCHAR(11),                    -- VKN (10) veya TCKN (11)
    contact_person VARCHAR(100),
    email          VARCHAR(120),
    phone          VARCHAR(20),
    address        VARCHAR(250),
    city           VARCHAR(50),
    created_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO customer (customer_code, customer_name, customer_type, tax_office, tax_number, contact_person, email, phone, address, city, created_date) VALUES
('M-0001', 'Güneş Otel İşletmeleri A.Ş.',      'KURUMSAL', 'Muratpaşa',    '1234567890', 'Serkan Arslan',  'satinalma@gunesotel.com.tr',   '0242 311 40 50', 'Lara Caddesi No: 45',            'Antalya',  '2023-02-10'),
('M-0002', 'Boğaziçi Kafe ve Restoran Ltd. Şti.','KURUMSAL','Beşiktaş',     '2345678901', 'Elif Koç',       'info@bogazicikafe.com.tr',     '0212 258 61 72', 'Çırağan Caddesi No: 12',         'İstanbul', '2023-05-22'),
('M-0003', 'Ankara Eğitim Kurumları A.Ş.',      'KURUMSAL', 'Çankaya',      '3456789012', 'Burak Tunç',     'idari@ankaraegitim.com.tr',    '0312 425 33 18', 'Tunalı Hilmi Caddesi No: 88',    'Ankara',   '2024-01-15'),
('M-0004', 'Ali Veli Kara',                      'BIREYSEL', 'Karşıyaka',    '12345678901','Ali Veli Kara',  'aliveli.kara@example.com',     '0541 234 56 78', 'Atatürk Mahallesi 1203. Sokak No: 7','İzmir', '2024-03-04'),
('M-0005', 'Selin Yıldız',                       'BIREYSEL', 'Nilüfer',      '23456789012','Selin Yıldız',   'selin.yildiz@example.com',     '0542 345 67 89', 'Özlüce Mahallesi Gül Sokak No: 3','Bursa',   '2024-06-19'),
('M-0006', 'Karadeniz Ofis Çözümleri Ltd. Şti.','KURUMSAL', 'Ortahisar',    '4567890123', 'Murat Başaran',  'murat@karadenizofis.com.tr',   '0462 322 90 14', 'Kalkınma Mahallesi Sanayi Sokak No: 21','Trabzon','2024-09-30');

CREATE TABLE supplier (
    supplier_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_code  VARCHAR(10)  NOT NULL UNIQUE,
    supplier_name  VARCHAR(150) NOT NULL,
    tax_office     VARCHAR(60),
    tax_number     VARCHAR(11),
    contact_person VARCHAR(100),
    email          VARCHAR(120),
    phone          VARCHAR(20),
    address        VARCHAR(250),
    city           VARCHAR(50),
    payment_terms_days INTEGER CHECK (payment_terms_days >= 0),  -- vade(gün)
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO supplier (supplier_code, supplier_name, tax_office, tax_number, contact_person, email, phone, address, city, payment_terms_days) VALUES
('T-0001', 'Kuzey Orman Ürünleri San. ve Tic. A.Ş.', 'Kastamonu',   '5678901234', 'Recep Aksoy',   'satis@kuzeyorman.com.tr',    '0366 214 55 60', 'Organize Sanayi Bölgesi 3. Cadde No: 5', 'Kastamonu', 45),
('T-0002', 'Anadolu Levha ve Kaplama Ltd. Şti.',      'Kayseri',     '6789012345', 'Gül Erdoğan',   'siparis@anadolulevha.com.tr','0352 336 78 90', 'Hacılar Sanayi Sitesi B Blok No: 14',    'Kayseri',  30),
('T-0003', 'Ege Hırdavat ve Bağlantı Elemanları A.Ş.','Bornova',     '7890123456', 'Tolga Karaca',  'tolga@egehirdavat.com.tr',   '0232 462 11 25', 'Işıkkent Sanayi Caddesi No: 62',         'İzmir',    30),
('T-0004', 'Marmara Boya ve Kimya San. Tic. Ltd. Şti.','Gebze',      '8901234567', 'Nur Özkan',     'nur.ozkan@marmaraboya.com.tr','0262 644 20 37','Gebze Organize Sanayi Bölgesi 7. Sokak No: 9','Kocaeli', 60),
('T-0005', 'Bursa Döşemelik Kumaş ve Sünger A.Ş.',    'Osmangazi',   '9012345678', 'Cemal Polat',   'cemal@bursakumas.com.tr',    '0224 261 47 83', 'Merinos Sanayi Bölgesi Tekstil Sokak No: 18','Bursa',   45),
('T-0006', 'Doğu Metal Mobilya Aksesuarları Ltd. Şti.','Ostim',      '0123456789', 'Sibel Yurt',    'sibel@dogumetal.com.tr',     '0312 354 92 06', 'Ostim Sanayi Sitesi 1234. Sokak No: 31', 'Ankara',   30);

CREATE TABLE item (
    item_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_code         VARCHAR(20)  NOT NULL UNIQUE,   -- stok kodu
    item_name         VARCHAR(150) NOT NULL,
    description       TEXT,
    item_category     VARCHAR(30)  NOT NULL
                      CHECK (item_category IN ('HAMMADDE', 'YARI_MAMUL', 'BILESEN', 'SARF_MALZEME', 'MAMUL')),
    unit_of_measure   VARCHAR(10)  NOT NULL
                      CHECK (unit_of_measure IN ('ADET', 'KG', 'LT', 'M', 'M2', 'M3', 'PAKET', 'TAKIM')),

    -- roles (not mutually exclusive)
    is_purchasable    BOOLEAN NOT NULL DEFAULT FALSE,  -- satın alınabilir
    is_manufacturable BOOLEAN NOT NULL DEFAULT FALSE,  -- üretilebilir
    is_consumable     BOOLEAN NOT NULL DEFAULT FALSE,  -- üretimde tüketilir
    is_sellable       BOOLEAN NOT NULL DEFAULT FALSE,  -- satılabilir

    is_serialized     BOOLEAN NOT NULL DEFAULT FALSE,  -- birimler tek tek izlenir mi
    standard_cost     NUMERIC(12,2) CHECK (standard_cost >= 0),
    list_price        NUMERIC(12,2) CHECK (list_price >= 0),
    reorder_level     NUMERIC(12,3) CHECK (reorder_level >= 0),
    lead_time_days    INTEGER       CHECK (lead_time_days >= 0),
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,

    -- an item must play at least one role
    CONSTRAINT item_has_role CHECK (is_purchasable OR is_manufacturable OR is_consumable OR is_sellable),
    -- a sellable item must have a list price
    CONSTRAINT sellable_has_price CHECK (NOT is_sellable OR list_price IS NOT NULL)
);

INSERT INTO item
(item_code, item_name, description, item_category, unit_of_measure,
 is_purchasable, is_manufacturable, is_consumable, is_sellable, is_serialized,
 standard_cost, list_price, reorder_level, lead_time_days) VALUES

('HM-0001', 'Masif Meşe Tahta 30 mm',
 'Kurutulmuş, kalibre edilmiş masif meşe tahta; masa ve sandalye iskeleti üretiminde kullanılır.',
 'HAMMADDE', 'M3', TRUE,  FALSE, TRUE,  FALSE, FALSE, 38500.00, NULL,    5.000, 14),

('HM-0002', 'MDF Levha 18 mm (210x280 cm)',
 'Yüksek yoğunluklu lif levha; dolap gövdesi ve raf yapımında kullanılır.',
 'HAMMADDE', 'ADET', TRUE, FALSE, TRUE,  TRUE,  FALSE, 1250.00,  1650.00, 20.000, 7),

('BL-0001', 'Çekmece Kulbu - Paslanmaz Çelik 128 mm',
 'Paslanmaz çelik çekmece ve kapak kulbu; montaj sırasında takılır, yedek parça olarak da satılır.',
 'BILESEN', 'ADET', TRUE, FALSE, TRUE,  TRUE,  FALSE, 18.50,    35.00,   200.000, 10),

('SM-0001', 'Ahşap Vidası 4x40 mm (200''lü paket)',
 'Çinko kaplama havşa başlı ahşap vidası; montajda tüketilir.',
 'SARF_MALZEME', 'PAKET', TRUE, FALSE, TRUE, FALSE, FALSE, 95.00, NULL,  50.000, 5),

('SM-0002', 'Su Bazlı Mat Vernik',
 'Mobilya yüzeyleri için çevre dostu, kokusuz, su bazlı mat vernik.',
 'SARF_MALZEME', 'LT', TRUE, FALSE, TRUE, FALSE, FALSE, 210.00, NULL,    40.000, 12),

-- Üretilen yarı mamul
('YM-0001', 'Masif Meşe Masa Ayağı 72 cm',
 'İşlenmiş ve zımparalanmış meşe masa ayağı; masa montajında kullanılır, yedek parça olarak da satılır.',
 'YARI_MAMUL', 'ADET', FALSE, TRUE, TRUE, TRUE,  FALSE, 145.00,  290.00,  40.000, 3),

-- Hem satın alınan hem üretilen bileşen
('BL-0002', 'Döşemelik Sandalye Oturağı',
 'Sünger dolgulu, kumaş kaplı sandalye oturağı; bazen dışarıdan hazır alınır, bazen atölyede üretilir.',
 'BILESEN', 'ADET', TRUE, TRUE, TRUE,  FALSE, FALSE, 120.00,  NULL,    60.000, 4),

-- Sipariş üzerine üretilen mamul
('MM-0001', 'Meşe Yemek Masası 180x90 cm',
 'Masif meşe yemek masası; sipariş üzerine ölçü ve renk seçenekleriyle üretilir.',
 'MAMUL', 'ADET', FALSE, TRUE, FALSE, TRUE, TRUE,  4200.00,  9800.00,  0.000, 21),

('MM-0002', 'Döşemeli Yemek Sandalyesi Model S-100',
 'Meşe iskeletli, kumaş döşemeli yemek sandalyesi.',
 'MAMUL', 'ADET', FALSE, TRUE, FALSE, TRUE, FALSE, 950.00,   2250.00,  0.000, 14),

('MM-0003', 'Çalışma Masası 140x70 cm',
 'MDF gövdeli, 2 çekmeceli ofis çalışma masası.',
 'MAMUL', 'ADET', FALSE, TRUE, FALSE, TRUE, TRUE,  2100.00,  4950.00,  0.000, 10);
