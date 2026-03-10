/* =========================================================
   IMAGINARY BANK ANALYTICS DATASET
   Author : Saba Chkhaidze

   Schema : Single fact table, star schema
   Grain  : One row = one month-end financial entry per
            channel x segment x product x currency x scenario x budget_item

   Scenarios:
     1  Actual               2022-2025, filter year via dim_date
     2  Budget_2023          Original approved budget FY2023
     3  Budget_2024          Original approved budget FY2024
     4  Budget_2025          Original approved budget FY2025
     5  Budget_2026_TopDown  Management stretch targets FY2026
     6  Budget_2026_BottomUp Consolidated channel submissions FY2026
     7  Forecast_2025_Q3     Rolling forecast after Q3 2025 close
     8  Forecast_2026_Q1     Rolling forecast after Q1 2026 close

   Currencies (EUR base = 1.000000):
     1  EUR  base currency
     2  USD  USD/EUR historical rates
     3  GBP  GBP/EUR historical rates

   FX rates (source: exchange-rates.org, EUR base):
   Year   USD/EUR avg   USD/EUR range     GBP/EUR avg   GBP/EUR range
   2022   1.0530        0.9900 - 1.1600   0.8530        0.8300 - 0.8900
   2023   1.0820        1.0500 - 1.1300   0.8690        0.8500 - 0.8900
   2024   1.0820        1.0600 - 1.1200   0.8550        0.8300 - 0.8700
   2025   1.0500        1.0200 - 1.0900   0.8400        0.8200 - 0.8700
   2026   1.0600        1.0300 - 1.0900   0.8450        0.8300 - 0.8700

   Amount derivation:
     dim_currency holds one authoritative eom_rate and daily_avg_rate
     per currency per month-end date.
     fact_financial_data joins dim_currency via rate_id = CONCAT(date_id, currency_id).
     amount_eur        = base formula (EUR equivalent)
     amount_nominal    = amount_eur * eom_rate
     daily_avg_eur     = amount_eur * daily adjustment factor
     daily_avg_nominal = daily_avg_eur * daily_avg_rate
     EUR rows          : both rates = 1.000000, nominal = eur exactly

   Channel multipliers : Flagship=3.0, Branch=2.0, Digital=1.5, Remote=0.8, BU=2.5
   Segment multipliers : Corporate=4.0, Private=3.0, FI=2.5, SME=2.0, Retail=1.0
   Currency weights    : EUR=1.00, USD=0.40, GBP=0.25
   Seasonality actuals : Q1=0.90, Q2=0.95, Q3=1.00, Q4=1.15
   Seasonality budgets : Q1=0.92, Q2=0.96, Q3=1.00, Q4=1.12
   ========================================================= */

-------------------------------------------------------------
-- 1. CREATE DATABASE
-------------------------------------------------------------
USE master;
GO

IF DB_ID('ImaginaryBank') IS NOT NULL
BEGIN
    ALTER DATABASE ImaginaryBank SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ImaginaryBank;
END
GO

CREATE DATABASE ImaginaryBank;
GO
USE ImaginaryBank;
GO

-- =========================================================
-- 2. dim_date  (2022-01-01 to 2026-12-31, date_id = YYYYMMDD)
-- =========================================================
CREATE TABLE dim_date (
    date_id          INT         NOT NULL PRIMARY KEY,
    full_date        DATE        NOT NULL,
    year             INT         NOT NULL,
    quarter          INT         NOT NULL,
    quarter_name     VARCHAR(6)  NOT NULL,
    month            INT         NOT NULL,
    month_name       VARCHAR(12) NOT NULL,
    month_name_short VARCHAR(3)  NOT NULL,
    day              INT         NOT NULL,
    is_month_end     BIT         NOT NULL DEFAULT 0,
    days_in_month    TINYINT     NOT NULL,
    days_in_year     SMALLINT    NOT NULL
);
GO

DECLARE @d   DATE = '2022-01-01';
DECLARE @end DATE = '2026-12-31';
WHILE @d <= @end
BEGIN
    INSERT INTO dim_date VALUES (
        CAST(FORMAT(@d,'yyyyMMdd') AS INT),
        @d,
        YEAR(@d),
        DATEPART(QUARTER,@d),
        'Q' + CAST(DATEPART(QUARTER,@d) AS VARCHAR),
        MONTH(@d),
        DATENAME(MONTH,@d),
        LEFT(DATENAME(MONTH,@d),3),
        DAY(@d),
        CASE WHEN @d = EOMONTH(@d) THEN 1 ELSE 0 END,
        DAY(EOMONTH(@d)),
        CASE WHEN YEAR(@d) % 400 = 0 OR (YEAR(@d) % 4 = 0 AND YEAR(@d) % 100 != 0) THEN 366 ELSE 365 END
    );
    SET @d = DATEADD(DAY,1,@d);
END
GO

-- =========================================================
-- 3. dim_channel
-- Non-physical channels use 'Other' for country and region.
-- =========================================================
CREATE TABLE dim_channel (
    channel_id   INT          NOT NULL PRIMARY KEY,
    channel_name VARCHAR(100) NOT NULL,
    channel_type VARCHAR(30)  NOT NULL,  -- Branch / Digital / Remote / Business Unit
    country      VARCHAR(50)  NOT NULL,
    region       VARCHAR(50)  NOT NULL,
    opened_date  DATE,
    is_active    BIT          NOT NULL DEFAULT 1
);

INSERT INTO dim_channel VALUES
( 1,'Paris Flagship',        'Branch',       'France',      'Western Europe', '2018-03-01',1),
( 2,'Berlin Main',           'Branch',       'Germany',     'Central Europe', '2018-06-01',1),
( 3,'Amsterdam Branch',      'Branch',       'Netherlands', 'Western Europe', '2019-04-01',1),
( 4,'Madrid Branch',         'Branch',       'Spain',       'Southern Europe','2019-09-01',1),
( 5,'Milan Flagship',        'Branch',       'Italy',       'Southern Europe','2018-03-01',1),
( 6,'Warsaw Branch',         'Branch',       'Poland',      'Eastern Europe', '2020-01-01',1),
( 7,'Vienna Branch',         'Branch',       'Austria',     'Central Europe', '2020-06-01',1),
( 8,'Zurich Branch',         'Branch',       'Switzerland', 'Central Europe', '2021-03-01',1),
( 9,'Stockholm Branch',      'Branch',       'Sweden',      'Northern Europe','2021-09-01',1),
(10,'Mobile Banking',        'Digital',      'Other',       'Other',          '2019-01-01',1),
(11,'Internet Banking',      'Digital',      'Other',       'Other',          '2018-01-01',1),
(12,'Call Center',           'Remote',       'Other',       'Other',          '2018-01-01',1),
(13,'Corporate Banking Unit','Business Unit','Other',       'Other',          '2018-01-01',1),
(14,'Private Banking Unit',  'Business Unit','Other',       'Other',          '2018-01-01',1);
GO

-- =========================================================
-- 4. dim_segment
-- =========================================================
CREATE TABLE dim_segment (
    segment_id   INT          NOT NULL PRIMARY KEY,
    segment_name VARCHAR(30)  NOT NULL,
    description  VARCHAR(200)
);

INSERT INTO dim_segment VALUES
(1,'Retail',                'Individual customers, personal banking'),
(2,'SME',                   'Small and medium enterprises'),
(3,'Corporate',             'Large corporate clients'),
(4,'Private Banking',       'High net worth individuals'),
(5,'Financial Institutions','Banks and financial entities');
GO

-- =========================================================
-- 5. dim_product
-- =========================================================
CREATE TABLE dim_product (
    product_id          INT          NOT NULL PRIMARY KEY,
    product_name        VARCHAR(100) NOT NULL,
    product_category    VARCHAR(50)  NOT NULL,
    product_subcategory VARCHAR(50),
    is_active           BIT          NOT NULL DEFAULT 1
);

INSERT INTO dim_product VALUES
( 1,'Consumer Loan',       'Loan',   'Unsecured', 1),
( 2,'Mortgage',            'Loan',   'Secured',   1),
( 3,'Auto Loan',           'Loan',   'Secured',   1),
( 4,'Business Loan',       'Loan',   'Unsecured', 1),
( 5,'SME Credit Line',     'Loan',   'Revolving', 1),
( 6,'Corporate Loan',      'Loan',   'Secured',   1),
( 7,'Credit Card Classic', 'Card',   'Credit',    1),
( 8,'Credit Card Premium', 'Card',   'Credit',    1),
( 9,'Debit Card',          'Card',   'Debit',     1),
(10,'Current Account EUR', 'Deposit','Current',   1),
(11,'Current Account USD', 'Deposit','Current',   1),
(12,'Current Account GBP', 'Deposit','Current',   1),
(13,'Savings Account',     'Deposit','Savings',   1),
(14,'Term Deposit EUR',    'Deposit','Term',      1),
(15,'Term Deposit USD',    'Deposit','Term',      1),
(16,'Internet Banking',    'Service','Digital',   1),
(17,'Mobile Banking',      'Service','Digital',   1);
GO

-- =========================================================
-- 6. dim_currency
-- One row per currency per month-end date.
-- EUR is base currency (rate = 1.000000).
-- rate_id = CONCAT(date_id, currency_id) - joins to fact table.
-- eom_rate      = end-of-month spot rate vs EUR
-- daily_avg_rate = monthly daily average rate vs EUR
-- =========================================================
CREATE TABLE dim_currency (
    rate_id         VARCHAR(20)   NOT NULL PRIMARY KEY,
    date_id         INT           NOT NULL REFERENCES dim_date(date_id),
    currency_id     INT           NOT NULL,
    currency_code   CHAR(3)       NOT NULL,
    currency_name   VARCHAR(50)   NOT NULL,
    currency_symbol VARCHAR(5)    NOT NULL,
    eom_rate        DECIMAL(10,6) NOT NULL,
    daily_avg_rate  DECIMAL(10,6) NOT NULL
);
GO

-- EUR rows: both rates = 1.000000
INSERT INTO dim_currency
    (rate_id, date_id, currency_id, currency_code, currency_name, currency_symbol, eom_rate, daily_avg_rate)
SELECT
    CONCAT(d.date_id, 1), d.date_id,
    1, 'EUR', 'Euro', '€', 1.000000, 1.000000
FROM dim_date d WHERE d.is_month_end = 1;
GO

-- USD rows: independently randomised eom and daily_avg within annual ranges
INSERT INTO dim_currency
    (rate_id, date_id, currency_id, currency_code, currency_name, currency_symbol, eom_rate, daily_avg_rate)
SELECT
    CONCAT(d.date_id, 2), d.date_id,
    2, 'USD', 'US Dollar', '$',
    CAST(CASE d.year
        WHEN 2022 THEN 1.0530 + (ABS(CHECKSUM(NEWID())) % 1700) / 10000.0 - 0.0850
        WHEN 2023 THEN 1.0820 + (ABS(CHECKSUM(NEWID())) %  800) / 10000.0 - 0.0400
        WHEN 2024 THEN 1.0820 + (ABS(CHECKSUM(NEWID())) %  600) / 10000.0 - 0.0300
        WHEN 2025 THEN 1.0500 + (ABS(CHECKSUM(NEWID())) %  700) / 10000.0 - 0.0350
        WHEN 2026 THEN 1.0600 + (ABS(CHECKSUM(NEWID())) %  600) / 10000.0 - 0.0300
    END AS DECIMAL(10,6)),
    CAST(CASE d.year
        WHEN 2022 THEN 1.0530 + (ABS(CHECKSUM(NEWID())) % 1700) / 10000.0 - 0.0850
        WHEN 2023 THEN 1.0820 + (ABS(CHECKSUM(NEWID())) %  800) / 10000.0 - 0.0400
        WHEN 2024 THEN 1.0820 + (ABS(CHECKSUM(NEWID())) %  600) / 10000.0 - 0.0300
        WHEN 2025 THEN 1.0500 + (ABS(CHECKSUM(NEWID())) %  700) / 10000.0 - 0.0350
        WHEN 2026 THEN 1.0600 + (ABS(CHECKSUM(NEWID())) %  600) / 10000.0 - 0.0300
    END AS DECIMAL(10,6))
FROM dim_date d WHERE d.is_month_end = 1;
GO

-- GBP rows: independently randomised eom and daily_avg within annual ranges
INSERT INTO dim_currency
    (rate_id, date_id, currency_id, currency_code, currency_name, currency_symbol, eom_rate, daily_avg_rate)
SELECT
    CONCAT(d.date_id, 3), d.date_id,
    3, 'GBP', 'British Pound', '£',
    CAST(CASE d.year
        WHEN 2022 THEN 0.8530 + (ABS(CHECKSUM(NEWID())) % 600) / 10000.0 - 0.0300
        WHEN 2023 THEN 0.8690 + (ABS(CHECKSUM(NEWID())) % 400) / 10000.0 - 0.0200
        WHEN 2024 THEN 0.8550 + (ABS(CHECKSUM(NEWID())) % 400) / 10000.0 - 0.0200
        WHEN 2025 THEN 0.8400 + (ABS(CHECKSUM(NEWID())) % 500) / 10000.0 - 0.0250
        WHEN 2026 THEN 0.8450 + (ABS(CHECKSUM(NEWID())) % 400) / 10000.0 - 0.0200
    END AS DECIMAL(10,6)),
    CAST(CASE d.year
        WHEN 2022 THEN 0.8530 + (ABS(CHECKSUM(NEWID())) % 600) / 10000.0 - 0.0300
        WHEN 2023 THEN 0.8690 + (ABS(CHECKSUM(NEWID())) % 400) / 10000.0 - 0.0200
        WHEN 2024 THEN 0.8550 + (ABS(CHECKSUM(NEWID())) % 400) / 10000.0 - 0.0200
        WHEN 2025 THEN 0.8400 + (ABS(CHECKSUM(NEWID())) % 500) / 10000.0 - 0.0250
        WHEN 2026 THEN 0.8450 + (ABS(CHECKSUM(NEWID())) % 400) / 10000.0 - 0.0200
    END AS DECIMAL(10,6))
FROM dim_date d WHERE d.is_month_end = 1;
GO
PRINT 'dim_currency populated';

-- =========================================================
-- 7. dim_scenario
-- =========================================================
CREATE TABLE dim_scenario (
    scenario_id   INT          NOT NULL PRIMARY KEY,
    scenario_name VARCHAR(50)  NOT NULL,
    scenario_type VARCHAR(30)  NOT NULL,  -- Actual / Budget / Forecast
    fiscal_year   INT,
    description   VARCHAR(200)
);

INSERT INTO dim_scenario VALUES
(1,'Actual',               'Actual',  NULL,'Actuals 2022-2025, filter year via dim_date'),
(2,'Budget_2023',          'Budget',  2023,'Original approved budget FY2023'),
(3,'Budget_2024',          'Budget',  2024,'Original approved budget FY2024'),
(4,'Budget_2025',          'Budget',  2025,'Original approved budget FY2025'),
(5,'Budget_2026_TopDown',  'Budget',  2026,'Management stretch targets FY2026'),
(6,'Budget_2026_BottomUp', 'Budget',  2026,'Consolidated channel submissions FY2026'),
(7,'Forecast_2025_Q3',     'Forecast',2025,'Rolling forecast after Q3 2025 close'),
(8,'Forecast_2026_Q1',     'Forecast',2026,'Rolling forecast after Q1 2026 close');
GO

-- =========================================================
-- 8. dim_budget_items  (P&L and Balance Sheet hierarchy)
--    parent_item_id NULL = top-level node
--    is_subtotal    1    = calculated in DAX, no data rows
--    sign_convention     = 1 (positive good), -1 (positive is cost)
-- =========================================================
CREATE TABLE dim_budget_items (
    budget_item_id  INT          NOT NULL PRIMARY KEY,
    item_name       VARCHAR(100) NOT NULL,
    statement_type  VARCHAR(5)   NOT NULL,  -- PL / BS
    category        VARCHAR(50)  NOT NULL,
    subcategory     VARCHAR(50),
    parent_item_id  INT          REFERENCES dim_budget_items(budget_item_id),
    sort_order      INT          NOT NULL,
    is_subtotal     BIT          NOT NULL DEFAULT 0,
    sign_convention INT          NOT NULL DEFAULT 1
);

INSERT INTO dim_budget_items VALUES
-- P&L
( 1,'Net Interest Income',           'PL','Income',  'NII',          NULL, 10,1, 1),
( 2,'Interest Income',               'PL','Income',  'NII',             1, 11,1, 1),
( 3,'Interest Income on Loans',      'PL','Income',  'NII',             2, 12,0, 1),
( 4,'Interest Income on Securities', 'PL','Income',  'NII',             2, 13,0, 1),
( 5,'Interest Income on Placements', 'PL','Income',  'NII',             2, 14,0, 1),
( 6,'Interest Expense',              'PL','Expense', 'NII',             1, 15,1,-1),
( 7,'Interest Expense on Deposits',  'PL','Expense', 'NII',             6, 16,0,-1),
( 8,'Interest Expense on Borrowings','PL','Expense', 'NII',             6, 17,0,-1),
( 9,'Non-Interest Income',           'PL','Income',  'Non-Interest', NULL, 20,1, 1),
(10,'Fee & Commission Income',       'PL','Income',  'Non-Interest',    9, 21,0, 1),
(11,'Trading & Investment Income',   'PL','Income',  'Non-Interest',    9, 22,0, 1),
(12,'FX Gains',                      'PL','Income',  'Non-Interest',    9, 23,0, 1),
(13,'Other Non-Interest Income',     'PL','Income',  'Non-Interest',    9, 24,0, 1),
(14,'Operating Expenses',            'PL','Expense', 'OpEx',         NULL, 30,1,-1),
(15,'Personnel Expenses',            'PL','Expense', 'OpEx',           14, 31,0,-1),
(16,'Administrative Expenses',       'PL','Expense', 'OpEx',           14, 32,0,-1),
(17,'Depreciation & Amortization',   'PL','Expense', 'OpEx',           14, 33,0,-1),
(18,'Provision for Loan Losses',     'PL','Expense', 'Risk Cost',    NULL, 40,0,-1),
(19,'Profit Before Tax',             'PL','Subtotal','PBT',          NULL, 50,1, 1),
(20,'Income Tax Expense',            'PL','Expense', 'Tax',          NULL, 51,0,-1),
(21,'Net Income',                    'PL','Subtotal','Bottom Line',  NULL, 52,1, 1),
-- Balance Sheet: Assets
(22,'Total Assets',                  'BS','Asset',   'Total',        NULL, 60,1, 1),
(23,'Cash & Central Bank Balances',  'BS','Asset',   'Liquid',         22, 61,0, 1),
(24,'Loans to Customers',            'BS','Asset',   'Loans',          22, 62,1, 1),
(25,'Consumer & Personal Loans',     'BS','Asset',   'Loans',          24, 63,0, 1),
(26,'Mortgage Loans',                'BS','Asset',   'Loans',          24, 64,0, 1),
(27,'SME & Corporate Loans',         'BS','Asset',   'Loans',          24, 65,0, 1),
(28,'Investment Securities',         'BS','Asset',   'Investments',    22, 66,0, 1),
(29,'Property Plant & Equipment',    'BS','Asset',   'Fixed Assets',   22, 67,0, 1),
(30,'Other Assets',                  'BS','Asset',   'Other',          22, 68,0, 1),
-- Balance Sheet: Liabilities
(31,'Total Liabilities',             'BS','Liability','Total',       NULL, 70,1,-1),
(32,'Customer Deposits',             'BS','Liability','Deposits',      31, 71,1,-1),
(33,'Demand Deposits',               'BS','Liability','Deposits',      32, 72,0,-1),
(34,'Savings Accounts',              'BS','Liability','Deposits',      32, 73,0,-1),
(35,'Term Deposits',                 'BS','Liability','Deposits',      32, 74,0,-1),
(36,'Interbank Borrowings',          'BS','Liability','Borrowings',    31, 75,0,-1),
(37,'Bonds Issued',                  'BS','Liability','Borrowings',    31, 76,0,-1),
(38,'Other Liabilities',             'BS','Liability','Other',         31, 77,0,-1),
-- Balance Sheet: Equity
(39,'Total Equity',                  'BS','Equity',  'Total',        NULL, 80,1, 1),
(40,'Share Capital',                 'BS','Equity',  'Capital',        39, 81,0, 1),
(41,'Retained Earnings',             'BS','Equity',  'Earnings',       39, 82,0, 1),
(42,'Regulatory Reserves',           'BS','Equity',  'Reserves',       39, 83,0, 1),
(43,'Other Comprehensive Income',    'BS','Equity',  'Other',          39, 84,0, 1);
GO

-- =========================================================
-- 9. Valid channel-segment-product-currency combinations
--
-- Branch (1-9)         : all segments, all products, all currencies
-- Digital (10-11)      : Retail, SME, Private Banking - all products
-- Remote/Call (12)     : Retail, SME - simple products only
-- Corporate Unit (13)  : Corporate and FI only
-- Private Unit (14)    : Private Banking only
-- =========================================================
IF OBJECT_ID('tempdb..#valid_combos') IS NOT NULL DROP TABLE #valid_combos;

CREATE TABLE #valid_combos (
    channel_id  INT,
    segment_id  INT,
    product_id  INT,
    currency_id INT
);

-- BRANCHES (1-9): full product/segment/currency coverage
-- Retail
INSERT INTO #valid_combos
SELECT ch.channel_id, 1, p.product_id, p.currency_id
FROM (VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9)) ch(channel_id)
CROSS JOIN (VALUES
    (1,1),(1,2),(2,1),(2,2),(3,1),(3,2),(7,1),(9,1),
    (10,1),(11,2),(12,3),(13,1),(13,2),(14,1),(15,2),(16,1),(17,1)
) p(product_id,currency_id);

-- SME
INSERT INTO #valid_combos
SELECT ch.channel_id, 2, p.product_id, p.currency_id
FROM (VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9)) ch(channel_id)
CROSS JOIN (VALUES
    (4,1),(4,2),(5,1),(5,2),(10,1),(11,2),(14,1),(16,1)
) p(product_id,currency_id);

-- Corporate
INSERT INTO #valid_combos
SELECT ch.channel_id, 3, p.product_id, p.currency_id
FROM (VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9)) ch(channel_id)
CROSS JOIN (VALUES
    (6,1),(6,2),(6,3),(10,1),(11,2),(12,3),(14,1),(15,2),(16,1)
) p(product_id,currency_id);

-- Private Banking
INSERT INTO #valid_combos
SELECT ch.channel_id, 4, p.product_id, p.currency_id
FROM (VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9)) ch(channel_id)
CROSS JOIN (VALUES
    (2,1),(2,2),(8,1),(8,2),(9,1),
    (10,1),(11,2),(12,3),(13,1),(13,2),(14,1),(15,2),(16,1),(17,1)
) p(product_id,currency_id);

-- Financial Institutions
INSERT INTO #valid_combos
SELECT ch.channel_id, 5, p.product_id, p.currency_id
FROM (VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9)) ch(channel_id)
CROSS JOIN (VALUES
    (10,1),(11,2),(12,3),(14,1),(15,2)
) p(product_id,currency_id);

-- DIGITAL (10-11): Retail, SME, Private Banking
-- Retail via digital
INSERT INTO #valid_combos
SELECT ch.channel_id, 1, p.product_id, p.currency_id
FROM (VALUES(10),(11)) ch(channel_id)
CROSS JOIN (VALUES
    (1,1),(1,2),(2,1),(2,2),(3,1),(3,2),(7,1),(9,1),
    (10,1),(11,2),(12,3),(13,1),(13,2),(14,1),(15,2),(16,1),(17,1)
) p(product_id,currency_id);

-- SME via digital
INSERT INTO #valid_combos
SELECT ch.channel_id, 2, p.product_id, p.currency_id
FROM (VALUES(10),(11)) ch(channel_id)
CROSS JOIN (VALUES
    (4,1),(4,2),(5,1),(10,1),(11,2),(14,1),(16,1)
) p(product_id,currency_id);

-- Private Banking via digital
INSERT INTO #valid_combos
SELECT ch.channel_id, 4, p.product_id, p.currency_id
FROM (VALUES(10),(11)) ch(channel_id)
CROSS JOIN (VALUES
    (2,1),(2,2),(8,1),(9,1),
    (10,1),(11,2),(12,3),(13,1),(13,2),(14,1),(15,2),(16,1),(17,1)
) p(product_id,currency_id);

-- CALL CENTER (12): Retail and SME, simple products
INSERT INTO #valid_combos
SELECT 12, 1, p.product_id, p.currency_id
FROM (VALUES
    (1,1),(1,2),(7,1),(9,1),(10,1),(11,2),(13,1),(13,2),(14,1),(16,1),(17,1)
) p(product_id,currency_id);

INSERT INTO #valid_combos
SELECT 12, 2, p.product_id, p.currency_id
FROM (VALUES
    (4,1),(10,1),(11,2),(14,1),(16,1)
) p(product_id,currency_id);

-- CORPORATE BANKING UNIT (13): Corporate and FI only
INSERT INTO #valid_combos
SELECT 13, 3, p.product_id, p.currency_id
FROM (VALUES
    (6,1),(6,2),(6,3),(10,1),(11,2),(12,3),(14,1),(15,2),(16,1)
) p(product_id,currency_id);

INSERT INTO #valid_combos
SELECT 13, 5, p.product_id, p.currency_id
FROM (VALUES
    (10,1),(11,2),(12,3),(14,1),(15,2)
) p(product_id,currency_id);

-- PRIVATE BANKING UNIT (14): Private Banking only
INSERT INTO #valid_combos
SELECT 14, 4, p.product_id, p.currency_id
FROM (VALUES
    (2,1),(2,2),(8,1),(8,2),(9,1),
    (10,1),(11,2),(12,3),(13,1),(13,2),(14,1),(15,2),(16,1),(17,1)
) p(product_id,currency_id);
GO

-- =========================================================
-- 10. fact_financial_data
-- No surrogate key - natural grain is the unique identifier.
-- rate_id joins to dim_currency for authoritative FX rates.
-- amount_nominal    = amount_eur * eom_rate
-- daily_avg_nominal = daily_avg_eur * daily_avg_rate
-- =========================================================
CREATE TABLE fact_financial_data (
    date_id           INT           NOT NULL REFERENCES dim_date(date_id),
    channel_id        INT           NOT NULL REFERENCES dim_channel(channel_id),
    segment_id        INT           NOT NULL REFERENCES dim_segment(segment_id),
    product_id        INT           NOT NULL REFERENCES dim_product(product_id),
    currency_id       INT           NOT NULL,
    scenario_id       INT           NOT NULL REFERENCES dim_scenario(scenario_id),
    budget_item_id    INT           NOT NULL REFERENCES dim_budget_items(budget_item_id),
    rate_id           VARCHAR(20)   NOT NULL REFERENCES dim_currency(rate_id),
    amount_eur        DECIMAL(22,2) NOT NULL DEFAULT 0,
    amount_nominal    DECIMAL(22,2) NOT NULL DEFAULT 0,
    daily_avg_eur     DECIMAL(22,2),
    daily_avg_nominal DECIMAL(22,2)
);
GO

-- =========================================================
-- 11. DATA GENERATION
-- Each block: CTE computes EUR amounts, then JOIN to dim_currency
-- derives nominal amounts using authoritative rates.
-- =========================================================

-- ── ACTUAL 2022 (scenario_id = 1) ────────────────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2022 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 1, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Actual 2022 done';

-- ── ACTUAL 2023 (scenario_id = 1, YoY x1.10) ────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.10
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.10
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2023 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 1, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Actual 2023 done';

-- ── ACTUAL 2024 (scenario_id = 1, YoY x1.21) ────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.21
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.21
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2024 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 1, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Actual 2024 done';

-- ── ACTUAL 2025 (scenario_id = 1, YoY x1.33) ────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.33
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.33
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2025 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 1, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Actual 2025 done';

-- ── BUDGET 2023 (scenario_id = 2) ────────────────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2023 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 2, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Budget 2023 done';

-- ── BUDGET 2024 (scenario_id = 3, YoY x1.12) ────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.12
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.12
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2024 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 3, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Budget 2024 done';

-- ── BUDGET 2025 (scenario_id = 4, YoY x1.25) ────────────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.25
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.25
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2025 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 4, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Budget 2025 done';

-- ── BUDGET 2026 TOP DOWN (scenario_id = 5, YoY x1.38) ────
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.38
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.38
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2026 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 5, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Budget 2026 TopDown done';

-- ── BUDGET 2026 BOTTOM UP (scenario_id = 6, YoY x1.28) ───
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.28
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.28
            * CASE d.quarter
                WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2026 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 6, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Budget 2026 BottomUp done';

-- ── FORECAST 2025 Q3 (scenario_id = 7) ───────────────────
-- Jan-Sep: mirrors Actual 2025 (multiplier 1.33)
-- Oct-Dec: Budget_2025 base x1.04 (tracking 4% above budget after strong Q3)
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter, d.month,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE WHEN d.month <= 9 THEN 1.33 ELSE 1.25 * 1.04 END
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE WHEN d.month <= 9 THEN 1.33 ELSE 1.25 * 1.04 END
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 15000 - 7500)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2025 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 7, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Forecast 2025 Q3 done';

-- ── FORECAST 2026 Q1 (scenario_id = 8, YoY x1.32) ───────
-- Full year 2026. Multiplier 1.32 sits between TopDown (1.38)
-- and BottomUp (1.28), reflecting Q1 actuals being conservative.
WITH base_amounts AS (
    SELECT
        d.date_id, d.quarter,
        ch.channel_id, ch.channel_name, ch.channel_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.32
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 15000 - 7500)
        ) AS DECIMAL(22,2)) AS amount_eur,
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 53000   WHEN 'Expense'   THEN 28000
                WHEN 'Asset'     THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity'    THEN 520000  ELSE 21000 END
            * CASE ch.channel_type
                WHEN 'Branch'        THEN CASE WHEN ch.channel_name LIKE '%Flagship%' THEN 3.0 ELSE 2.0 END
                WHEN 'Digital'       THEN 1.5
                WHEN 'Remote'        THEN 0.8
                WHEN 'Business Unit' THEN 2.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.32
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.25 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 15000 - 7500)
        ) AS DECIMAL(22,2)) AS daily_avg_eur
    FROM dim_date d
    CROSS JOIN dim_channel ch
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2026 AND vc.channel_id = ch.channel_id
)
INSERT INTO fact_financial_data
    (date_id, channel_id, segment_id, product_id, currency_id, scenario_id, budget_item_id,
     rate_id, amount_eur, amount_nominal, daily_avg_eur, daily_avg_nominal)
SELECT
    b.date_id, b.channel_id, b.segment_id, b.product_id, b.currency_id, 8, b.budget_item_id,
    CONCAT(b.date_id, b.currency_id),
    b.amount_eur,
    CAST(b.amount_eur    * c.eom_rate      AS DECIMAL(22,2)),
    b.daily_avg_eur,
    CAST(b.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2))
FROM base_amounts b
JOIN dim_currency c ON c.rate_id = CONCAT(b.date_id, b.currency_id);
GO
PRINT 'Forecast 2026 Q1 done';

-- =========================================================
-- CLEANUP
-- =========================================================
DROP TABLE #valid_combos;
GO

-- =========================================================
-- INDEXES
-- =========================================================
CREATE INDEX idx_fd_date        ON fact_financial_data(date_id);
CREATE INDEX idx_fd_channel     ON fact_financial_data(channel_id);
CREATE INDEX idx_fd_segment     ON fact_financial_data(segment_id);
CREATE INDEX idx_fd_product     ON fact_financial_data(product_id);
CREATE INDEX idx_fd_currency    ON fact_financial_data(currency_id);
CREATE INDEX idx_fd_scenario    ON fact_financial_data(scenario_id);
CREATE INDEX idx_fd_budget_item ON fact_financial_data(budget_item_id);
CREATE INDEX idx_fd_rate        ON fact_financial_data(rate_id);
CREATE INDEX idx_dc_date        ON dim_currency(date_id);
CREATE INDEX idx_dc_currency    ON dim_currency(currency_id);
GO

-- =========================================================
-- VALIDATION
-- =========================================================
SELECT 'dim_date'          AS tbl, COUNT(*) AS rows FROM dim_date           UNION ALL
SELECT 'dim_channel',               COUNT(*)         FROM dim_channel        UNION ALL
SELECT 'dim_segment',               COUNT(*)         FROM dim_segment        UNION ALL
SELECT 'dim_product',               COUNT(*)         FROM dim_product        UNION ALL
SELECT 'dim_currency',              COUNT(*)         FROM dim_currency       UNION ALL
SELECT 'dim_scenario',              COUNT(*)         FROM dim_scenario       UNION ALL
SELECT 'dim_budget_items',          COUNT(*)         FROM dim_budget_items   UNION ALL
SELECT 'fact_financial_data',       COUNT(*)         FROM fact_financial_data;

-- Scenario row counts
SELECT s.scenario_name, s.scenario_type, s.fiscal_year, COUNT(*) AS rows
FROM fact_financial_data f
JOIN dim_scenario s ON f.scenario_id = s.scenario_id
GROUP BY s.scenario_name, s.scenario_type, s.fiscal_year
ORDER BY s.fiscal_year, s.scenario_type, s.scenario_name;

-- EUR sanity: amount_eur = amount_nominal, both rates = 1.000000
SELECT TOP 5
    f.currency_id, c.eom_rate, c.daily_avg_rate,
    f.amount_eur, f.amount_nominal,
    ABS(f.amount_eur - f.amount_nominal) AS diff
FROM fact_financial_data f
JOIN dim_currency c ON c.rate_id = f.rate_id
WHERE f.currency_id = 1
ORDER BY NEWID();

-- USD/GBP: verify nominal = eur * rate
SELECT TOP 5
    f.currency_id,
    c.eom_rate,      f.amount_eur,    f.amount_nominal,
    CAST(f.amount_eur    * c.eom_rate       AS DECIMAL(22,2)) AS expected_nominal,
    c.daily_avg_rate, f.daily_avg_eur, f.daily_avg_nominal,
    CAST(f.daily_avg_eur * c.daily_avg_rate AS DECIMAL(22,2)) AS expected_daily_nominal
FROM fact_financial_data f
JOIN dim_currency c ON c.rate_id = f.rate_id
WHERE f.currency_id IN (2,3)
ORDER BY NEWID();

PRINT '================================================';
PRINT 'Imaginary Bank - Complete!';
PRINT 'Actuals 2022-2025  |  Budgets 2023-2026';
PRINT 'Forecasts: 2025-Q3, 2026-Q1';
PRINT 'EUR base  |  dim_currency as rate table'
PRINT '================================================';
GO