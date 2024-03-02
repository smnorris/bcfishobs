-- Dump all un-referenced points (within 1500m of a stream) for QA.
-- Note that points >1500m from a stream will not be in this table, but there
-- are not many of those.
truncate bcfishobs.fiss_fish_obsrvtn_unmatched;
insert into bcfishobs.fiss_fish_obsrvtn_unmatched (
  fish_obsrvtn_pnt_distinct_id,
  obs_ids,
  species_ids,
  distance_to_stream,
  geom
)
SELECT DISTINCT ON (e1.fish_obsrvtn_pnt_distinct_id)
  e1.fish_obsrvtn_pnt_distinct_id,
  o.obs_ids,
  o.species_ids,
  e1.distance_to_stream,
  o.geom
FROM bcfishobs.fiss_fish_obsrvtn_events_prelim_a e1
LEFT OUTER JOIN bcfishobs.fiss_fish_obsrvtn_events_prelim_b e2
ON e1.fish_obsrvtn_pnt_distinct_id = e2.fish_obsrvtn_pnt_distinct_id
INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct o
ON e1.fish_obsrvtn_pnt_distinct_id = o.fish_obsrvtn_pnt_distinct_id
WHERE e2.fish_obsrvtn_pnt_distinct_id IS NULL
ORDER BY e1.fish_obsrvtn_pnt_distinct_id, e1.distance_to_stream;