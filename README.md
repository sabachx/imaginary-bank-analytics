# Imaginary Bank Analytics: CFO/CEO Dashboard Pipeline

## 📌 Project Overview
This project simulates an enterprise-grade financial analytics pipeline for a multi-national commercial bank. It transforms raw financial ledger data into a comprehensive Executive Dashboard designed for the C-Suite. The core objective is to automate Profit & Loss (P&L) reporting, track Balance Sheet metrics, and perform dynamic Actual vs. Budget variance analysis across multiple currencies and business units.

## 💼 Business Value & Problem Solved
In enterprise banking, financial reporting is often bottlenecked by manual Excel consolidation, static exchange rates, and disconnected budget scenarios. This solution provides:
* **Automated Financial Statements:** Dynamic generation of hierarchical P&L and Balance Sheets using parent-child data modeling.
* **Scenario Variance Analysis:** Instant comparison between Actuals, multi-year Budgets (Top-Down & Bottom-Up), and Rolling Forecasts.
* **FX Risk Management:** Built-in multi-currency handling (EUR, USD, GBP) using both End-of-Month and Daily Average exchange rates.
* **Granular Profitability:** Drill-down capabilities from top-level Net Income down to specific channels (e.g., Paris Flagship) and segments (e.g., Private Banking).

## 🛠️ Technical Architecture & Data Stack
* **Database Engine:** SQL Server
* **Data Modeling:** Kimball Star Schema (1 Fact Table, 7 Dimension Tables)
* **Data Visualization & Logic:** Power BI / DAX
* **Key Techniques Demonstrated:** Ragged hierarchy handling (Chart of Accounts), dynamic currency conversion via Field Parameters, complex DAX time-intelligence, and scenario-based waterfall visualizations.
