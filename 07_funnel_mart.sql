-- ============================================================
-- 07. Воронка исключений и итоговая витрина
-- ------------------------------------------------------------
-- Два последних шага проекта:
--   1) показать, сколько строк и почему выпало из расчёта;
--   2) собрать одну таблицу, из которой строится весь дашборд.
-- ============================================================


-- ------------------------------------------------------------
-- П21. Воронка исключений
--
-- В отчёте нельзя писать "я почистил данные". Читатель должен
-- видеть таблицей: из 134 301 строки до расчёта дошло столько-то,
-- выпало столько-то, и вот по каким причинам.
--
-- Считаем НАКОПИТЕЛЬНО: каждый шаг добавляет условие к
-- предыдущему. На глаз шаги не складываются, потому что
-- пересекаются: 62 записи со статусом Closed без даты выпадают
-- уже на первом шаге, а не на втором.
--
-- ВАЖНО: воронка обязана заканчиваться там же, где начинается
-- база расчётов. Наша база — is_duration_valid (131 927).
-- Поэтому шага "статус Closed" здесь НЕТ: флаг is_duration_valid
-- требует только двух корректных дат, статус ему безразличен.
-- Воронка, ведущая не туда, куда ведут метрики, хуже, чем её
-- отсутствие — читатель перестаёт верить всему документу.
--
-- excluded считается через LAG: значение предыдущей строки
-- минус текущее. У первой строки предыдущей нет, поэтому NULL.
--
-- Контроль: 134 301 -> 131 951 (выпало 2 350) -> 131 927 (выпало 24)
-- ------------------------------------------------------------
WITH steps AS (
  SELECT 1 AS step_order,
         'Всего в выгрузке' AS step_name,
         COUNT(*) AS rows_left
  FROM requests AS s

  UNION ALL

  SELECT 2,
         'Есть дата закрытия',
         COUNT(*)
  FROM requests AS s
  WHERE s.has_closed_at

  UNION ALL

  SELECT 3,
         'И закрытие не раньше создания',
         COUNT(*)
  FROM requests AS s
  WHERE s.is_duration_valid
)
SELECT st.step_name,
       st.rows_left,
       LAG(st.rows_left) OVER (ORDER BY st.step_order) - st.rows_left AS excluded,
       ROUND(st.rows_left * 100.0 / (SELECT COUNT(*) FROM requests), 2) AS share_left_pct
FROM steps AS st
ORDER BY st.step_order;

-- Проверка на устойчивость: если дополнительно потребовать
-- статус Closed, база сократится до 131 751 (минус ещё 176
-- обращений с датой закрытия при незакрытом статусе —
-- вероятно, переоткрытых). Из 24 записей с закрытием раньше
-- создания статус Closed имеют только 6.


-- ------------------------------------------------------------
-- П22. Итоговая витрина mart_requests
--
-- ЗЕРНО: одна строка = одно обращение. 134 301 строка.
--
-- Почему детальная, а не агрегированная: агрегат отвечает
-- только на заложенные вопросы. Стоит спросить "а как это
-- по каналам" — и витрину надо переделывать. Детальная
-- отвечает на вопросы, которых ещё не задавали.
--
-- Правило: витрина хранит факты, а не итоги. Агрегирует
-- потребитель — BI-система.
--
-- Здесь НЕТ GROUP BY: строки перекладываются один к одному,
-- добавляются только расчётные поля.
--
-- ЛОВУШКА, из-за которой отчёт врёт молча: в витрине лежат ВСЕ
-- строки, включая 2 374 без корректного срока. Без первой ветки
-- CASE WHEN days IS NULL THEN NULL они провалились бы в ELSE и
-- получили корзину "90+ дней". Ни одна проверка бы не упала:
-- сумма по корзинам сошлась бы со 134 301.
-- Меняешь базу — перепроверяй все CASE, написанные под старую.
--
-- Контроль: 134 301 / 134 301 / 131 927 / 131 927
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_requests;

CREATE TABLE mart_requests AS
WITH d AS (
  SELECT s.unique_key,
         s.created_at,
         s.closed_at,
         s.agency,
         s.complaint_type,
         s.channel,
         s.community_board,
         s.is_closed,
         s.is_duration_valid,
         DATE_TRUNC('month', s.created_at)   AS month,
         EXTRACT(DOW  FROM s.created_at)     AS dow,
         EXTRACT(HOUR FROM s.created_at)     AS hour,
         CASE WHEN s.is_duration_valid
              THEN EXTRACT(EPOCH FROM (s.closed_at - s.created_at)) / 86400
         END AS days
  FROM requests AS s
)
SELECT d.unique_key,
       d.created_at,
       d.closed_at,
       d.month,

       CASE d.dow WHEN 1 THEN 'Пн'
                  WHEN 2 THEN 'Вт'
                  WHEN 3 THEN 'Ср'
                  WHEN 4 THEN 'Чт'
                  WHEN 5 THEN 'Пт'
                  WHEN 6 THEN 'Сб'
                  WHEN 0 THEN 'Вс'
       END AS dow_name,

       CASE WHEN d.dow = 0 THEN 7 ELSE d.dow END AS dow_order,

       d.hour,
       d.agency,
       d.complaint_type,
       d.channel,
       d.community_board,
       d.is_closed,
       d.is_duration_valid,

       ROUND(d.days, 2) AS days,

       CASE WHEN d.days IS NULL THEN NULL
            WHEN d.days < 1  THEN 'до 1 дня'
            WHEN d.days < 3  THEN '1-3 дня'
            WHEN d.days < 7  THEN '3-7 дней'
            WHEN d.days < 30 THEN '7-30 дней'
            WHEN d.days < 90 THEN '30-90 дней'
            ELSE                  '90+ дней'
       END AS bucket,

       CASE WHEN d.days IS NULL THEN NULL
            WHEN d.days < 1  THEN 1
            WHEN d.days < 3  THEN 2
            WHEN d.days < 7  THEN 3
            WHEN d.days < 30 THEN 4
            WHEN d.days < 90 THEN 5
            ELSE                  6
       END AS bucket_order

FROM d;


-- Контроль витрины.
-- rows_cnt = keys_cnt означает, что зерно не сломалось
-- и строки не размножились.
SELECT COUNT(*)                     AS rows_cnt,
       COUNT(DISTINCT m.unique_key) AS keys_cnt,
       COUNT(m.days)                AS with_days,
       COUNT(m.bucket)              AS with_bucket
FROM mart_requests AS m;
