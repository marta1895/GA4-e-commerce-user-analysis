# GA4-e-commerce-user-analysis
This project explores 3 months of session-level data from the Google Merchandise Store using the public GA4 sample dataset on BigQuery. I wanted to look at where users drop off in the conversion funnel, whether marketing channels and device types really differ in how they convert, and how many users come back week after week.


## Dashboard preview

<img width="2804" height="1950" alt="image" src="https://github.com/user-attachments/assets/c448804b-726c-4f65-b5f0-c7cac94f0bb6" />


**[View the interactive dashboard on Tableau Public](https://public.tableau.com/views/GA4Analytics_17817907782290/GA4Analytics)**

## Data

**Source:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` — obfuscated session-level event data from Google's own merchandise store, exported to BigQuery in standard GA4 format.

**Scope:** ~355K sessions from ~268K unique users, covering the full extent of the public sample (November 1, 2020 – January 31, 2021 — approximately 3 months).

**What this data represents:** GA4 captures every user event on the site (page views, product views, add-to-cart, checkout begins, purchases) as a row, with rich nested attributes (event parameters, item details, device, traffic source) stored as ARRAY<STRUCT> fields. Each row has a user pseudo ID, a session ID hidden inside the `event_params` array, a traffic source struct, and a device category. Working with this data requires comfort with BigQuery's nested-field handling.

## Tech stack

- **BigQuery SQL** — `UNNEST` of nested event arrays, scalar subqueries for struct field extraction, window functions, cost-aware querying on a wildcard-partitioned dataset
- **Python** (pandas, scipy.stats, statsmodels) — statistical tests on query outputs (two-proportion z-test, chi-square test of independence)
- **Tableau Desktop / Public** — interactive dashboard with KPI tiles, retention curve, cohort bars, funnel chart, channel table, and device breakdowns

## Repository structure

```
ga4-ecommerce-analysis/
├── README.md
├── ga4_analysis.sql                # BigQuery: all analytical queries
├── ga4_stat_test.ipynb             # Python: z-test + chi-square notebooks
├── GA4 Analytics.twbx              # Tableau workbook
├── dashboard.png                   # Dashboard screenshot
└── data/
    ├── kpi_ga4.csv                 # Dashboard KPI metrics
    ├── ga4_q1.csv                  # Q1 funnel results
    ├── ga4_q2.csv                  # Q2 channel results
    ├── 03_cohort_retention.csv     # Q3 cohort retention
    └── ga4_q4.csv                  # Q4 device results
```

## Analysis

The SQL covers four questions. Two of them have a statistical test in the Python notebook.

### Q1 — Where do users drop off in the conversion funnel?

Maps the full conversion funnel from `session_start` → `view_item` → `add_to_cart` → `begin_checkout` → `purchase`, with step-by-step and cumulative conversion rates.

**Key findings:**

- **Only 1.65% of sessions end in a purchase** — out of every 100 visitors, fewer than 2 buy something.
- **The biggest leak is at the top of the funnel** — only 22.9% of users who started a session went on to view a product. 77% never even browsed.
- **Mid-funnel conversion is surprisingly healthy** — once users add an item to cart, 77.4% begin checkout, and 45.5% of those complete the purchase. The leak isn't checkout abandonment; it's getting users engaged in the first place.

### Q2 — Which acquisition channel converts best?

Groups sessions by GA4 default channel groupings (Direct, Organic Search, Paid Search, Referral, Unassigned), with conversion rate per channel and a statistical test on the top two channels.

**Methodology note:** GA4's `(data deleted)` rows (anonymization placeholders for redacted user data) were excluded, as they don't represent real channels.

**Key findings:**

- **Referrals convert the best at 1.67%**, mostly from `shop.googlemerchandisestore.com`, a related Google site, so those visitors already know what they're shopping for.
- **Direct traffic converts slightly better than Organic Search (1.30% vs 1.11%)** The gap looks tiny, just 0.18 percentage points, but it's about 16% better in relative terms
- **Paid search converts worse than organic (0.98% vs 1.11%)** That's a common pattern: paid clicks usually bring people who are still browsing, while organic search brings people who already know what they're looking for.

**Statistical test:** Two-proportion z-test on Direct vs Organic Search conversion rates.

- **H₀:** rate(Direct) = rate(Organic) | **H₁:** they differ | **α** = 0.05
- **Result:** z = -3.64, p < 0.001 → **reject H₀**
- The gap is small (just 0.18 pp), but with about 194K sessions in the test, even tiny differences show up as statistically real. So the difference is genuine, direct really does convert better, but it's still a small one.

### Q3 — Cohort retention: do users come back?

Groups users by the week they first showed up, then tracks how many come back in each later week.

**Key findings:**

- **Average Week 1 retention is ~4%** across all cohorts, roughly 96% of new users never return after their first visit.
- **Retention wasn't steady across the period** November groups kept about 6% of users at Week 1, but December and January groups dropped to around 3%. Roughly half as many users came back.
- **The drop lines up with the holiday shopping season**. Later visitors were probably gift-buyers and post-holiday browsers, who don't tend to come back. The same pattern shows up across multiple weeks, so it's a real shift, not random noise.
- **By Week 4 onward, retention settles below 1%** across all cohorts. It's a small "loyal core" of repeat visitors that's stable but tiny.

### Q4 — Does device type affect conversion?

Compares conversion rate and average purchase value across device types (desktop, mobile, tablet), with a chi-square test of independence.

**Key findings:**

- **Conversion rates across devices are very close:** Mobile 1.41%, Desktop 1.34%, Tablet 1.30%.
- **Desktop has the highest average purchase value** ($75.96), while Mobile drives more frequent but smaller purchases ($73.57), the usual pattern where mobile shoppers buy more often but spend a little less each time.

**Statistical test:** Chi-square test of independence on the device × purchase contingency table.

- **H₀:** device type and purchase are independent | **H₁:** they differ | **α** = 0.05
- **Result:** χ² = 3.48, p = 0.18 → **fail to reject H₀**
- On the surface, mobile looks like it converts a little better (by 0.11 pp), but the gaps are small enough that they could easily be random. Even with ~355K sessions, the test couldn't find a real difference between devices. For this dataset, device type doesn't really tell you whether a session will end in a purchase.

## Limitations

- **Short time window.** The dataset covers only 3 months. Seasonal patterns (Q1 spring, mid-year sales cycles, year-over-year comparisons) cannot be observed within this scope.
- **Obfuscated sample data.** Some channel sources are aggregated as `<Other>` and some user identifiers have been redacted (`(data deleted)` rows). This limits the granularity of channel attribution and may throw some of the numbers off slightly.
- **Huge sample size affects the statistics.** With ~355K sessions, the tests can pick up even small differences as "real." Both findings still hold up: Q2 found a real (if small) gap between channels, and Q4 correctly found no real gap between devices. With less data, the same tests might land differently.
- **Single-source data.** GA4 only sees what happens on the site; it doesn't include marketing spend, A/B test variants, customer support contacts, or what competitors are doing. The findings show behavior, not what caused it.
