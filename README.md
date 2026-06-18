# GA4-e-commerce-user-analysis
This project explores 3 months of session-level event data from the Google Merchandise Store using the public GA4 obfuscated sample dataset on BigQuery. The goal: trace where users drop off in the conversion funnel, test whether marketing channels and device types meaningfully differ in conversion behavior, and measure cohort retention week-by-week
These analytical patterns — funnel conversion, channel attribution, cohort retention, device-segmented conversion testing — are the daily work of analysts at iGaming, e-commerce, and SaaS companies. iGaming operators don't publish behavioral data, but the SQL techniques (`UNNEST` of event arrays, struct field access, session-level metrics) and statistical methods (proportion z-tests, chi-square independence) translate 1:1 from this e-commerce sample to a sportsbook or casino analytics environment.

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

The SQL is organized around four diagnostic questions. Two of the four are paired with statistical tests in the accompanying Python notebook.

### Q1 — Where do users drop off in the conversion funnel?

Maps the full conversion funnel from `session_start` → `view_item` → `add_to_cart` → `begin_checkout` → `purchase`, with step-by-step and cumulative conversion rates.

**Key findings:**

- **Only 1.65% of sessions end in a purchase** — out of every 100 visitors, fewer than 2 buy something.
- **The biggest leak is at the top of the funnel** — only 22.9% of users who started a session went on to view a product. 77% never even browsed.
- **Mid-funnel conversion is surprisingly healthy** — once users add an item to cart, 77.4% begin checkout, and 45.5% of those complete the purchase. The leak isn't checkout abandonment; it's getting users engaged in the first place.

### Q2 — Which acquisition channel converts best?

Groups sessions by GA4 default channel groupings (Direct, Organic Search, Paid Search, Referral, Unassigned), with conversion rate per channel and a statistical test on the top two channels.

**Methodology note:** GA4's `(data deleted)` rows (anonymization placeholders for redacted user data) were excluded — they don't represent real channels.

**Key findings:**

- **Referral traffic is the highest-converting channel at 1.67%**, dominated by visitors from `shop.googlemerchandisestore.com` — a partner property delivering high-intent traffic.
- **Direct traffic converts slightly better than Organic Search** (1.30% vs 1.11%) — a 0.18 pp absolute gap, or ~16% in relative terms.
- **Paid search underperforms organic** (0.98% vs 1.11%) — typical pattern where paid clicks skew toward top-of-funnel browsing while organic captures users who already have search intent.

**Statistical test:** Two-proportion z-test on Direct vs Organic Search conversion rates.

- **H₀:** rate(Direct) = rate(Organic) | **H₁:** they differ | **α** = 0.05
- **Result:** z = -3.64, p < 0.001 → **reject H₀**
- The 0.18 pp gap is statistically reliable despite being small, because the combined sample is ~194K sessions — large enough to detect even modest differences. An honest "statistically significant but practically modest" finding.

### Q3 — Cohort retention: do users come back?

Tracks weekly retention for each acquisition cohort — what fraction of users from each cohort return in each subsequent week.

**Key findings:**

- **Average Week 1 retention is ~4%** across all cohorts — roughly 96% of new users never return after their first visit.
- **Retention isn't uniform across the period** — November cohorts retained ~6% at Week 1, while December and January cohorts dropped to ~3%. A roughly 50% relative decline.
- **The November-to-December shift coincides with the holiday shopping season**, suggesting later traffic may have lower repeat intent (gift-buyers, post-holiday browsers). The pattern is consistent across multiple weekly cohorts, so it's structural rather than random noise.
- **By Week 4 onward, retention settles below 1%** across all cohorts — a small "loyal core" of repeat visitors that's stable but tiny.

### Q4 — Does device type affect conversion?

Compares conversion rate and average purchase value across device types (desktop, mobile, tablet), with a chi-square test of independence.

**Key findings:**

- **Conversion rates across devices are very close:** Mobile 1.41%, Desktop 1.34%, Tablet 1.30%.
- **Desktop has the highest average purchase value** ($75.96), while Mobile drives more frequent but smaller purchases ($73.57) — the classic mobile-vs-desktop pattern of higher frequency at lower per-transaction value.

**Statistical test:** Chi-square test of independence on the device × purchase contingency table.

- **H₀:** device type and purchase are independent | **H₁:** they differ | **α** = 0.05
- **Result:** χ² = 3.48, p = 0.18 → **fail to reject H₀**
- The differences in conversion rate look real on the surface (mobile leads by 0.11 pp), but the gaps are small enough to be plausibly explained by random variation. Despite ~355K total sessions, the spread isn't large enough to reach statistical significance. For this dataset, device choice doesn't meaningfully predict whether a session ends in a purchase.

## Limitations

- **Short time window.** The dataset covers only 3 months. Seasonal patterns (Q1 spring, mid-year sales cycles, year-over-year comparisons) cannot be observed within this scope.
- **Obfuscated sample data.** Some channel sources are aggregated as `<Other>` and some user identifiers have been redacted (`(data deleted)` rows). This limits the granularity of channel attribution and may slightly distort some findings.
- **Huge sample size affects the statistics.** With ~355K sessions, statistical tests will flag small differences as significant. Both findings in this project hold up — Q2's z-test rejects because the effect is real even though the gap is small, and Q4's chi-square correctly fails to reject because the device-level spread is tighter than the test's sensitivity threshold. A smaller dataset might produce different conclusions.
- **Single-source data.** GA4 captures only what's measurable through Google's tracking — it doesn't include marketing spend, A/B test variants, customer support contacts, or competitor benchmarks. Findings describe behavior, not causes.
