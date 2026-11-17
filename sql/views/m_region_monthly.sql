-- ============================================================
-- 파일: sql/views/m_region_monthly.sql
-- 목적: 시군구 x 월 단위 매매·전세 중위값과 전세가율 (지역 단위 마트)
-- 입력: apt_dataset.v_sales, apt_dataset.v_rents (전세만)
-- 출력: region_name, deal_month, sale_n, sale_median, jeonse_n, jeonse_median,
--       jeonse_ratio_pct(전세 중위값 / 매매 중위값 x 100), enough_sample
-- 기간: 2025-02 이후 (2025-01 은 수집 시작월이라 부분 데이터)
-- 기준: enough_sample = 매매·전세 각각 30건 이상인 지역·월
-- 주의: - v_sales 를 사용하므로 일괄 거래(is_bulk)가 포함된다.
--       - 지역 중위값끼리 나눈 비율이라 거래 구성(단지·면적) 차이로 100% 를 넘을 수 있다.
--         단지 단위 비교는 m_complex_ratio 를 쓴다.
--       - 중위값은 APPROX_QUANTILES 근사값.
-- 작성: 2026-11-16
-- ============================================================

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