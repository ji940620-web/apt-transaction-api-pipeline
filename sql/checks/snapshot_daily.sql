-- ============================================================
-- 파일: sql/checks/snapshot_daily.sql
-- 목적: 특정 시점의 일자별 매매 건수를 테이블로 고정 (스냅샷)
-- 이유: 뷰는 재수집 후 결과가 바뀌므로, "재수집 전" 값을 따로 보관해야
--       신고 지연으로 건수가 얼마나 늘었는지 전후 비교가 가능하다.
-- 데이터: 2026-08 이후, 일괄 거래 제외, 서울/서울 외 구분
-- 사용법: 실행할 때마다 아래 테이블명의 날짜(YYYYMMDD)를 오늘 날짜로 바꿔서 실행
-- 비교: 재수집 후 docs/findings_log.md 의 비교 쿼리 실행
--       (비교 쿼리의 snap_daily_날짜 테이블명도 함께 변경)
-- 주의: - 같은 날짜 테이블은 한 번만 실행한다. 다시 실행하면 "이미 존재" 오류가 난다 (덮어쓰기 방지 의도).
--       - 스냅샷 테이블은 삭제하지 않는다.
-- 이력: snap_daily_20261110 (11/5 수집분 기준, 최초 생성)
--       snap_daily_20261111 (11/11 재수집 직후)
-- 작성: 2026-11-10
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