-- ============================================================
-- 05. Разрезы: типы жалоб, службы, каналы, районы
-- ------------------------------------------------------------
-- ВАЖНО: база выбирается под вопрос, а не одна на весь файл.
--   "сколько обращений поступило"  -> все 134 301 строка
--   "сколько времени занимает"     -> is_duration_valid, 131 927
--
-- Где в одной строке нужны обе базы, используется приём:
--   CASE WHEN is_duration_valid THEN <срок> END AS days
-- У негодных строк там NULL. Агрегаты NULL не видят, поэтому
-- медиана считается по годным, а COUNT(*) — по всем.
-- ============================================================


-- ------------------------------------------------------------
-- П11. Топ-10 типов жалоб
-- База: все 134 301. Знаменатель — подзапросом, не числом.
-- Ожидаемо: Illegal Parking 17 456 (13.00%), сумма топ-10 51.12%
-- ------------------------------------------------------------
SELECT s.complaint_type,
       COUNT(*) AS cnt,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM requests), 2) AS share_pct
FROM requests AS s
GROUP BY s.complaint_type
ORDER BY cnt DESC
LIMIT 10;


-- ------------------------------------------------------------
-- П12. Службы: объём и доля закрытых
-- База: все строки. Знаменатель доли — СВОЙ у каждой службы.
-- "Закрыто" берётся из флага is_closed, а не из строки 'Closed':
-- определение живёт в одном месте — в чистом слое.
-- Ожидаемо: NYPD 48 108 / 48 108 / 100.00%
-- ------------------------------------------------------------
SELECT s.agency,
       COUNT(*)                                AS total,
       COUNT(*) FILTER (WHERE s.is_closed)     AS closed_cnt,
       ROUND(COUNT(*) FILTER (WHERE s.is_closed) * 100.0 / COUNT(*), 2) AS closed_pct
FROM requests AS s
GROUP BY s.agency
ORDER BY total DESC
LIMIT 10;


-- ------------------------------------------------------------
-- П13. Службы: скорость закрытия
-- База: is_duration_valid.
-- p90 рядом с медианой показывает форму хвоста:
-- нормальный разрыв 3-5x, у DPR 43x, у DOHMH 286x.
-- Ожидаемо: NYPD 48 105 / 0.06 / 0.20
-- ------------------------------------------------------------
WITH d AS (
  SELECT s.agency,
         EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400 AS days
  FROM requests AS s
  WHERE s.is_duration_valid
)
SELECT d.agency,
       COUNT(*) AS cnt,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS p90_days
FROM d
GROUP BY d.agency
ORDER BY cnt DESC
LIMIT 10;


-- ------------------------------------------------------------
-- П14. Каналы обращения
-- Две базы в одной строке: total по всем, медиана по годным.
-- Контроль: сумма total = 134 301, сумма долей = 100.00
-- ------------------------------------------------------------
WITH d AS (
  SELECT s.channel,
         CASE WHEN s.is_duration_valid
              THEN EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400
         END AS days
  FROM requests AS s
)
SELECT d.channel,
       COUNT(*) AS total,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM requests), 2) AS share_pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days
FROM d
GROUP BY d.channel
ORDER BY total DESC;


-- ------------------------------------------------------------
-- П15. Районы
-- valid_cnt = COUNT(d.days): единственный случай, где
-- COUNT(колонка) правильнее COUNT(*) — пропуски надо не считать.
--
-- Доля долгих считается от valid_cnt, а не от total:
-- про обращение без даты закрытия нельзя сказать, долгое оно
-- или нет — оно не участвует в этом вопросе.
--
-- Внутри FILTER условие всегда про ОДНУ строку.
-- Агрегат там запрещён: FILTER отбирает строки ДО агрегации.
--
-- Контроль: сумма total = 134 301
-- ------------------------------------------------------------
WITH d AS (
  SELECT s.community_board,
         CASE WHEN s.is_duration_valid
              THEN EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400
         END AS days
  FROM requests AS s
)
SELECT d.community_board,
       COUNT(*)      AS total,
       COUNT(d.days) AS valid_cnt,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days,
       ROUND(COUNT(*) FILTER (WHERE d.days > 30) * 100.0 / COUNT(d.days), 2)  AS long30_pct
FROM d
GROUP BY d.community_board
ORDER BY total DESC;
