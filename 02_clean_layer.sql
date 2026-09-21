-- ============================================================
-- 02. Чистый слой: requests
-- ------------------------------------------------------------
-- Из сырого текстового слоя requests_raw строится рабочая
-- таблица с типами и флагами качества.
--
-- Принцип: строки НЕ удаляются, а помечаются флагами.
-- Одна таблица обслуживает все вопросы, каждый расчёт сам
-- решает, по какому флагу фильтровать.
--
-- Идиома NULLIF(TRIM(col), '') снимает пробелы по краям и
-- превращает пустую строку в NULL. Порядок важен:
-- ''::timestamp падает с ошибкой, NULL::timestamp — нет.
-- ============================================================

DROP TABLE IF EXISTS requests;

CREATE TABLE requests AS
SELECT
  r.unique_key,

  -- даты
  NULLIF(TRIM(r.created_date), '')::timestamp                  AS created_at,
  NULLIF(TRIM(r.closed_date),  '')::timestamp                  AS closed_at,
  NULLIF(TRIM(r.due_date),     '')::timestamp                  AS due_at,
  NULLIF(TRIM(r.resolution_action_updated_date), '')::timestamp AS resolution_updated_at,

  -- справочники
  NULLIF(TRIM(r.agency), '')                 AS agency,
  NULLIF(TRIM(r.agency_name), '')            AS agency_name,
  NULLIF(TRIM(r.complaint_type), '')         AS complaint_type,
  NULLIF(TRIM(r.descriptor), '')             AS descriptor,
  NULLIF(TRIM(r.location_type), '')          AS location_type,
  NULLIF(TRIM(r.status), '')                 AS status,

  -- география
  NULLIF(TRIM(r.incident_zip), '')           AS incident_zip,
  NULLIF(TRIM(r.incident_address), '')       AS incident_address,
  NULLIF(TRIM(r.street_name), '')            AS street_name,
  NULLIF(TRIM(r.city), '')                   AS city,
  NULLIF(TRIM(r.community_board), '')        AS community_board,
  NULLIF(TRIM(r.borough), '')                AS borough,
  NULLIF(TRIM(r.latitude),  '')::numeric     AS latitude,
  NULLIF(TRIM(r.longitude), '')::numeric     AS longitude,

  -- прочее
  NULLIF(TRIM(r.open_data_channel_type), '') AS channel,
  NULLIF(TRIM(r.resolution_description), '') AS resolution_description,

  -- флаги качества
  (TRIM(r.status) = 'Closed')                   AS is_closed,
  (NULLIF(TRIM(r.closed_date), '') IS NOT NULL) AS has_closed_at,
  COALESCE(NULLIF(TRIM(r.closed_date), '')::timestamp
           >= NULLIF(TRIM(r.created_date), '')::timestamp, false) AS is_duration_valid

FROM requests_raw AS r;


-- ------------------------------------------------------------
-- Контроль сборки.
-- Ожидаемо: 134301 / 131819 / 131951 / 131927
-- ------------------------------------------------------------
SELECT COUNT(*)                                   AS total,
       COUNT(*) FILTER (WHERE q.is_closed)         AS closed,
       COUNT(*) FILTER (WHERE q.has_closed_at)     AS with_date,
       COUNT(*) FILTER (WHERE q.is_duration_valid) AS valid
FROM requests AS q;
