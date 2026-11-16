WITH s AS (
  SELECT region_name, complex_key,
         CAST(ROUND(area_m2/5)*5 AS INT64) AS area_band,
         APPROX_QUANTILES(price, 100)[OFFSET(50)] AS sale_median,
         COUNT(*) AS sale_n
  FROM apt_dataset.v_sales
  WHERE deal_month >= DATE '2026-08-01'
  GROUP BY 1, 2, 3
),
j AS (
  SELECT region_name, complex_key,
         CAST(ROUND(area_m2/5)*5 AS INT64) AS area_band,
         APPROX_QUANTILES(deposit, 100)[OFFSET(50)] AS jeonse_median,
         COUNT(*) AS jeonse_n
  FROM apt_dataset.v_rents
  WHERE rent_type = '전세' AND deal_month >= DATE '2026-08-01'
  GROUP BY 1, 2, 3
),
pairs AS (
  SELECT s.region_name, s.complex_key, s.area_band,
         s.sale_n, j.jeonse_n, s.sale_median, j.jeonse_median,
         ROUND(SAFE_DIVIDE(j.jeonse_median, s.sale_median) * 100, 1) AS jeonse_ratio_pct
  FROM s JOIN j USING (region_name, complex_key, area_band)
  WHERE s.sale_n >= 3 AND j.jeonse_n >= 3
)
SELECT
  COUNT(*) AS n_pairs,
  COUNTIF(jeonse_ratio_pct > 100) AS over_100,
  ROUND(COUNTIF(jeonse_ratio_pct > 100) / COUNT(*) * 100, 1) AS over_100_pct,
  APPROX_QUANTILES(jeonse_ratio_pct, 100)[OFFSET(50)] AS median_ratio,
  MAX(jeonse_ratio_pct) AS max_ratio
FROM pairs;