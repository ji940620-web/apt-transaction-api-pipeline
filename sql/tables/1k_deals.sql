-- ============================================================
-- 파일: sql/tables/lk_deals.sql
-- 목적: Looker Studio용 거래 단위 테이블 (매매·전세·월세 통합, 1행 = 1거래)
-- 이유: 중앙값은 미리 집계하면 지역별로 다시 합칠 수 없어서,
--       거래 단위로 두고 Looker에서 MEDIAN()으로 계산한다.
-- 금액: 매매 = 매매가, 전세·월세 = 보증금 (단위: 만원). 월세만 monthly_rent 값이 있다.
-- 일괄 거래: 매매에만 적용(is_bulk). 전세·월세는 항상 FALSE.
-- 갱신: 테이블이므로 데이터 수집 후 다시 실행해야 최신이 된다 (매주 월요일 수집 뒤).
-- 입력: apt_dataset.v_sales_clean, apt_dataset.v_rents
-- 작성: 2026-11-11
-- ============================================================
CREATE OR REPLACE TABLE apt_dataset.lk_deals
PARTITION BY deal_month
CLUSTER BY deal_type, sido, sigungu
AS
WITH base AS (
  SELECT
    '매매' AS deal_type, deal_date, deal_month, region_name, umd_nm, apt_nm, complex_key,
    area_m2, CAST(price AS FLOAT64) AS amount, CAST(NULL AS FLOAT64) AS monthly_rent,
    SAFE_CAST(floor AS INT64) AS floor, SAFE_CAST(build_year AS INT64) AS build_year,
    is_bulk
  FROM apt_dataset.v_sales_clean
  UNION ALL
  SELECT
    rent_type, deal_date, deal_month, region_name, umd_nm, apt_nm, complex_key,
    area_m2, CAST(deposit AS FLOAT64),
    IF(rent_type = '월세', CAST(monthly_rent AS FLOAT64), NULL),
    SAFE_CAST(floor AS INT64), SAFE_CAST(build_year AS INT64),
    FALSE
  FROM apt_dataset.v_rents
)
SELECT
  deal_type, deal_date, deal_month,
  SPLIT(region_name, ' ')[OFFSET(0)] AS sido,
  REGEXP_REPLACE(region_name, r'^\S+\s+', '') AS sigungu,
  umd_nm AS dong,
  apt_nm,
  CONCAT(complex_key, '|', CAST(CAST(FLOOR(area_m2 / 5) * 5 AS INT64) AS STRING)) AS complex_area_key,
  area_m2,
  CAST(FLOOR(area_m2 / 5) * 5 AS INT64) AS area_band,
  CONCAT(CAST(CAST(FLOOR(area_m2 / 5) * 5 AS INT64) AS STRING), '~',
         CAST(CAST(FLOOR(area_m2 / 5) * 5 + 5 AS INT64) AS STRING), '㎡') AS area_label,
  amount,
  monthly_rent,
  SAFE_DIVIDE(amount, area_m2 / 3.3058) AS amount_per_py,
  CASE
    WHEN amount < 30000  THEN '1) 3억 미만'
    WHEN amount < 50000  THEN '2) 3~5억'
    WHEN amount < 70000  THEN '3) 5~7억'
    WHEN amount < 100000 THEN '4) 7~10억'
    WHEN amount < 150000 THEN '5) 10~15억'
    ELSE '6) 15억 이상'
  END AS amount_band,
  floor, build_year,
  is_bulk,
  IF(is_bulk, '일괄 거래', '일반 거래') AS bulk_label
FROM base;