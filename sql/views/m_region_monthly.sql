CREATE OR REPLACE VIEW apt_dataset.m_region_monthly AS
WITH sales AS (
  SELECT region_name, deal_month,
         COUNT(*) AS sale_n,
         APPROX_QUANTILES(price, 100)[OFFSET(50)] AS sale_median
  FROM apt_dataset.v_sales
  WHERE deal_month >= DATE '2025-02-01'
  GROUP BY region_name, deal_month
),
jeonse AS (
  SELECT region_name, deal_month,
         COUNT(*) AS jeonse_n,
         APPROX_QUANTILES(deposit, 100)[OFFSET(50)] AS jeonse_median
  FROM apt_dataset.v_rents
  WHERE rent_type = '전세' AND deal_month >= DATE '2025-02-01'
  GROUP BY region_name, deal_month
)
SELECT
  s.region_name, s.deal_month,
  s.sale_n, s.sale_median,
  j.jeonse_n, j.jeonse_median,
  ROUND(SAFE_DIVIDE(j.jeonse_median, s.sale_median) * 100, 1) AS jeonse_ratio_pct,
  (s.sale_n >= 30 AND j.jeonse_n >= 30) AS enough_sample
FROM sales s
LEFT JOIN jeonse j USING (region_name, deal_month);