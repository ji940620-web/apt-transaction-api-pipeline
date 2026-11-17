-- ============================================================
-- 파일: sql/checks/monthly_count_mom.sql
-- 목적: 월별 매매 거래 건수와 전월 대비 증감률 (거래량 추이 점검)
-- 입력: apt_dataset.v_sales (일괄 거래 포함)
-- 출력: deal_month, n(건수), mom_change(전월 대비 증감률)
-- 주의: - 첫 달(2025-01)은 수집 시작월이라 부분 데이터이므로 증감률 해석에 주의.
--       - 최근 1-2개월은 신고 지연으로 잠정치(30일 이내 신고).
-- 작성: 2026-11-16
-- ============================================================

SELECT
  deal_month,
  COUNT(*) AS n,
  ROUND(SAFE_DIVIDE(COUNT(*), LAG(COUNT(*)) OVER (ORDER BY deal_month)) - 1, 3) AS mom_change
FROM apt_dataset.v_sales
GROUP BY deal_month
ORDER BY deal_month;