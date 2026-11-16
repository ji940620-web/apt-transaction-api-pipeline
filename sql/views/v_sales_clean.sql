-- ============================================================
-- 파일: sql/views/v_sales_clean.sql
-- 목적: 매매 거래 중 "일괄 신고 의심" 거래를 표시하는 뷰
-- 입력: apt_dataset.v_sales
-- 출력: v_sales의 모든 컬럼 + is_bulk (TRUE/FALSE)
-- 기준: 같은 단지 + 같은 날짜 + 같은 가격이 10건 이상이면 is_bulk = TRUE
-- 배경: 2026-10-08 동대문구 에드가휘경 한 단지에서 313건이 같은 가격으로 신고되어
--       동대문구 중위가가 3.8배 낮게 왜곡됨 (일괄 포함 24,488 / 제외 94,000만원)
-- 주의: - 삭제하지 않고 표시만 한다. 사용할 때 WHERE NOT is_bulk 로 제외.
--       - 10건이라는 기준은 임의값이다. 진짜 개별 거래가 섞여 있을 수 있다.
-- 작성: 2026-11-10
-- ============================================================
CREATE OR REPLACE VIEW apt_dataset.v_sales_clean AS
SELECT *,
  COUNT(*) OVER (PARTITION BY complex_key, deal_date, price) >= 10 AS is_bulk
FROM apt_dataset.v_sales;