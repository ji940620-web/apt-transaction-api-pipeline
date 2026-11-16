-- ============================================================
-- 파일: sql/views/m_sido_monthly.sql
-- 목적: 시도별 월별 거래량과 가격 추이 (대시보드용 마트)
-- 입력: apt_dataset.v_sales_clean
-- 출력: sido, deal_month, trades_all(전체 건수), trades_clean(일괄 제외 건수),
--       median_price_clean(일괄 제외 중위 거래가, 만원),
--       median_price_per_py(일괄 제외 중위 평당가, 만원, 전용면적 기준)
-- 기간: 2025-02 이후 (2025-01은 수집 시작월이라 부분 데이터여서 제외)
-- 주의: - 총액 중위가는 평형 구성에 흔들리므로 추이는 평당가 기준으로 본다.
--       - 시도 단위 중위값도 지역 구성의 영향을 받는 "참고 지표"다.
--       - 최근 1~2개월은 신고 지연으로 잠정치 (30일 이내 신고).
-- 작성: 2026-11-10
-- ============================================================
CREATE OR REPLACE VIEW apt_dataset.m_sido_monthly AS
SELECT
  SPLIT(region_name, ' ')[OFFSET(0)] AS sido,
  deal_month,
  COUNT(*) AS trades_all,
  COUNTIF(NOT is_bulk) AS trades_clean,
  APPROX_QUANTILES(IF(NOT is_bulk, price, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_price_clean,
  ROUND(APPROX_QUANTILES(IF(NOT is_bulk, price_per_py, NULL), 100 IGNORE NULLS)[OFFSET(50)]) AS median_price_per_py
FROM apt_dataset.v_sales_clean
WHERE deal_month >= DATE '2025-02-01'
GROUP BY sido, deal_month;

