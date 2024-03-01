create extension if not exists intarray;
create schema if not exists bcfishobs;

CREATE TABLE whse_fish.wdic_waterbodies (
  id integer primary key,
  type text,
  extinct_indicator text,
  watershed_id integer,
  sequence_number text,
  waterbody_identifier text,
  gazetted_name text,
  waterbody_mouth_identifier text,
  formatted_name text
 );
create index wdic_waterbodies_wbtrimidx on whse_fish.wdic_waterbodies (ltrim(waterbody_identifier,'0'));
create index wdic_waterbodies_typeidx on whse_fish.wdic_waterbodies (type);

CREATE TABLE whse_fish.species_cd (
  species_id     integer primary key,
  code            text,
  name            text,
  cdcgr_code      text,
  cdclr_code      text,
  scientific_name text,
  spctype_code    text,
  spcgrp_code     text
);

create table bcfishobs.fiss_fish_obsrvtn_events ( 
  fish_obsrvtn_event_id bigint
     GENERATED ALWAYS AS ((((blue_line_key::bigint + 1) - 354087611) * 10000000) + round(downstream_route_measure::bigint)) STORED PRIMARY KEY,
  linear_feature_id integer,
  wscode_ltree ltree,
  localcode_ltree ltree,
  blue_line_key integer,
  watershed_group_code character varying(4),
  downstream_route_measure double precision,
  match_types text[],
  obs_ids integer[],
  species_codes text[],
  species_ids integer[],
  maximal_species integer[],
  distances_to_stream double precision[],
  geom geometry(pointzm, 3005)
);
create index on bcfishobs.fiss_fish_obsrvtn_events (linear_feature_id);
create index on bcfishobs.fiss_fish_obsrvtn_events (blue_line_key);
create index on bcfishobs.fiss_fish_obsrvtn_events (wscode_ltree);
create index on bcfishobs.fiss_fish_obsrvtn_events (localcode_ltree);
create index on bcfishobs.fiss_fish_obsrvtn_events using gist (wscode_ltree);
create index on bcfishobs.fiss_fish_obsrvtn_events using gist (localcode_ltree);
create index on bcfishobs.fiss_fish_obsrvtn_events using gist (geom);
create index on bcfishobs.fiss_fish_obsrvtn_events using gist (obs_ids gist__intbig_ops);
create index on bcfishobs.fiss_fish_obsrvtn_events using gist (species_ids gist__intbig_ops);

create table bcfishobs.fiss_fish_obsrvtn_unmatched (
  fish_obsrvtn_pnt_distinct_id integer primary key,
  obs_ids integer[],
  species_ids integer[],
  distance_to_stream double precision,
  geom geometry(Point, 3005)
);
create index on bcfishobs.fiss_fish_obsrvtn_unmatched using gist (geom);

comment on table bcfishobs.fiss_fish_obsrvtn_events IS 'Unique locations of BC Fish Observations snapped to FWA streams';
comment on column bcfishobs.fiss_fish_obsrvtn_events.fish_obsrvtn_event_id IS 'Unique identifier, linked to blue_line_key and measure';
comment on column bcfishobs.fiss_fish_obsrvtn_events.match_types IS 'Notes on how the observation(s) were matched to the stream';
comment on column bcfishobs.fiss_fish_obsrvtn_events.obs_ids IS 'fish_observation_point_id for observations associated with the location';
comment on column bcfishobs.fiss_fish_obsrvtn_events.species_codes IS 'BC fish species codes, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
comment on column bcfishobs.fiss_fish_obsrvtn_events.species_ids IS 'Species IDs, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
comment on column bcfishobs.fiss_fish_obsrvtn_events.maximal_species IS 'Indicates if the observation is the most upstream for the given species (no additional observations upstream)';
comment on column bcfishobs.fiss_fish_obsrvtn_events.distances_to_stream IS 'Distances (m) from source observations to output point';
comment on column bcfishobs.fiss_fish_obsrvtn_events.geom IS 'Geometry of observation(s) on the FWA stream (measure rounded to the nearest metre)';


-- de-aggregated view - all matched observations as single points, snapped to streams
CREATE VIEW bcfishobs.fiss_fish_obsrvtn_events_vw AS

WITH all_obs AS (
  SELECT
    unnest(e.obs_ids) AS fish_observation_point_id,
    e.fish_obsrvtn_event_id,
    s.linear_feature_id,
    s.wscode_ltree,
    s.localcode_ltree,
    e.blue_line_key,
    s.waterbody_key,
    e.downstream_route_measure,
    unnest(e.distances_to_stream) as distance_to_stream,
    unnest(e.match_types) as match_type,
    s.watershed_group_code,
    e.geom
  FROM bcfishobs.fiss_fish_obsrvtn_events e
  INNER JOIN whse_basemapping.fwa_stream_networks_sp s
  ON e.linear_feature_id = s.linear_feature_id
)
SELECT
  a.fish_observation_point_id,
  a.fish_obsrvtn_event_id,
  a.linear_feature_id,
  a.wscode_ltree,
  a.localcode_ltree,
  a.blue_line_key,
  a.waterbody_key,
  a.downstream_route_measure,
  a.distance_to_stream,
  a.match_type,
  a.watershed_group_code,
  sp.species_id,
  b.species_code,
  b.agency_id,
  b.observation_date,
  b.agency_name,
  b.source,
  b.source_ref,
  b.activity_code,
  b.activity,
  b.life_stage_code,
  b.life_stage,
  b.acat_report_url,
  (st_dump(a.geom)).geom::geometry(PointZM, 3005) AS geom
FROM all_obs a
INNER JOIN whse_fish.fiss_fish_obsrvtn_pnt_sp  b
ON a.fish_observation_point_id = b.fish_observation_point_id
INNER JOIN whse_fish.species_cd sp ON b.species_code = sp.code;

comment on view bcfishobs.fiss_fish_obsrvtn_events_vw IS 'BC Fish Observations snapped to FWA streams';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.fish_obsrvtn_event_id IS 'Links to fiss_fish_obsrvtn_events, a unique location on the stream network based on blue_line_key and measure';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.fish_observation_point_id IS 'Source observation primary key';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.distance_to_stream IS 'Distance (m) from source observation to output point';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.match_type IS 'Notes on how the observation was matched to the stream';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.species_id IS 'Species ID, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.species_code IS 'BC fish species code, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.agency_id IS '';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.observation_date IS 'The date on which the observation occurred.';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.agency_name IS 'The name of the agency that made the observation.';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.source IS 'The abbreviation, and if appropriate, the primary key, of the dataset(s) from which the data was obtained. For example: FDIS Database: fshclctn_id 66589';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.source_ref IS 'The concatenation of all biographical references for the source data.  This may include citations to reports that published the observations, or the name of a project under which the observations were made. Some example values for SOURCE REF are: A RECONNAISSANCE SURVEY OF CULTUS LAKE, and Bonaparte Watershed Fish and Fish Habitat Inventory - 2000';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.activity_code IS 'ACTIVITY CODE contains the fish activity code from the source dataset, such as I for Incubating, or SPE for Spawning In Estuary.';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.activity IS 'ACTIVITY is a full textual description of the activity the fish was engaged in when it was observed, such as SPAWNING.';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.life_stage_code IS 'LIFE STAGE CODE is a short character code identiying the life stage of the fish species for this oberservation.  Each source dataset of observations uses its own set of LIFE STAGE CODES.  For example, in the FDIS dataset, U means Undetermined, NS means Not Specified, M means Mature, IM means Immature, and MT means Maturing.  Descriptions for each LIFE STAGE CODE are given in the LIFE STAGE attribute.';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.life_stage IS 'LIFE STAGE is the full textual description corresponding to the LIFE STAGE CODE';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.acat_report_url IS 'ACAT REPORT URL is a URL to the ACAT REPORT which provides additional information about the FISS FISH OBSRVTN PNT SP.';
comment on column bcfishobs.fiss_fish_obsrvtn_events_vw.geom IS 'Geometry of observation on the FWA stream (measure rounded to the nearest metre)';     


create table bcfishobs.summary (
  match_type text,
  n_distinct_events integer,
  n_observations integer
);