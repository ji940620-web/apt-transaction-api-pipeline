SELECT
  deal_month,
  COUNT(*) AS n,
  ROUND(SAFE_DIVIDE(COUNT(*), LAG(COUNT(*)) OVER (ORDER BY deal_month)) - 1, 3) AS mom_change
FROM apt_dataset.v_sales
GROUP BY deal_month
ORDER BY deal_month;