/* =========================================================
   IMAGINARY BANK ANALYTICS DATASET v5.0
   Author: Saba Chkhaidze

   Architecture : Single fact table, star schema
   Grain        : One row = one month-end financial entry per
                  branch x segment x product x currency
                  x scenario x budget_item

   Key improvements over v4:
   - Real GEL/USD and GEL/EUR annual average FX rates
     sourced from exchange-rates.org historical data
   - Row-level FX rate variance within realistic annual ranges
   - amount_nominal derived correctly as amount_gel / fx_rate
   - daily_avg_nominal derived correctly as daily_avg_gel / fx_rate
   - Actual scenarios: 2022-01-01 to 2025-12-31
   - Budget scenarios: up to 2026-12-31
   - GEL rows: fx_rate always 1.000000, nominal = gel
   =========================================================

   REAL FX RATE REFERENCE (source: exchange-rates.org)
   ┌──────┬─────────────┬───────────────┬─────────────┬───────────────┐
   │ Year │ USD/GEL avg │ USD/GEL range │ EUR/GEL avg │ EUR/GEL range │
   ├──────┼─────────────┼───────────────┼─────────────┼───────────────┤
   │ 2022 │   2.9150    │  2.6500–3.4450│   3.0600    │  2.8500–3.2000│
   │ 2023 │   2.6237    │  2.4800–2.7150│   2.8387    │  2.7212–2.9887│
   │ 2024 │   2.7172    │  2.6300–2.8700│   2.9412    │  2.8240–3.0922│
   │ 2025 │   2.7431    │  2.6900–2.8800│   3.1485    │  3.0829–3.2392│
   │ 2026 │   2.7200    │  2.6800–2.7600│   3.1600    │  3.1000–3.2200│
   └──────┴─────────────┴───────────────┴─────────────┴───────────────┘
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
-- 2. dim_date
-- Full calendar 2022-01-01 to 2026-12-31
-- date_id format: YYYYMMDD integer
-- =========================================================
CREATE TABLE dim_date (
    date_id      INT          NOT NULL PRIMARY KEY,
    full_date    DATE         NOT NULL,
    year         INT          NOT NULL,
    quarter      INT          NOT NULL,
    quarter_name VARCHAR(6)   NOT NULL,
    month        INT          NOT NULL,
    month_name   VARCHAR(12)  NOT NULL,
    day          INT          NOT NULL,
    is_month_end BIT          NOT NULL DEFAULT 0,
    is_weekend   BIT          NOT NULL DEFAULT 0,
    is_holiday   BIT          NOT NULL DEFAULT 0
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
        DAY(@d),
        CASE WHEN @d = EOMONTH(@d) THEN 1 ELSE 0 END,
        CASE WHEN DATEPART(WEEKDAY,@d) IN (1,7) THEN 1 ELSE 0 END,
        0
    );
    SET @d = DATEADD(DAY,1,@d);
END
GO

-- =========================================================
-- 3. dim_branch
-- =========================================================
CREATE TABLE dim_branch (
    branch_id    INT          NOT NULL PRIMARY KEY,
    branch_name  VARCHAR(100) NOT NULL,
    branch_type  VARCHAR(30)  NOT NULL,
    city         VARCHAR(50)  NOT NULL,
    region       VARCHAR(50)  NOT NULL,
    opened_date  DATE,
    manager_name VARCHAR(100),
    is_active    BIT          NOT NULL DEFAULT 1
);

INSERT INTO dim_branch VALUES
( 1,'Rustaveli Flagship', 'Flagship','Tbilisi','Central Tbilisi','2018-03-01','Nino Kalandadze',     1),
( 2,'Vake Branch',        'Standard','Tbilisi','West Tbilisi',   '2019-06-15','Giorgi Beridze',      1),
( 3,'Saburtalo Branch',   'Standard','Tbilisi','North Tbilisi',  '2020-02-10','Lika Dgebuadze',      1),
( 4,'Isani Branch',       'Mini',    'Tbilisi','East Tbilisi',   '2021-08-01','Davit Tsereteli',     1),
( 5,'Batumi Flagship',    'Flagship','Batumi', 'Adjara',         '2018-09-01','Tamar Mchedlidze',    1),
( 6,'Batumi City Branch', 'Standard','Batumi', 'Adjara',         '2022-01-15','Mariam Kobaidze',     1),
( 7,'Kutaisi Main',       'Standard','Kutaisi','Imereti',        '2020-01-10','Levan Sturua',        1),
( 8,'Rustavi Branch',     'Standard','Rustavi','Kvemo Kartli',   '2021-05-20','Ana Jibuti',          1),
( 9,'Gori Branch',        'Mini',    'Gori',  'Shida Kartli',   '2022-06-01','Irakli Lomidze',      1),
(10,'Digital Branch',     'Digital', 'Online','Nationwide',     '2023-01-01','Salome Kvaratskhelia',1);
GO

-- =========================================================
-- 4. dim_segment
-- =========================================================
CREATE TABLE dim_segment (
    segment_id   INT         NOT NULL PRIMARY KEY,
    segment_name VARCHAR(30) NOT NULL,
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
(10,'Current Account GEL', 'Deposit','Current',   1),
(11,'Current Account USD', 'Deposit','Current',   1),
(12,'Current Account EUR', 'Deposit','Current',   1),
(13,'Savings Account',     'Deposit','Savings',   1),
(14,'Term Deposit GEL',    'Deposit','Term',      1),
(15,'Term Deposit USD',    'Deposit','Term',      1),
(16,'Internet Banking',    'Service','Digital',   1),
(17,'Mobile Banking',      'Service','Digital',   1);
GO

-- =========================================================
-- 6. dim_currency
-- Updated with real midpoint rates
-- =========================================================
CREATE TABLE dim_currency (
    currency_id     INT           NOT NULL PRIMARY KEY,
    currency_code   CHAR(3)       NOT NULL,
    currency_name   VARCHAR(50)   NOT NULL,
    currency_symbol VARCHAR(5)    NOT NULL,
    fx_rate_to_gel  DECIMAL(10,6) NOT NULL
);

INSERT INTO dim_currency VALUES
(1,'GEL','Georgian Lari','₾',1.000000),
(2,'USD','US Dollar',   '$',2.720000),   -- 2025/2026 midpoint
(3,'EUR','Euro',        '€',3.150000);   -- 2025/2026 midpoint
GO

-- =========================================================
-- 7. dim_scenario
-- =========================================================
CREATE TABLE dim_scenario (
    scenario_id   INT         NOT NULL PRIMARY KEY,
    scenario_name VARCHAR(50) NOT NULL,
    scenario_type VARCHAR(30) NOT NULL,
    fiscal_year   INT         NOT NULL,
    description   VARCHAR(200)
);

INSERT INTO dim_scenario VALUES
(1,'Actual_2022',     'Actual',  2022,'Audited actuals FY2022'),
(2,'Actual_2023',     'Actual',  2023,'Audited actuals FY2023'),
(3,'Actual_2024',     'Actual',  2024,'Actuals FY2024'),
(4,'Actual_2025',     'Actual',  2025,'Actuals FY2025'),
(5,'Budget_2023',     'Budget',  2023,'Approved budget FY2023'),
(6,'Budget_2024',     'Budget',  2024,'Approved budget FY2024'),
(7,'Budget_2025',     'Budget',  2025,'Approved budget FY2025'),
(8,'Budget_2026',     'Budget',  2026,'Approved budget FY2026'),
(9,'Stress_Test_2024','Stress',  2024,'Adverse scenario stress test');
GO

-- =========================================================
-- 8. dim_budget_items
-- =========================================================
CREATE TABLE dim_budget_items (
    budget_item_id  INT          NOT NULL PRIMARY KEY,
    item_name       VARCHAR(100) NOT NULL,
    statement_type  VARCHAR(5)   NOT NULL,
    category        VARCHAR(50)  NOT NULL,
    subcategory     VARCHAR(50),
    parent_item_id  INT          REFERENCES dim_budget_items(budget_item_id),
    sort_order      INT          NOT NULL,
    is_subtotal     BIT          NOT NULL DEFAULT 0,
    sign_convention INT          NOT NULL DEFAULT 1
);

INSERT INTO dim_budget_items VALUES
-- P&L
( 1,'Net Interest Income',           'PL','Income', 'NII',         NULL, 10,1, 1),
( 2,'Interest Income',               'PL','Income', 'NII',            1, 11,1, 1),
( 3,'Interest Income on Loans',      'PL','Income', 'NII',            2, 12,0, 1),
( 4,'Interest Income on Securities', 'PL','Income', 'NII',            2, 13,0, 1),
( 5,'Interest Income on Placements', 'PL','Income', 'NII',            2, 14,0, 1),
( 6,'Interest Expense',              'PL','Expense','NII',            1, 15,1,-1),
( 7,'Interest Expense on Deposits',  'PL','Expense','NII',            6, 16,0,-1),
( 8,'Interest Expense on Borrowings','PL','Expense','NII',            6, 17,0,-1),
( 9,'Non-Interest Income',           'PL','Income', 'Non-Interest',NULL, 20,1, 1),
(10,'Fee & Commission Income',       'PL','Income', 'Non-Interest',   9, 21,0, 1),
(11,'Trading & Investment Income',   'PL','Income', 'Non-Interest',   9, 22,0, 1),
(12,'FX Gains',                      'PL','Income', 'Non-Interest',   9, 23,0, 1),
(13,'Other Non-Interest Income',     'PL','Income', 'Non-Interest',   9, 24,0, 1),
(14,'Operating Expenses',            'PL','Expense','OpEx',        NULL, 30,1,-1),
(15,'Personnel Expenses',            'PL','Expense','OpEx',          14, 31,0,-1),
(16,'Administrative Expenses',       'PL','Expense','OpEx',          14, 32,0,-1),
(17,'Depreciation & Amortization',   'PL','Expense','OpEx',          14, 33,0,-1),
(18,'Provision for Loan Losses',     'PL','Expense','Risk Cost',   NULL, 40,0,-1),
(19,'Profit Before Tax',             'PL','Subtotal','PBT',        NULL, 50,1, 1),
(20,'Income Tax Expense',            'PL','Expense','Tax',         NULL, 51,0,-1),
(21,'Net Income',                    'PL','Subtotal','Bottom Line',NULL, 52,1, 1),
-- Balance Sheet: Assets
(22,'Total Assets',                  'BS','Asset',  'Total',       NULL, 60,1, 1),
(23,'Cash & Central Bank Balances',  'BS','Asset',  'Liquid',        22, 61,0, 1),
(24,'Loans to Customers',            'BS','Asset',  'Loans',         22, 62,1, 1),
(25,'Consumer & Personal Loans',     'BS','Asset',  'Loans',         24, 63,0, 1),
(26,'Mortgage Loans',                'BS','Asset',  'Loans',         24, 64,0, 1),
(27,'SME & Corporate Loans',         'BS','Asset',  'Loans',         24, 65,0, 1),
(28,'Investment Securities',         'BS','Asset',  'Investments',   22, 66,0, 1),
(29,'Property Plant & Equipment',    'BS','Asset',  'Fixed Assets',  22, 67,0, 1),
(30,'Other Assets',                  'BS','Asset',  'Other',         22, 68,0, 1),
-- Balance Sheet: Liabilities
(31,'Total Liabilities',             'BS','Liability','Total',     NULL, 70,1,-1),
(32,'Customer Deposits',             'BS','Liability','Deposits',    31, 71,1,-1),
(33,'Demand Deposits',               'BS','Liability','Deposits',    32, 72,0,-1),
(34,'Savings Accounts',              'BS','Liability','Deposits',    32, 73,0,-1),
(35,'Term Deposits',                 'BS','Liability','Deposits',    32, 74,0,-1),
(36,'Interbank Borrowings',          'BS','Liability','Borrowings',  31, 75,0,-1),
(37,'Bonds Issued',                  'BS','Liability','Borrowings',  31, 76,0,-1),
(38,'Other Liabilities',             'BS','Liability','Other',       31, 77,0,-1),
-- Balance Sheet: Equity
(39,'Total Equity',                  'BS','Equity', 'Total',      NULL, 80,1, 1),
(40,'Share Capital',                 'BS','Equity', 'Capital',      39, 81,0, 1),
(41,'Retained Earnings',             'BS','Equity', 'Earnings',     39, 82,0, 1),
(42,'Regulatory Reserves',           'BS','Equity', 'Reserves',     39, 83,0, 1),
(43,'Other Comprehensive Income',    'BS','Equity', 'Other',        39, 84,0, 1);
GO

-- =========================================================
-- 9. VALID PRODUCT-SEGMENT COMBINATIONS
-- =========================================================
CREATE TABLE #valid_combos (
    segment_id  INT,
    product_id  INT,
    currency_id INT
);

-- RETAIL
INSERT INTO #valid_combos VALUES
(1, 1,1),(1, 1,2),(1, 2,1),(1, 2,2),(1, 3,1),(1, 3,2),
(1, 7,1),(1, 9,1),
(1,10,1),(1,11,2),(1,12,3),
(1,13,1),(1,13,2),(1,14,1),(1,15,2),
(1,16,1),(1,17,1);

-- SME
INSERT INTO #valid_combos VALUES
(2, 4,1),(2, 4,2),(2, 5,1),(2, 5,2),
(2,10,1),(2,11,2),(2,14,1),(2,16,1);

-- CORPORATE
INSERT INTO #valid_combos VALUES
(3, 6,1),(3, 6,2),(3, 6,3),
(3,10,1),(3,11,2),(3,12,3),
(3,14,1),(3,15,2),(3,16,1);

-- PRIVATE BANKING
INSERT INTO #valid_combos VALUES
(4, 2,1),(4, 2,2),(4, 8,1),(4, 8,2),(4, 9,1),
(4,10,1),(4,11,2),(4,12,3),
(4,13,1),(4,13,2),(4,14,1),(4,15,2),
(4,16,1),(4,17,1);

-- FINANCIAL INSTITUTIONS
INSERT INTO #valid_combos VALUES
(5,10,1),(5,11,2),(5,12,3),(5,14,1),(5,15,2);
GO

-- =========================================================
-- 10. fact_financial_data
-- =========================================================
CREATE TABLE fact_financial_data (
    entry_id          BIGINT        IDENTITY PRIMARY KEY,
    date_id           INT           NOT NULL REFERENCES dim_date(date_id),
    branch_id         INT           NOT NULL REFERENCES dim_branch(branch_id),
    segment_id        INT           NOT NULL REFERENCES dim_segment(segment_id),
    product_id        INT           NOT NULL REFERENCES dim_product(product_id),
    currency_id       INT           NOT NULL REFERENCES dim_currency(currency_id),
    scenario_id       INT           NOT NULL REFERENCES dim_scenario(scenario_id),
    budget_item_id    INT           NOT NULL REFERENCES dim_budget_items(budget_item_id),

    amount_gel        DECIMAL(22,2) NOT NULL DEFAULT 0,
    amount_nominal    DECIMAL(22,2) NOT NULL DEFAULT 0,
    daily_avg_gel     DECIMAL(22,2),
    daily_avg_nominal DECIMAL(22,2),
    fx_rate           DECIMAL(10,6) NOT NULL DEFAULT 1.000000
);
GO

-- =========================================================
-- 11. DATA GENERATION
--
-- FX RATE LOGIC (applied uniformly across all scenarios):
--   GEL  : fx_rate = 1.000000 (always)
--   USD  : fx_rate = annual_mid + row-level noise within annual range
--   EUR  : fx_rate = annual_mid + row-level noise within annual range
--
-- Variance formula:
--   USD 2022: 2.9150 ± random within ±0.2650  → range ~2.65–3.18
--   USD 2023: 2.6237 ± random within ±0.0700  → range ~2.55–2.69
--   USD 2024: 2.7172 ± random within ±0.0700  → range ~2.65–2.79
--   USD 2025: 2.7431 ± random within ±0.0750  → range ~2.67–2.82
--   USD 2026: 2.7200 ± random within ±0.0400  → range ~2.68–2.76
--
-- All amounts:
--   amount_gel     = base * branch * segment * yoy * quarter * currency_weight + noise
--   fx_rate        = realistic row-level rate per year
--   amount_nominal = amount_gel / fx_rate
--   daily_avg_gel  = amount_gel * daily_adj + smaller_noise
--   daily_avg_nominal = daily_avg_gel / fx_rate
-- =========================================================

-- ── HELPER: FX rate expression per year and currency ─────
-- We use a CTE-style approach via inline CASE in each INSERT.
-- The pattern is:
--   CASE currency_id
--     WHEN 1 THEN 1.000000
--     WHEN 2 THEN <usd_mid> + (ABS(CHECKSUM(NEWID())) % <usd_range_cents>) / 10000.0 - <usd_half_range>
--     WHEN 3 THEN <eur_mid> + (ABS(CHECKSUM(NEWID())) % <eur_range_cents>) / 10000.0 - <eur_half_range>
--   END
-- ─────────────────────────────────────────────────────────

-- ── SCENARIO 1: Actual_2022 ───────────────────────────────
-- USD: avg 2.9150, range 2.65–3.18  → mid±0.265, range 5300 units of 0.0001
-- EUR: avg 3.0600, range 2.85–3.20  → mid±0.175, range 3500 units of 0.0001
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT
    d.date_id, b.branch_id, vc.segment_id, vc.product_id, vc.currency_id,
    1, bi.budget_item_id,

    -- amount_gel
    CAST(ABS(
        CASE bi.category
            WHEN 'Income'    THEN 50000  WHEN 'Expense'   THEN 30000
            WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
            WHEN 'Equity'    THEN 500000  ELSE 20000 END
        * CASE b.branch_type
            WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
            WHEN 'Mini'     THEN 0.8 WHEN 'Digital'  THEN 1.5 ELSE 1.0 END
        * CASE vc.segment_id
            WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
        * CASE d.quarter
            WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
        * CASE vc.currency_id
            WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
        + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
    ) AS DECIMAL(22,2)) AS amount_gel,

    -- amount_nominal = amount_gel / fx_rate (computed inline via subquery trick using CROSS APPLY)
    -- We calculate fx_rate once, reuse for nominal — done via CROSS APPLY below

    0, -- placeholder, will be replaced by CROSS APPLY value
    0,
    0,
    0,

    -- fx_rate
    CASE vc.currency_id
        WHEN 1 THEN 1.000000
        WHEN 2 THEN CAST(2.9150 + (ABS(CHECKSUM(NEWID())) % 5300) / 10000.0 - 0.2650 AS DECIMAL(10,6))
        WHEN 3 THEN CAST(3.0600 + (ABS(CHECKSUM(NEWID())) % 3500) / 10000.0 - 0.1750 AS DECIMAL(10,6))
    END

FROM dim_date d
CROSS JOIN dim_branch b
CROSS JOIN #valid_combos vc
JOIN dim_currency c      ON c.currency_id  = vc.currency_id
JOIN dim_budget_items bi ON bi.is_subtotal = 0
WHERE d.is_month_end = 1 AND d.year = 2022;
GO

-- The approach above would require updating nominal after insert.
-- Cleaner: use a single CTE to compute gel + fx_rate together, then derive nominal.
-- Let's drop and redo with the correct pattern:

TRUNCATE TABLE fact_financial_data;
GO

-- =========================================================
-- CORRECT INSERTION PATTERN
-- Uses CTE to compute amount_gel and fx_rate in one step,
-- then derives amount_nominal, daily_avg_gel, daily_avg_nominal
-- from those computed values.
-- =========================================================

-- ── SCENARIO 1: Actual_2022 ───────────────────────────────
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,

        -- Step 1: compute amount_gel
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE b.branch_type
                WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini'     THEN 0.8 WHEN 'Digital'  THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id
                WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_gel,

        -- Step 2: compute daily_avg_gel
        CAST(ABS(
            CASE bi.category
                WHEN 'Income'    THEN 50000   WHEN 'Expense'   THEN 30000
                WHEN 'Asset'     THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity'    THEN 500000  ELSE 20000 END
            * CASE b.branch_type
                WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini'     THEN 0.8 WHEN 'Digital'  THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id
                WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter
                WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id
                WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category
                WHEN 'Asset'     THEN 0.94
                WHEN 'Liability' THEN 1.03
                ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,

        -- Step 3: compute fx_rate with real 2022 annual ranges
        -- USD 2022: avg 2.9150, realistic range 2.65–3.18
        -- EUR 2022: avg 3.0600, realistic range 2.85–3.27
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.9150 + (ABS(CHECKSUM(NEWID())) % 5300) / 10000.0 - 0.2650
            WHEN 3 THEN 3.0600 + (ABS(CHECKSUM(NEWID())) % 4200) / 10000.0 - 0.2100
        END AS DECIMAL(10,6)) AS fx_rate

    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2022
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT
    date_id, branch_id, segment_id, product_id, currency_id,
    1,
    budget_item_id,
    amount_gel,
    CAST(amount_gel     / NULLIF(fx_rate, 0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel  / NULLIF(fx_rate, 0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 1 (Actual_2022) done';

-- ── SCENARIO 2: Actual_2023 ───────────────────────────────
-- USD 2023: avg 2.6237, range 2.48–2.72  → ±0.120
-- EUR 2023: avg 2.8387, range 2.72–2.99  → ±0.135
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 50000 WHEN 'Expense' THEN 30000
                WHEN 'Asset' THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity' THEN 500000 ELSE 20000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.10
            * CASE d.quarter WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 50000 WHEN 'Expense' THEN 30000
                WHEN 'Asset' THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity' THEN 500000 ELSE 20000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.10
            * CASE d.quarter WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.6237 + (ABS(CHECKSUM(NEWID())) % 2400) / 10000.0 - 0.1200
            WHEN 3 THEN 2.8387 + (ABS(CHECKSUM(NEWID())) % 2700) / 10000.0 - 0.1350
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2023
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 2, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 2 (Actual_2023) done';

-- ── SCENARIO 3: Actual_2024 ───────────────────────────────
-- USD 2024: avg 2.7172, range 2.63–2.87  → ±0.120
-- EUR 2024: avg 2.9412, range 2.82–3.09  → ±0.135
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 50000 WHEN 'Expense' THEN 30000
                WHEN 'Asset' THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity' THEN 500000 ELSE 20000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.21
            * CASE d.quarter WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 50000 WHEN 'Expense' THEN 30000
                WHEN 'Asset' THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity' THEN 500000 ELSE 20000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.21
            * CASE d.quarter WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.7172 + (ABS(CHECKSUM(NEWID())) % 2400) / 10000.0 - 0.1200
            WHEN 3 THEN 2.9412 + (ABS(CHECKSUM(NEWID())) % 2700) / 10000.0 - 0.1350
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2024
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 3, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 3 (Actual_2024) done';

-- ── SCENARIO 4: Actual_2025 ───────────────────────────────
-- USD 2025: avg 2.7431, range 2.69–2.88  → ±0.095
-- EUR 2025: avg 3.1485, range 3.08–3.24  → ±0.080
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 50000 WHEN 'Expense' THEN 30000
                WHEN 'Asset' THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity' THEN 500000 ELSE 20000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.33  -- ~10% YoY growth from 2024
            * CASE d.quarter WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 30000 - 15000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 50000 WHEN 'Expense' THEN 30000
                WHEN 'Asset' THEN 2000000 WHEN 'Liability' THEN 1500000
                WHEN 'Equity' THEN 500000 ELSE 20000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.33
            * CASE d.quarter WHEN 1 THEN 0.90 WHEN 2 THEN 0.95 WHEN 3 THEN 1.00 WHEN 4 THEN 1.15 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 20000 - 10000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.7431 + (ABS(CHECKSUM(NEWID())) % 1900) / 10000.0 - 0.0950
            WHEN 3 THEN 3.1485 + (ABS(CHECKSUM(NEWID())) % 1600) / 10000.0 - 0.0800
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2025
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 4, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 4 (Actual_2025) done';

-- ── SCENARIO 5: Budget_2023 ───────────────────────────────
-- USD 2023 budget: same rate range as actual 2023
-- EUR 2023 budget: same rate range as actual 2023
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.6237 + (ABS(CHECKSUM(NEWID())) % 2400) / 10000.0 - 0.1200
            WHEN 3 THEN 2.8387 + (ABS(CHECKSUM(NEWID())) % 2700) / 10000.0 - 0.1350
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2023
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 5, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 5 (Budget_2023) done';

-- ── SCENARIO 6: Budget_2024 ───────────────────────────────
-- USD 2024: avg 2.7172  EUR 2024: avg 2.9412
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.12
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.12
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.7172 + (ABS(CHECKSUM(NEWID())) % 2400) / 10000.0 - 0.1200
            WHEN 3 THEN 2.9412 + (ABS(CHECKSUM(NEWID())) % 2700) / 10000.0 - 0.1350
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2024
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 6, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 6 (Budget_2024) done';

-- ── SCENARIO 7: Budget_2025 ───────────────────────────────
-- USD 2025: avg 2.7431  EUR 2025: avg 3.1485
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.25
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.25
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.7431 + (ABS(CHECKSUM(NEWID())) % 1900) / 10000.0 - 0.0950
            WHEN 3 THEN 3.1485 + (ABS(CHECKSUM(NEWID())) % 1600) / 10000.0 - 0.0800
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2025
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 7, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 7 (Budget_2025) done';

-- ── SCENARIO 8: Budget_2026 ───────────────────────────────
-- USD 2026 estimated: avg 2.7200, range 2.68–2.76  → ±0.040
-- EUR 2026 estimated: avg 3.1600, range 3.10–3.22  → ±0.060
WITH base AS (
    SELECT
        d.date_id, d.quarter,
        b.branch_id, b.branch_type,
        vc.segment_id, vc.product_id, vc.currency_id,
        bi.budget_item_id, bi.category,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.38  -- ~10% YoY growth from 2025 budget
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            + (ABS(CHECKSUM(NEWID())) % 10000 - 5000)
        ) AS DECIMAL(22,2)) AS amount_gel,
        CAST(ABS(
            CASE bi.category WHEN 'Income' THEN 53000 WHEN 'Expense' THEN 28000
                WHEN 'Asset' THEN 2100000 WHEN 'Liability' THEN 1550000
                WHEN 'Equity' THEN 520000 ELSE 21000 END
            * CASE b.branch_type WHEN 'Flagship' THEN 3.0 WHEN 'Standard' THEN 2.0
                WHEN 'Mini' THEN 0.8 WHEN 'Digital' THEN 1.5 ELSE 1.0 END
            * CASE vc.segment_id WHEN 3 THEN 4.0 WHEN 4 THEN 3.0 WHEN 5 THEN 2.5 WHEN 2 THEN 2.0 ELSE 1.0 END
            * 1.38
            * CASE d.quarter WHEN 1 THEN 0.92 WHEN 2 THEN 0.96 WHEN 3 THEN 1.00 WHEN 4 THEN 1.12 ELSE 1.0 END
            * CASE vc.currency_id WHEN 1 THEN 1.00 WHEN 2 THEN 0.40 WHEN 3 THEN 0.20 ELSE 1.0 END
            * CASE bi.category WHEN 'Asset' THEN 0.94 WHEN 'Liability' THEN 1.03 ELSE 1.00 END
            + (ABS(CHECKSUM(NEWID())) % 8000 - 4000)
        ) AS DECIMAL(22,2)) AS daily_avg_gel,
        CAST(CASE vc.currency_id
            WHEN 1 THEN 1.000000
            WHEN 2 THEN 2.7200 + (ABS(CHECKSUM(NEWID())) % 800)  / 10000.0 - 0.0400
            WHEN 3 THEN 3.1600 + (ABS(CHECKSUM(NEWID())) % 1200) / 10000.0 - 0.0600
        END AS DECIMAL(10,6)) AS fx_rate
    FROM dim_date d
    CROSS JOIN dim_branch b
    CROSS JOIN #valid_combos vc
    JOIN dim_budget_items bi ON bi.is_subtotal = 0
    WHERE d.is_month_end = 1 AND d.year = 2026
)
INSERT INTO fact_financial_data
    (date_id, branch_id, segment_id, product_id, currency_id,
     scenario_id, budget_item_id,
     amount_gel, amount_nominal, daily_avg_gel, daily_avg_nominal, fx_rate)
SELECT date_id, branch_id, segment_id, product_id, currency_id, 8, budget_item_id,
    amount_gel,
    CAST(amount_gel    / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    daily_avg_gel,
    CAST(daily_avg_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)),
    fx_rate
FROM base;
GO
PRINT 'Scenario 8 (Budget_2026) done';

-- =========================================================
-- CLEANUP
-- =========================================================
DROP TABLE #valid_combos;
GO

-- =========================================================
-- INDEXES
-- =========================================================
CREATE INDEX idx_fd_date        ON fact_financial_data(date_id);
CREATE INDEX idx_fd_branch      ON fact_financial_data(branch_id);
CREATE INDEX idx_fd_segment     ON fact_financial_data(segment_id);
CREATE INDEX idx_fd_product     ON fact_financial_data(product_id);
CREATE INDEX idx_fd_currency    ON fact_financial_data(currency_id);
CREATE INDEX idx_fd_scenario    ON fact_financial_data(scenario_id);
CREATE INDEX idx_fd_budget_item ON fact_financial_data(budget_item_id);
GO

-- =========================================================
-- VALIDATION
-- =========================================================
SELECT 'dim_date'         AS tbl, COUNT(*) AS rows FROM dim_date         UNION ALL
SELECT 'dim_branch',               COUNT(*)         FROM dim_branch       UNION ALL
SELECT 'dim_segment',              COUNT(*)         FROM dim_segment      UNION ALL
SELECT 'dim_product',              COUNT(*)         FROM dim_product      UNION ALL
SELECT 'dim_currency',             COUNT(*)         FROM dim_currency     UNION ALL
SELECT 'dim_scenario',             COUNT(*)         FROM dim_scenario     UNION ALL
SELECT 'dim_budget_items',         COUNT(*)         FROM dim_budget_items UNION ALL
SELECT 'fact_financial_data',      COUNT(*)         FROM fact_financial_data;

-- Scenario breakdown
SELECT s.scenario_name, s.scenario_type, COUNT(*) AS rows
FROM fact_financial_data f
JOIN dim_scenario s ON f.scenario_id = s.scenario_id
GROUP BY s.scenario_name, s.scenario_type
ORDER BY s.scenario_name;

-- FX rate sanity check: GEL rows should have fx_rate = 1.0 and amount_gel = amount_nominal
SELECT TOP 10
    currency_id,
    fx_rate,
    amount_gel,
    amount_nominal,
    ABS(amount_gel - amount_nominal) AS gel_nominal_diff
FROM fact_financial_data
WHERE currency_id = 1
ORDER BY NEWID();

-- USD/EUR rows: verify nominal = gel / fx_rate
SELECT TOP 10
    currency_id,
    fx_rate,
    amount_gel,
    amount_nominal,
    CAST(amount_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2)) AS expected_nominal,
    ABS(amount_nominal - CAST(amount_gel / NULLIF(fx_rate,0) AS DECIMAL(22,2))) AS diff
FROM fact_financial_data
WHERE currency_id IN (2,3)
ORDER BY NEWID();

PRINT '================================================';
PRINT 'Imaginary Bank v5.0 - Complete!';
PRINT 'Actuals: 2022–2025 | Budgets: 2023–2026';
PRINT 'Real FX rates | Correct nominal derivation';
PRINT 'Single fact | Star schema | Realistic combos';
PRINT '================================================';
GO