CREATE OR REPLACE VIEW apt_dataset.v_rents AS
SELECT
  lawdCd                                   AS lawd_cd,
  regionName                               AS region_name,
  umdNm                                    AS umd_nm,
  aptNm                                    AS apt_nm,
  CONCAT(CAST(lawdCd AS STRING), '|', umdNm, '|', aptNm) AS complex_key,
  DATE(dealYear, dealMonth, dealDay)       AS deal_date,
  DATE(dealYear, dealMonth, 1)             AS deal_month,
  IF(monthlyRent = 0, '전세', '월세')        AS rent_type,
  deposit,                                                    -- 만원
  monthlyRent                              AS monthly_rent,   -- 만원
  excluUseAr                               AS area_m2,
  ROUND(excluUseAr / 3.3058, 1)            AS area_py,
  floor,
  buildYear                                AS build_year
FROM apt_dataset.rent_raw
WHERE excluUseAr > 0
  AND deposit >= 0
  AND DATE(dealYear, dealMonth, 1) < DATE_TRUNC(CURRENT_DATE('Asia/Seoul'), MONTH);