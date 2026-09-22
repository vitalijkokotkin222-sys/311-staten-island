-- ============================================================
-- 06. Динамика: месяцы, дни недели, часы
-- ------------------------------------------------------------
-- Разрезы отвечали на вопрос "у кого". Этот файл — на вопрос
-- "когда": есть ли сезонность, где пики, что меняется во времени.
--
-- Приём, общий для всего файла: в CTE длительность кладётся
-- через CASE, поэтому у строк без корректных дат там NULL.
-- Агрегаты NULL не видят — медиана считается по годным,
-- а COUNT(*) при этом считает ВСЕ строки разреза.
-- ============================================================


-- ------------------------------------------------------------
-- П16-П18. Поток по месяцам: объём, нормализация, изменение
--
-- Группировка через DATE_TRUNC, а не TO_CHAR: DATE_TRUNC даёт
-- дату, по ней сортировка корректна всегда. TO_CHAR дал бы
-- текст, а у текста порядка нет.
--
-- days_in_month: берём первое число месяца, прибавляем месяц,
-- отнимаем день — получаем последнее число месяца, из него
-- достаём номер дня. Високосный год отрабатывает сам.
--
-- ЗАЧЕМ нормализация: в феврале 28 дней, в январе 31.
-- Без деления на число дней февраль выглядит провалом года
-- (9 154 против 10 125), а на самом деле он ВЫШЕ января:
-- 326.9 в день против 326.6.
--
-- LAG — оконная функция, работает ПОСЛЕ группировки, поэтому
-- ей нужен отдельный слой (f -> g), агрегат внутрь не положить.
--
-- Контроль: 12 строк, сумма total = 134 301, сумма дней = 365,
-- у января mom_pct пустой, у февраля +0.1
-- ------------------------------------------------------------
WITH d AS (
  SELECT DATE_TRUNC('month', s.created_at) AS month,
         CASE WHEN s.is_duration_valid
              THEN EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400
         END AS days
  FROM requests AS s
),
f AS (
  SELECT d.month,
         COUNT(*) AS total,
         EXTRACT(DAY FROM (d.month + INTERVAL '1 month' - INTERVAL '1 day')) AS days_in_month,
         ROUND(COUNT(*) / EXTRACT(DAY FROM (d.month + INTERVAL '1 month' - INTERVAL '1 day')), 1) AS per_day,
         ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days
  FROM d
  GROUP BY d.month
),
g AS (
  SELECT f.month,
         f.total,
         f.days_in_month,
         f.per_day,
         f.median_days,
         LAG(f.per_day) OVER (ORDER BY f.month) AS prev_per_day
  FROM f
)
SELECT g.month,
       g.total,
       g.days_in_month,
       g.per_day,
       g.prev_per_day,
       ROUND((g.per_day - g.prev_per_day) * 100.0 / g.prev_per_day, 1) AS mom_pct,
       g.median_days
FROM g
ORDER BY g.month;


-- ------------------------------------------------------------
-- П19. Дни недели
--
-- EXTRACT(DOW) возвращает 0 для воскресенья, 1 для понедельника
-- и так далее. Подпись дня — текст, сортировать по ней нельзя,
-- поэтому рядом идёт служебная колонка-номер dow_order.
-- У воскресенья она равна 7, чтобы оно встало последним.
--
-- Контроль: 7 строк, сумма total = 134 301
-- ------------------------------------------------------------
WITH d AS (
  SELECT EXTRACT(DOW FROM s.created_at) AS dow,
         CASE WHEN s.is_duration_valid
              THEN EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400
         END AS days
  FROM requests AS s
)
SELECT CASE d.dow WHEN 1 THEN 'Пн'
                  WHEN 2 THEN 'Вт'
                  WHEN 3 THEN 'Ср'
                  WHEN 4 THEN 'Чт'
                  WHEN 5 THEN 'Пт'
                  WHEN 6 THEN 'Сб'
                  WHEN 0 THEN 'Вс'
       END AS dow_name,
       CASE WHEN d.dow = 0 THEN 7 ELSE d.dow END AS dow_order,
       COUNT(*) AS total,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days
FROM d
GROUP BY 1, 2
ORDER BY dow_order;


-- ------------------------------------------------------------
-- П20. Часы суток
--
-- Час уже число от 0 до 23, сортируется сам — служебная
-- колонка не нужна.
--
-- Что видно: медиана скачет в шесть раз ровно в 7:00
-- (с 0.05-0.16 до 1.0-1.2). Это момент включения городских
-- служб: ночью в системе работает только полиция.
--
-- Контроль: 24 строки, сумма total = 134 301, долей = 100.00
-- ------------------------------------------------------------
WITH d AS (
  SELECT EXTRACT(HOUR FROM s.created_at) AS hour,
         CASE WHEN s.is_duration_valid
              THEN EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400
         END AS days
  FROM requests AS s
)
SELECT d.hour,
       COUNT(*) AS total,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM requests), 2) AS share_pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.days)::numeric, 2) AS median_days
FROM d
GROUP BY d.hour
ORDER BY d.hour;
