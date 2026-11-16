-- ============================================================
-- 파일: sql/views/m_sido_pace.sql
-- 목적: 월 안에서 구간별(월초/중순/월말) 일평균 거래 건수 (신고 지연 점검용)
-- 입력: apt_dataset.v_sales_clean (일괄 거래 제외)
-- 출력: sido, deal_month, avg_d01_10, avg_d11_20, avg_d21_end (일평균, 건)
-- 사용: - 신고가 끝난 월은 월말이 월초의 약 0.88배 (서울, 2026-06~08 기준)
--       - 최근 월의 월말 비율이 이보다 훨씬 낮으면 신고 지연으로 판단
--       - 월초 10일(avg_d01_10)이 신고 지연에 강해 최근 월 비교에 적합
-- 주의: 일요일·공휴일(예: 추석)은 건수가 낮아 구간 평균에 영향을 줄 수 있다.
-- 작성: 2026-11-10
-- ============================================================
CREATE OR REPLACE VIEW apt_dataset.m_sido_pace AS
SELECT
  SPLIT(region_name, ' ')[OFFSET(0)] AS sido,
  deal_month,
  ROUND(COUNTIF(EXTRACT(DAY FROM deal_date) <= 10) / 10, 1) AS avg_d01_10,
  ROUND(COUNTIF(EXTRACT(DAY FROM deal_date) BETWEEN 11 AND 20) / 10, 1) AS avg_d11_20,
  ROUND(COUNTIF(EXTRACT(DAY FROM deal_date) >= 21)
        / (EXTRACT(DAY FROM LAST_DAY(deal_month)) - 20), 1) AS avg_d21_end
FROM apt_dataset.v_sales_clean
WHERE NOT is_bulk AND deal_month >= DATE '2025-02-01'
GROUP BY sido, deal_month;