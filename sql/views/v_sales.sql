CREATE OR REPLACE VIEW apt_dataset.v_sales AS
SELECT
  lawdCd                                   AS lawd_cd,
  regionName                               AS region_name,
  umdNm                                    AS umd_nm,
  aptNm                                    AS apt_nm,
  CONCAT(CAST(lawdCd AS STRING), '|', umdNm, '|', aptNm) AS complex_key,
  DATE(dealYear, dealMonth, dealDay)       AS deal_date,
  DATE(dealYear, dealMonth, 1)             AS deal_month,
  dealAmount                               AS price,          -- 만원
  excluUseAr                               AS area_m2,
  ROUND(excluUseAr / 3.3058, 1)            AS area_py,
  SAFE_DIVIDE(dealAmount, excluUseAr / 3.3058) AS price_per_py,
  floor,
  buildYear                                AS build_year,
  dealYear - buildYear                     AS building_age
FROM apt_dataset.transaction_raw
WHERE dealAmount > 0
  AND excluUseAr > 0
  AND DATE(dealYear, dealMonth, 1) < DATE_TRUNC(CURRENT_DATE('Asia/Seoul'), MONTH);