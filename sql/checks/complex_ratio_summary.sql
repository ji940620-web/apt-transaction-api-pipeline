-- ============================================================
-- 파일: sql/checks/complex_ratio_summary.sql
-- 목적: 단지·면적대 전세가율의 분포 요약 (100% 초과 비율, 중앙값, 최댓값)
-- 입력: apt_dataset.v_sales, apt_dataset.v_rents (전세만)
-- 출력: n_pairs, over_100, over_100_pct, median_ratio, max_ratio
-- 기간: 2026-08-01 이후로 고정(하드코딩). m_complex_ratio(최근 3개월)와 시간이 지나면 달라진다.
-- 용도: docs/findings_log.md 의 '전세가율 이상치' 표 중 단지·면적 매칭 행 검증
-- 해석: 지역 중위값 비율(jeonse_ratio_distribution.sql A)보다 100% 초과 비율이 훨씬 낮으면
--       100% 초과의 원인이 거래 구성 불일치라는 근거가 된다.
-- 작성: 2026-11-16
-- ============================================================

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