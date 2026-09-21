-- ============================================================
-- 04. Метрики: время закрытия обращения
-- ------------------------------------------------------------
-- База для всего файла: is_duration_valid (131 927 строк).
-- Считаем время — значит нужны обе даты и корректный порядок.
--
-- Длительность в днях:
--   EXTRACT(EPOCH FROM (closed_at - created_at)) / 86400
--
-- Типы: EXTRACT в PostgreSQL 14+ возвращает numeric,
-- поэтому AVG / MIN / MAX округляются напрямую.
-- PERCENTILE_CONT возвращает double precision ВСЕГДА —
-- перед ROUND(x, 2) обязателен ::numeric.
-- ============================================================


-- ------------------------------------------------------------
-- П7. Время закрытия: объём, среднее, медиана, границы
-- Ожидаемо: 131927 / 10.89 / 0.63 / 0.00 / 595.14
-- ------------------------------------------------------------
WITH d AS (
  SELECT EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400 AS days
  FROM requests AS s
  WHERE s.is_duration_valid
)
SELECT COUNT(*)                AS rows_cnt,
       ROUND(AVG(d.days), 2)   AS avg_days,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days,
       ROUND(MIN(d.days), 2)   AS min_days,
       ROUND(MAX(d.days), 2)   AS max_days
FROM d;


-- ------------------------------------------------------------
-- П8. Лестница перцентилей
-- Ожидаемо: 0.06 / 0.63 / 3.68 / 13.84 / 48.83 / 262.39
-- ------------------------------------------------------------
WITH d AS (
  SELECT EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400 AS days
  FROM requests AS s
  WHERE s.is_duration_valid
)
SELECT ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p25,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p50,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p75,
       ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p90,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p95,
       ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p99
FROM d;


-- ------------------------------------------------------------
-- П9–П10. Распределение по корзинам сроков + доля от общего
--
-- Подпись корзины — текст, порядка в себе не содержит:
-- сортировка по ней поставила бы '30-90' рядом с '3-7'.
-- Поэтому рядом идёт служебная колонка-номер bucket_order,
-- она же попадает в GROUP BY.
--
-- Контроль: сумма cnt = 131927, сумма долей = 100.00
-- ------------------------------------------------------------
WITH d AS (
  SELECT EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400 AS days
  FROM requests AS s
  WHERE s.is_duration_valid
),
f AS (
  SELECT CASE WHEN d.days < 1  THEN 'до 1 дня'
              WHEN d.days < 3  THEN '1-3 дня'
              WHEN d.days < 7  THEN '3-7 дней'
              WHEN d.days < 30 THEN '7-30 дней'
              WHEN d.days < 90 THEN '30-90 дней'
              ELSE                  '90+ дней'
         END AS bucket,
         CASE WHEN d.days < 1  THEN 1
              WHEN d.days < 3  THEN 2
              WHEN d.days < 7  THEN 3
              WHEN d.days < 30 THEN 4
              WHEN d.days < 90 THEN 5
              ELSE                  6
         END AS bucket_order,
         COUNT(*) AS cnt
  FROM d
  GROUP BY 1, 2
)
SELECT f.bucket,
       f.cnt,
       ROUND(f.cnt * 100.0 / (SELECT COUNT(*) FROM d), 2) AS share_pct
FROM f
ORDER BY f.bucket_order;
