-- A) 전세가율 분포: 표본 충분한 행만
SELECT
  COUNT(*) AS rows_ok,
  ROUND(MIN(jeonse_ratio_pct),1) AS min_ratio,
  APPROX_QUANTILES(jeonse_ratio_pct, 100)[OFFSET(50)] AS median_ratio,
  ROUND(MAX(jeonse_ratio_pct),1) AS max_ratio,
  COUNTIF(jeonse_ratio_pct > 100) AS over_100
FROM apt_dataset.m_region_monthly
WHERE enough_sample;

-- B) 최근 월(2026-10) 전세가율 상위 지역
SELECT region_name, sale_n, jeonse_n, sale_median, jeonse_median, jeonse_ratio_pct
FROM apt_dataset.m_region_monthly
WHERE deal_month = DATE '2026-10-01' AND enough_sample
ORDER BY jeonse_ratio_pct DESC
LIMIT 15;