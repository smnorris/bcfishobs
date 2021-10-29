-- How many records total?
-- Compare this to match_report.sql
-- n_distinct_pts will always be lower than match_report's n_distinct_events,
-- but the total number of observations should be the same.
SELECT 'Total' as match_type, dist.n_distinct_pts, total.n_observations
FROM
(SELECT Count(*) AS n_distinct_pts
FROM bcfishobs.fiss_fish_obsrvtn_pnt_distinct) dist,
(SELECT Count(*) AS n_observations
FROM whse_fish.fiss_fish_obsrvtn_pnt_sp
WHERE point_type_code = 'Observation') total

--AND species_code in ('CM','CH','CO','PK','SK')