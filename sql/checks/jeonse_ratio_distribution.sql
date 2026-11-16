-- ============================================================
-- 파일: sql/checks/jeonse_ratio_distribution.sql
-- 목적: 지역 단위 전세가율 분포 점검 (이상치와 상위 지역 확인)
-- 입력: apt_dataset.m_region_monthly
-- 출력: A) 표본 충분한 행의 건수·최소·중앙값·최대·100% 초과 건수
--       B) 최근 월(2026-10) 전세가율 상위 15개 지역
-- 용도: docs/findings_log.md 의 '전세가율 이상치' 표 중 지역 중위값 행 검증
-- 주의: B 의 월(2026-10-01)은 고정값이라 월이 바뀌면 직접 수정해야 한다.
-- 작성: 2026-11-16 (주석 추가)
-- ============================================================

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