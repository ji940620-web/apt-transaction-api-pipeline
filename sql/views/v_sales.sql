-- ============================================================
-- 파일: sql/views/v_sales.sql
-- 목적: 매매 원천(transaction_raw)을 분석용 컬럼명과 파생 컬럼으로 정제한 기본 뷰
-- 입력: apt_dataset.transaction_raw
-- 출력: lawd_cd, region_name, umd_nm, apt_nm, complex_key(법정동코드|동|단지명),
--       deal_date, deal_month, price(만원), area_m2, area_py, price_per_py(만원/평),
--       floor, build_year, building_age(거래연도 - 건축연도)
-- 제외: 금액·전용면적이 0 이하인 행, 진행 중인 당월(신고가 덜 들어온 달)
-- 주의: 일괄 거래는 표시되지 않는다 (is_bulk 는 v_sales_clean 에서 추가).
--       평 환산은 1평 = 3.3058㎡ 기준.
-- 작성: 2026-11-16
-- ============================================================

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