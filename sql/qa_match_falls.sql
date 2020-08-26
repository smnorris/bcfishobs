with total AS
(
    SELECT
      count(*) as n_falls_total
    FROM whse_fish.fiss_obstacles_pnt_sp
    WHERE obstacle_name = 'Falls'
),

matched AS
(
    SELECT
      count(*) as n_falls_matched
    FROM whse_fish.fiss_falls_events_sp
)

SELECT a.n_falls_total, b.n_falls_matched
FROM total a, matched b;