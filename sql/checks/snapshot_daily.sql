-- ============================================================
-- 파일: sql/checks/snapshot_daily.sql
-- 목적: 특정 시점의 일자별 매매 건수를 테이블로 고정(스냅샷)
-- 이유: 뷰는 재수집하면 결과가 바뀌므로, 재수집 전 값을 따로 보관해야
--       신고 지연으로 건수가 얼마나 늘었는지 전후 비교가 가능하다.
-- 내용: 2026-08 이후, 일괄 거래 제외, 서울/서울 외 구분 (deal_date, is_seoul, n)
--
-- [날짜 규칙] snap_daily_YYYYMMDD 의 날짜 = 스냅샷 테이블을 만든 날짜 (수집일이 아님)
--
-- [스냅샷 이력]
--   snap_daily_20261110  생성 2026-11-10 / 11/5 수집분 반영 (재수집 전)  <- 비교 기준(baseline)
--   snap_daily_20261111  생성 2026-11-11 / 11/11 재수집 직후
--   2026-11-16 비교는 스냅샷 없이, 현재 v_sales_clean 을 baseline(20261110)과 직접 비교
--
-- [사용법] 아래 CREATE TABLE 의 날짜(YYYYMMDD)를 실행하는 날짜로 바꿔 한 번만 실행한다.
--          (이 파일에 적힌 날짜는 마지막으로 만든 스냅샷: 20261111)
-- [비교]   재수집 후 docs/findings_log.md 의 비교 쿼리를 실행한다 (쿼리 안의 snap_daily 날짜도 확인).
-- [주의]   같은 날짜 테이블은 한 번만 생성한다. 다시 실행하면 "이미 존재" 오류가 난다 (덮어쓰기 방지).
--          스냅샷 테이블은 삭제하지 않는다.
-- 작성: 2026-11-10 / 수정: 2026-11-16 (날짜 규칙·이력 정리)
-- ============================================================

CREATE TABLE apt_dataset.snap_daily_20261111 AS
SELECT
  CURRENT_TIMESTAMP() AS snapshot_at,
  deal_date,
  STARTS_WITH(region_name, '서울') AS is_seoul,
  COUNT(*) AS n
FROM apt_dataset.v_sales_clean
WHERE deal_month >= DATE '2026-08-01' AND NOT is_bulk
GROUP BY deal_date, is_seoul;