WITH matched_pts AS
(SELECT
  match_type,
  count(*) as n_distinct_events
FROM whse_fish.fiss_fish_obsrvtn_events
GROUP BY match_type
ORDER BY match_type),

matched_obs AS
(SELECT match_type, count(*) as n_observations
FROM
(SELECT
  a.match_type,
  unnest(b.obs_ids) as fish_observation_point_id
FROM whse_fish.fiss_fish_obsrvtn_events_prelim2 a
INNER JOIN whse_fish.fiss_fish_obsrvtn_pnt_distinct b
ON a.fish_obsrvtn_pnt_distinct_id = b.fish_obsrvtn_pnt_distinct_id) as obs
GROUP BY match_type
ORDER BY match_type),

unmatched_pts1 AS
(
SELECT
  'F. unmatched - less than 1500m to stream' as match_type,
  count(*) as n_distinct_events
FROM whse_fish.fiss_fish_obsrvtn_unmatched
GROUP BY match_type
ORDER BY match_type),

unmatched_obs1 AS
(SELECT match_type, count(*) as n_observations
FROM
(SELECT
  'F. unmatched - less than 1500m to stream' as match_type,
  unnest(obs_ids) as fish_observation_point_id
FROM whse_fish.fiss_fish_obsrvtn_unmatched) as obs
GROUP BY match_type
ORDER BY match_type),

unmatched_pts2 AS (
SELECT
  'G. unmatched - more than 1500m to stream' as match_type,
  count(o.fish_obsrvtn_pnt_distinct_id) as n_distinct_events
FROM whse_fish.fiss_fish_obsrvtn_pnt_distinct o
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events_prelim2 e
ON o.fish_obsrvtn_pnt_distinct_id = e.fish_obsrvtn_pnt_distinct_id
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_unmatched u
ON o.fish_obsrvtn_pnt_distinct_id = u.fish_obsrvtn_pnt_distinct_id
WHERE u.fish_obsrvtn_pnt_distinct_id IS NULL
AND e.fish_obsrvtn_pnt_distinct_id IS NULL
),

unmatched_obs2 AS (
  SELECT
    'G. unmatched - more than 1500m to stream' as match_type,
    Count(*) as n_observations
  FROM
  (SELECT unnest(o.obs_ids) AS fish_observation_point_id
  FROM whse_fish.fiss_fish_obsrvtn_pnt_distinct o
  LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events_prelim2 e
  ON o.fish_obsrvtn_pnt_distinct_id = e.fish_obsrvtn_pnt_distinct_id
  LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_unmatched u
  ON o.fish_obsrvtn_pnt_distinct_id = u.fish_obsrvtn_pnt_distinct_id
  WHERE u.fish_obsrvtn_pnt_distinct_id IS NULL
  AND e.fish_obsrvtn_pnt_distinct_id IS NULL) as all_ids
),

raw AS
(
SELECT
  a.match_type,
  a.n_distinct_events,
  b.n_observations
FROM matched_pts a
INNER JOIN matched_obs b ON a.match_type = b.match_type
UNION ALL
SELECT
  x.match_type,
  x.n_distinct_events,
  y.n_observations
FROM unmatched_pts1 x
INNER JOIN unmatched_obs1 y ON x.match_type = y.match_type
UNION ALL
SELECT
  m.match_type,
  m.n_distinct_events,
  n.n_observations
FROM unmatched_pts2 m
INNER JOIN unmatched_obs2 n ON m.match_type = n.match_type),

total_matched AS (
SELECT
'TOTAL MATCHED' as match_type,
sum(n_distinct_events) as n_distinct_events,
sum(n_observations) as n_observations
FROM raw
WHERE match_type LIKE '%% matched - %%'),

total_unmatched AS (
SELECT
'TOTAL UNMATCHED' as match_type,
sum(n_distinct_events) as n_distinct_events,
sum(n_observations) as n_observations
FROM raw
WHERE match_type LIKE '%% unmatched%%')

SELECT * FROM raw
WHERE match_type LIKE '%% matched%%'
UNION ALL
SELECT * FROM total_matched
UNION ALL
SELECT * FROM raw
WHERE match_type LIKE '%% unmatched%%'
UNION ALL
SELECT * FROM total_unmatched
UNION ALL
SELECT
  'GRAND TOTAL' as match_type,
  sum(n_distinct_events) as n_distinct_events,
  sum(n_observations) as n_observations
FROM raw
