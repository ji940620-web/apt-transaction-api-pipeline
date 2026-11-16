-- ============================================================
-- 파일: sql/views/v_rents.sql
-- 목적: 전월세 원천(rent_raw)을 분석용 컬럼명으로 정제한 기본 뷰
-- 입력: apt_dataset.rent_raw
-- 출력: lawd_cd, region_name, umd_nm, apt_nm, complex_key, deal_date, deal_month,
--       rent_type(월세 0이면 '전세', 아니면 '월세'), deposit(만원), monthly_rent(만원),
--       area_m2, area_py, floor, build_year
-- 제외: 전용면적 0 이하, 보증금 음수, 진행 중인 당월
-- 주의: 일괄 거래 표시는 매매(v_sales_clean)에만 있다. 전세·월세 모두 보증금은 deposit 컬럼.
-- 작성: 2026-11-16 (주석 추가)
-- ============================================================

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