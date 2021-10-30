# bcfishobs

BC [Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is a table described as the *most current and comprehensive information source on fish presence for the province*. This repository includes a method and scripts for locating these observation locations as linear referencing events on the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater).

The scripts:

- download `whse_fish.fiss_fish_obsrvtn_pnt_sp`, the latest observation data from DataBC
- download a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- download a lookup table `species_cd`, linking the fish species code found in the observation table to species name and scientific name
- load each above table to a PostgreSQL database
- discards any observations not coded as `point_type_code = 'Observation'` (`Summary` records are all be duplicates of `Observation` records)
- discards duplicate geometries from observation table
- references the observation points to their position on the FWA stream network (as outlined below)

### Matching logic, observations

1. For observation points associated with a lake or wetland (according to `wbody_id`):

    - match observations to the closest FWA stream in a waterbody that matches the observation's `wbody_id`, within 1500m
    - if no FWA stream in a lake/wetland within 1500m matches the observation's `wbody_id`, match to the closest stream in any lake/wetland within 1500m

2. For observation points associated with a stream:

    - match to the closest FWA stream within 100m that has a matching watershed code (via `fwa_streams_20k_50k_xref`)
    - for remaining unmatched records within 100m of an FWA stream, match to the closest stream regardless of a match via watershed code
    - for remaining unmatched records between 100m to 500m of an FWA stream, match to the closest FWA stream that has a matching watershed code

This logic is based on the assumptions:

- for observations noted as within a lake/wetland, we can use a relatively high distance threshold for matching to a stream because
    -  an observation may be on a bank far from a waterbody flow line
    -  as long as an observation is associated with the correct waterbody, it is not important to exactly locate it on the stream network within the waterbody
- for observations on streams, the location of an observation should generally take priority over a match via the xref lookup because many points have been manually snapped to the 20k stream lines - the lookup is best used to prioritize instances of multiple matches within 100m and allow for confidence in making matches between 100 and 500m


## Requirements

- PostgreSQL/PostGIS (requires PostgreSQL >=12.0, tested with v12.2, PostGIS 3.0.1)
- a FWA database created by [fwapg](https://github.com/smnorris/fwapg)
- GDAL
- Python (>=3.6)
- [bcdata](https://github.com/smnorris/bcdata)
- wget, unzip, psql2csv

## Installation

With `bcdata` installed (via `pip install --user bcdata`), all required Python libraries should be available, no further installation should be necessary.

Download/clone the scripts to your system and navigate to the folder:

```
$ git clone https://github.com/smnorris/bcfishobs.git
$ cd bcfishobs
```

## Run the scripts

Scripts presume that:
- environment variable `DATABASE_URL` points to the appropriate db
- FWA data are loaded to the db via `fwapg`

To run the job:

```
$ make
```


## Output tables

All derived outout tables are written to schema `bcfishobs`.

#### `bcfishobs.fiss_fish_obsrvtn_events_sp`

All observations that are successfully matched to streams (not just distinct locations) plus commonly used columns.
Geometries are located on the stream to which the observation is matched.

```
          Column           |          Type          | Collation | Nullable | Default
---------------------------+------------------------+-----------+----------+---------
 fish_observation_point_id | integer                |           |          |
 linear_feature_id         | integer                |           |          |
 wscode_ltree              | ltree                  |           |          |
 localcode_ltree           | ltree                  |           |          |
 blue_line_key             | integer                |           |          |
 waterbody_key             | integer                |           |          |
 downstream_route_measure  | double precision       |           |          |
 distance_to_stream        | double precision       |           |          |
 match_type                | text                   |           |          |
 watershed_group_code      | character varying(4)   |           |          |
 species_id                | integer                |           |          |
 species_code              | character varying      |           |          |
 agency_id                 | character varying      |           |          |
 observation_date          | date                   |           |          |
 agency_name               | character varying      |           |          |
 source                    | character varying      |           |          |
 source_ref                | character varying      |           |          |
 geom                      | geometry(PointZM,3005) |           |          |
Indexes:
    "fiss_fish_obsrvtn_events_sp_blue_line_key_idx" btree (blue_line_key)
    "fiss_fish_obsrvtn_events_sp_geom_idx" gist (geom)
    "fiss_fish_obsrvtn_events_sp_linear_feature_id_idx" btree (linear_feature_id)
    "fiss_fish_obsrvtn_events_sp_localcode_ltree_idx" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_sp_localcode_ltree_idx1" gist (localcode_ltree)
    "fiss_fish_obsrvtn_events_sp_waterbody_key_idx" btree (waterbody_key)
    "fiss_fish_obsrvtn_events_sp_watershed_group_code_idx" btree (watershed_group_code)
    "fiss_fish_obsrvtn_events_sp_wscode_ltree_idx" btree (wscode_ltree)
    "fiss_fish_obsrvtn_events_sp_wscode_ltree_idx1" gist (wscode_ltree)
```

## QA results

On completion, the script reports on the number and type of matches made and [dumps a summary to csv](qa_summary.csv)

The observation result can be compared with the output of `sql/qa_total_records`, the number of total observations should be the same in each query.

## Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.

### Example 1

List all species observed on the Cowichan River (`blue_line_key = 354155148`), downstream of Skutz Falls (`downstream_route_meaure = 34180`).

```
SELECT DISTINCT species_code
FROM bcfishobs.fiss_fish_obsrvtn_events_sp
WHERE blue_line_key = 354155148 AND
downstream_route_measure < 34180
ORDER BY species_code;

 species_code
--------------
 ACT
 AS
 BNH
 BT
 C
 CAL
 CAS
 CH
 CM
 CO
 CT
 DV
 EB
 GB
 KO
 L
 MARFAL
 RB
 SA
 SB
 ST
 TR
 TSB
```


### Example 2

What is the slope (percent) of the stream at the locations of all *distinct* Coho observation locations in `COWN` watershed group (on single line streams)?

```
SELECT DISTINCT ON (e.linear_feature_id, e.downstream_route_measure)
  e.fish_observation_point_id,
  s.gradient
FROM bcfishobs.fiss_fish_obsrvtn_events_sp e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
INNER JOIN whse_basemapping.fwa_edge_type_codes ec
ON s.edge_type = ec.edge_type
WHERE e.species_code = 'CO'
AND e.watershed_group_code = 'COWN'
AND ec.edge_type = 1000
ORDER BY e.linear_feature_id, e.downstream_route_measure, fish_observation_point_id;

 fish_observation_point_id | gradient
---------------------------+----------
                    188045 |   0.0109
                    187998 |   0.0015
                    187872 |        0
                    201002 |   0.1169
                    230155 |   0.0448
                    230838 |   0.0448
                    230194 |   0.0203
                    201004 |   0.0399
                    230353 |   0.0399
...
```


### Example 3

Trace downstream from fish observations to the ocean, generating implied habitat distribution for anadramous species:

See [`bcfishobs_traces`](https://github.com/smnorris/bcfishobs_traces)

### Example 4

What are the order, elevation and gradient of all Arctic Grayling observations in the Parsnip watershed group?

```
SELECT
  fish_observation_point_id,
  s.gradient,
  s.stream_order,
  round((ST_Z((ST_Dump(ST_LocateAlong(s.geom, e.downstream_route_measure))).geom))::numeric) as elevation
FROM bcfishobs.fiss_fish_obsrvtn_events_sp e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
WHERE e.species_code = 'GR'
AND e.watershed_group_code = 'PARS';

fish_observation_point_id | gradient | stream_order | elevation
---------------------------+----------+--------------+-----------
                     52045 |   0.0025 |            3 |       753
                     67443 |        0 |            6 |       694
                    175139 |   0.0005 |            2 |       728
                    230075 |        0 |            1 |       735
                    243190 |   0.0585 |            3 |      1097
...
```
