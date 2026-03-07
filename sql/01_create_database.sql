-- ============================================
-- IMAGINARY BANK - Complete Database Script
-- SQL Server 2025 Express Compatible
-- ============================================

USE master;
GO

-- Create Database
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'ImaginaryBank')
    DROP DATABASE ImaginaryBank;
GO

CREATE DATABASE ImaginaryBank;
GO

USE ImaginaryBank;
GO

-- ============================================
-- TABLE 1: BRANCHES
-- ============================================
CREATE TABLE branches (
    branch_id       INT PRIMARY KEY,
    branch_name     NVARCHAR(100),
    city            NVARCHAR(50),
    region          NVARCHAR(50),
    opened_date     DATE,
    manager_name    NVARCHAR(100),
    is_active       BIT
);

INSERT INTO branches VALUES
(1, 'Rustaveli Branch',   'Tbilisi',  'Central',  '2018-03-01', 'Nino Kalandadze',  1),
(2, 'Vake Branch',        'Tbilisi',  'West',     '2019-06-15', 'Giorgi Beridze',   1),
(3, 'Batumi Main Branch', 'Batumi',   'Adjara',   '2018-09-01', 'Tamar Mchedlidze', 1),
(4, 'Kutaisi Branch',     'Kutaisi',  'Imereti',  '2020-01-10', 'Levan Sturua',     1),
(5, 'Rustavi Branch',     'Rustavi',  'Kvemo Kartli', '2021-05-20', 'Ana Jibuti',   1);
GO

-- ============================================
-- TABLE 2: CUSTOMERS
-- ============================================
CREATE TABLE customers (
    customer_id     INT PRIMARY KEY,
    first_name      NVARCHAR(50),
    last_name       NVARCHAR(50),
    gender          CHAR(1),
    birth_date      DATE,
    email           NVARCHAR(100),
    phone           NVARCHAR(20),
    city            NVARCHAR(50),
    segment         NVARCHAR(20),  -- Retail, SME, Corporate
    branch_id       INT FOREIGN KEY REFERENCES branches(branch_id),
    joined_date     DATE,
    is_active       BIT
);
GO

-- Generate 2000 customers using a numbers trick
WITH nums AS (
    SELECT TOP 2000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects a CROSS JOIN sys.objects b
),
names AS (
    SELECT n,
        CASE (n % 10)
            WHEN 0 THEN 'Giorgi'   WHEN 1 THEN 'Nino'
            WHEN 2 THEN 'Luka'     WHEN 3 THEN 'Mariam'
            WHEN 4 THEN 'David'    WHEN 5 THEN 'Tamar'
            WHEN 6 THEN 'Levan'    WHEN 7 THEN 'Ana'
            WHEN 8 THEN 'Irakli'   ELSE 'Salome'
        END AS first_name,
        CASE (n % 8)
            WHEN 0 THEN 'Beridze'    WHEN 1 THEN 'Kalandadze'
            WHEN 2 THEN 'Sturua'     WHEN 3 THEN 'Jibuti'
            WHEN 4 THEN 'Mchedlidze' WHEN 5 THEN 'Kvaratskhelia'
            WHEN 6 THEN 'Chikvanaia' ELSE 'Lomidze'
        END AS last_name,
        CASE WHEN n % 2 = 0 THEN 'M' ELSE 'F' END AS gender,
        DATEADD(DAY, -(n * 7 + 8000), GETDATE()) AS birth_date,
        CASE (n % 5)
            WHEN 0 THEN 'Tbilisi' WHEN 1 THEN 'Batumi'
            WHEN 2 THEN 'Kutaisi' WHEN 3 THEN 'Rustavi'
            ELSE 'Tbilisi'
        END AS city,
        CASE WHEN n % 10 < 7 THEN 'Retail'
             WHEN n % 10 < 9 THEN 'SME'
             ELSE 'Corporate'
        END AS segment,
        (n % 5) + 1 AS branch_id,
        DATEADD(DAY, -(n * 3 + 100), GETDATE()) AS joined_date
    FROM nums
)
INSERT INTO customers
SELECT
    n AS customer_id,
    first_name,
    last_name,
    gender,
    CAST(birth_date AS DATE),
    LOWER(first_name) + '.' + LOWER(last_name) + CAST(n AS NVARCHAR) + '@email.ge' AS email,
    '+995 5' + RIGHT('00' + CAST((n * 17) % 100 AS VARCHAR), 2) + ' ' +
              RIGHT('000' + CAST((n * 31) % 1000 AS VARCHAR), 3) + ' ' +
              RIGHT('000' + CAST((n * 53) % 1000 AS VARCHAR), 3) AS phone,
    city,
    segment,
    branch_id,
    CAST(joined_date AS DATE),
    CASE WHEN n % 20 = 0 THEN 0 ELSE 1 END AS is_active
FROM names;
GO

-- ============================================
-- TABLE 3: ACCOUNTS
-- ============================================
CREATE TABLE accounts (
    account_id      INT PRIMARY KEY,
    customer_id     INT FOREIGN KEY REFERENCES customers(customer_id),
    account_type    NVARCHAR(20),   -- Checking, Savings, Credit, Loan
    currency        CHAR(3),        -- GEL, USD, EUR
    opened_date     DATE,
    balance         DECIMAL(18,2),
    credit_limit    DECIMAL(18,2),
    is_active       BIT
);
GO

WITH nums AS (
    SELECT TOP 2000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects a CROSS JOIN sys.objects b
)
INSERT INTO accounts
SELECT
    n AS account_id,
    n AS customer_id,
    CASE (n % 4)
        WHEN 0 THEN 'Checking'
        WHEN 1 THEN 'Savings'
        WHEN 2 THEN 'Credit'
        ELSE 'Loan'
    END AS account_type,
    CASE (n % 3)
        WHEN 0 THEN 'GEL'
        WHEN 1 THEN 'USD'
        ELSE 'EUR'
    END AS currency,
    DATEADD(DAY, -(n * 3 + 100), GETDATE()) AS opened_date,
    CAST(ABS(CHECKSUM(NEWID())) % 50000 + 500 AS DECIMAL(18,2)) AS balance,
    CASE WHEN n % 4 = 2 THEN CAST((ABS(CHECKSUM(NEWID())) % 10000 + 1000) AS DECIMAL(18,2)) ELSE NULL END AS credit_limit,
    CASE WHEN n % 20 = 0 THEN 0 ELSE 1 END AS is_active
FROM nums;
GO

-- Add second accounts for some customers
WITH nums AS (
    SELECT TOP 500 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects a CROSS JOIN sys.objects b
)
INSERT INTO accounts
SELECT
    2000 + n AS account_id,
    n * 4 AS customer_id,
    CASE (n % 2) WHEN 0 THEN 'Savings' ELSE 'Credit' END AS account_type,
    'GEL' AS currency,
    DATEADD(DAY, -(n * 2 + 50), GETDATE()) AS opened_date,
    CAST(ABS(CHECKSUM(NEWID())) % 20000 + 1000 AS DECIMAL(18,2)) AS balance,
    NULL AS credit_limit,
    1 AS is_active
FROM nums
WHERE n * 4 <= 2000;
GO

-- ============================================
-- TABLE 4: LOANS
-- ============================================
CREATE TABLE loans (
    loan_id             INT PRIMARY KEY,
    customer_id         INT FOREIGN KEY REFERENCES customers(customer_id),
    branch_id           INT FOREIGN KEY REFERENCES branches(branch_id),
    loan_type           NVARCHAR(30),   -- Mortgage, Consumer, Auto, Business
    principal_amount    DECIMAL(18,2),
    outstanding_balance DECIMAL(18,2),
    interest_rate       DECIMAL(5,2),
    start_date          DATE,
    maturity_date       DATE,
    status              NVARCHAR(20),   -- Performing, Non-Performing, Closed
    days_past_due       INT
);
GO

WITH nums AS (
    SELECT TOP 800 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.objects a CROSS JOIN sys.objects b
)
INSERT INTO loans
SELECT
    n AS loan_id,
    (n * 2) % 2000 + 1 AS customer_id,
    (n % 5) + 1 AS branch_id,
    CASE (n % 4)
        WHEN 0 THEN 'Mortgage'
        WHEN 1 THEN 'Consumer'
        WHEN 2 THEN 'Auto'
        ELSE 'Business'
    END AS loan_type,
    CAST((ABS(CHECKSUM(NEWID())) % 90000 + 10000) AS DECIMAL(18,2)) AS principal_amount,
    CAST((ABS(CHECKSUM(NEWID())) % 80000 + 5000) AS DECIMAL(18,2)) AS outstanding_balance,
    CAST(CASE (n % 4)
        WHEN 0 THEN 8.5 + (n % 3)
        WHEN 1 THEN 18.0 + (n % 5)
        WHEN 2 THEN 12.0 + (n % 4)
        ELSE 14.0 + (n % 6)
    END AS DECIMAL(5,2)) AS interest_rate,
    DATEADD(MONTH, -(n % 24 + 1), GETDATE()) AS start_date,
    DATEADD(MONTH, (n % 240 + 12), GETDATE()) AS maturity_date,
    CASE
        WHEN n % 12 = 0 THEN 'Non-Performing'
        WHEN n % 30 = 0 THEN 'Closed'
        ELSE 'Performing'
    END AS status,
    CASE WHEN n % 12 = 0 THEN (n % 90) + 30 ELSE 0 END AS days_past_due
FROM nums;
GO

-- ============================================
-- TABLE 5: TRANSACTIONS
-- ============================================
CREATE TABLE transactions (
    transaction_id      BIGINT PRIMARY KEY,
    account_id          INT FOREIGN KEY REFERENCES accounts(account_id),
    transaction_date    DATE,
    transaction_type    NVARCHAR(30),   -- Deposit, Withdrawal, Transfer, Payment, Fee
    amount              DECIMAL(18,2),
    direction           CHAR(1),        -- D = Debit, C = Credit
    description         NVARCHAR(200),
    channel             NVARCHAR(20)    -- Branch, ATM, Online, Mobile
);
GO

-- Generate ~24 months of transactions (approx 24000 rows)
WITH months AS (
    SELECT TOP 24 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS m
    FROM sys.objects
),
accounts_sample AS (
    SELECT TOP 1000 account_id FROM accounts WHERE is_active = 1
),
combos AS (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn,
           a.account_id, m.m
    FROM accounts_sample a CROSS JOIN months m
)
INSERT INTO transactions
SELECT
    rn AS transaction_id,
    account_id,
    DATEADD(DAY, (rn % 28), DATEADD(MONTH, -(m - 1), CAST(GETDATE() AS DATE))) AS transaction_date,
    CASE (rn % 5)
        WHEN 0 THEN 'Deposit'
        WHEN 1 THEN 'Withdrawal'
        WHEN 2 THEN 'Transfer'
        WHEN 3 THEN 'Payment'
        ELSE 'Fee'
    END AS transaction_type,
    CAST(ABS(CHECKSUM(NEWID())) % 5000 + 10 AS DECIMAL(18,2)) AS amount,
    CASE WHEN rn % 5 IN (0) THEN 'C' ELSE 'D' END AS direction,
    CASE (rn % 5)
        WHEN 0 THEN 'Salary / incoming transfer'
        WHEN 1 THEN 'ATM cash withdrawal'
        WHEN 2 THEN 'Bank transfer'
        WHEN 3 THEN 'Utility / loan payment'
        ELSE 'Service fee'
    END AS description,
    CASE (rn % 4)
        WHEN 0 THEN 'Branch'
        WHEN 1 THEN 'ATM'
        WHEN 2 THEN 'Online'
        ELSE 'Mobile'
    END AS channel
FROM combos;
GO

-- ============================================
-- TABLE 6: FINANCIALS (Monthly P&L)
-- ============================================
CREATE TABLE financials (
    financial_id            INT PRIMARY KEY,
    year_month              CHAR(7),        -- YYYY-MM
    branch_id               INT FOREIGN KEY REFERENCES branches(branch_id),
    interest_income         DECIMAL(18,2),
    interest_expense        DECIMAL(18,2),
    non_interest_income     DECIMAL(18,2),
    operating_expenses      DECIMAL(18,2),
    loan_loss_provisions    DECIMAL(18,2),
    net_profit              DECIMAL(18,2),
    total_assets            DECIMAL(18,2),
    total_deposits          DECIMAL(18,2),
    total_loans             DECIMAL(18,2),
    total_equity            DECIMAL(18,2)
);
GO

WITH months AS (
    SELECT TOP 24 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS m
    FROM sys.objects
),
branches_list AS (SELECT branch_id FROM branches),
combos AS (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn,
           b.branch_id, m.m,
           FORMAT(DATEADD(MONTH, -(m-1), GETDATE()), 'yyyy-MM') AS year_month
    FROM branches_list b CROSS JOIN months m
)
INSERT INTO financials
SELECT
    rn AS financial_id,
    year_month,
    branch_id,
    CAST(80000 + (branch_id * 5000) + (rn * 200) + ABS(CHECKSUM(NEWID())) % 10000 AS DECIMAL(18,2)) AS interest_income,
    CAST(20000 + (branch_id * 1000) + ABS(CHECKSUM(NEWID())) % 5000 AS DECIMAL(18,2)) AS interest_expense,
    CAST(15000 + (branch_id * 2000) + ABS(CHECKSUM(NEWID())) % 3000 AS DECIMAL(18,2)) AS non_interest_income,
    CAST(40000 + (branch_id * 3000) + ABS(CHECKSUM(NEWID())) % 8000 AS DECIMAL(18,2)) AS operating_expenses,
    CAST(5000 + ABS(CHECKSUM(NEWID())) % 3000 AS DECIMAL(18,2)) AS loan_loss_provisions,
    CAST(25000 + (branch_id * 2000) + ABS(CHECKSUM(NEWID())) % 5000 AS DECIMAL(18,2)) AS net_profit,
    CAST(5000000 + (branch_id * 500000) + (rn * 10000) AS DECIMAL(18,2)) AS total_assets,
    CAST(3000000 + (branch_id * 300000) + (rn * 5000) AS DECIMAL(18,2)) AS total_deposits,
    CAST(2000000 + (branch_id * 200000) + (rn * 3000) AS DECIMAL(18,2)) AS total_loans,
    CAST(800000 + (branch_id * 80000) AS DECIMAL(18,2)) AS total_equity
FROM combos;
GO

-- ============================================
-- VERIFY - Quick row counts
-- ============================================
SELECT 'branches'     AS tbl, COUNT(*) AS rows FROM branches     UNION ALL
SELECT 'customers',           COUNT(*)          FROM customers    UNION ALL
SELECT 'accounts',            COUNT(*)          FROM accounts     UNION ALL
SELECT 'loans',               COUNT(*)          FROM loans        UNION ALL
SELECT 'transactions',        COUNT(*)          FROM transactions UNION ALL
SELECT 'financials',          COUNT(*)          FROM financials;
GO

PRINT 'Imaginary Bank database created successfully!';
GO
