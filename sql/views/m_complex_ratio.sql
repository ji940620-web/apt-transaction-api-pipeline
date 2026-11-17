-- ============================================================
-- 파일: sql/views/m_complex_ratio.sql
-- 목적: 단지 x 면적대 단위 전세가율 (같은 단지·같은 면적대끼리 매칭)
-- 입력: apt_dataset.v_sales, apt_dataset.v_rents (전세만)
-- 출력: region_name, complex_key, area_band, sale_n, jeonse_n, sale_median,
--       jeonse_median, jeonse_ratio_pct, is_over_100
-- 기간: 최근 3개월 (당월 제외). 2026-11-16 기준 2026-08 ~ 2026-10
-- 기준: 매매·전세 각각 3건 이상인 단지·면적대만 포함. 면적대 = 전용면적을 5㎡ 단위로 반올림
-- 주의: - v_sales 를 사용하므로 일괄 거래(is_bulk)가 포함된다.
--       - 면적대 기준이 lk_deals(5㎡ 단위 내림)와 다르다.
-- 작성: 2026-11-16
-- ============================================================

CREATE OR REPLACE VIEW apt_dataset.m_complex_ratio AS
WITH s AS (
  SELECT region_name, complex_key,
         CAST(ROUND(area_m2/5)*5 AS INT64) AS area_band,
         APPROX_QUANTILES(price, 100)[OFFSET(50)] AS sale_median,
         COUNT(*) AS sale_n
  FROM apt_dataset.v_sales
  WHERE deal_month >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('Asia/Seoul'), MONTH), INTERVAL 3 MONTH)
  GROUP BY 1, 2, 3
),
j AS (
  SELECT region_name, complex_key,
         CAST(ROUND(area_m2/5)*5 AS INT64) AS area_band,
         APPROX_QUANTILES(deposit, 100)[OFFSET(50)] AS jeonse_median,
         COUNT(*) AS jeonse_n
  FROM apt_dataset.v_rents
  WHERE rent_type = '전세'
    AND deal_month >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('Asia/Seoul'), MONTH), INTERVAL 3 MONTH)
  GROUP BY 1, 2, 3
)
SELECT
  s.region_name, s.complex_key, s.area_band,
  s.sale_n, j.jeonse_n, s.sale_median, j.jeonse_median,
  ROUND(SAFE_DIVIDE(j.jeonse_median, s.sale_median) * 100, 1) AS jeonse_ratio_pct,
  SAFE_DIVIDE(j.jeonse_median, s.sale_median) > 1 AS is_over_100
FROM s JOIN j USING (region_name, complex_key, area_band)
WHERE s.sale_n >= 3 AND j.jeonse_n >= 3;