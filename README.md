# bcfishobs

BC [Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is a table described as the *most current and comprehensive information source on fish presence for the province*. This repository includes a method and scripts for locating these observation locations as linear referencing events on the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater).

The script:

- downloads `whse_fish.fiss_fish_obsrvtn_pnt_sp`, the latest observation data from DataBC
- downloads a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- downloads a lookup table `species_cd`, linking the fish species code found in the observation table to species name and scientific name
- loads each table to a PostgreSQL database
- aggregates the observations to retain only distinct sites that are coded as `point_type_code = 'Observation'` (`Summary` records should all be duplicates of `Observation` records; they can be discarded)
- references the observation points to their position on the FWA stream network using the logic outlined below

### Matching logic / steps

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
- a FWA database created by [fwapg](https://github.com/smnorris/bcdata)
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
- the FWA database is loaded (to schema `whse_basemapping`)
- environment variables PGHOST, PGUSER, PGDATABASE, PGPORT, DATABASE_URL are set to the appropriate db
- password authentication for the database is not required

The scripts are run via two bash control scripts:

```
$ ./01_load.sh
$ ./02_process.sh
```


## Output data

Three new tables and one view are created by the script (in addition to the downloaded data):

#### `whse_fish.fiss_fish_obsrvtn_pnt_distinct`

Distinct locations of fish observations. Some points are duplicated as equivalent locations may have different values for `new_watershed_code`.

```
            Column             |         Type
-------------------------------+-----------------------
 fish_obsrvtn_pnt_distinct_id  | integer
 obs_ids                       | integer[]
 utm_zone                      | integer
 utm_easting                   | integer
 utm_northing                  | integer
 wbody_id                      | double precision
 waterbody_type                | character varying
 new_watershed_code            | character varying
 species_codes                 | text[]
 watershed_group_code          | text
 geom                          | geometry(Point, 3005)

Indexes:
    "fiss_fish_obsrvtn_pnt_distinct_pkey" PRIMARY KEY, btree (fish_obsrvtn_pnt_distinct_id)
    "fiss_fish_obsrvtn_distinct_gidx" gist (geom)
    "fiss_fish_obsrvtn_distinct_wbidix" btree (wbody_id)
```


#### `whse_fish.fiss_fish_obsrvtn_events`

Distinct observation points stored as linear events on `whse_basemapping.fwa_stream_networks_sp`

```
          Column              |         Type
------------------------------+----------------------
 fish_obsrvtn_pnt_distinct_id | integer
 linear_feature_id            | integer
 wscode_ltree                 | ltree
 localcode_ltree              | ltree
 blue_line_key                | integer
 waterbody_key                | integer
 downstream_route_measure     | double precision
 watershed_group_code         | character varying(4)
 obs_ids                      | integer[]
 species_codes                | text[]
 maximal_species              | text[]
 distance_to_stream           | double precision
 match_type                   | text
Indexes:
    "fiss_fish_obsrvtn_events_blue_line_key_idx" btree (blue_line_key)
    "fiss_fish_obsrvtn_events_linear_feature_id_idx" btree (linear_feature_id)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx" gist (localcode_ltree)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx1" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_waterbody_key_idx" btree (waterbody_key)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx" gist (wscode_ltree)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx1" btree (wscode_ltree)
```


#### `whse_fish.fiss_fish_obsrvtn_unmatched`

Distinct observation points that were not referenced to the stream network (for QA)

```
            Column             |        Type
-------------------------------+---------------------
 fish_obsrvtn_pnt_distinct_id  | bigint
 obs_ids                       | integer[]
 species_codes                 | character varying[]
 distance_to_stream            | double precision
 geom                          | geometry(Point, 3005)
Indexes:
    "fish_obsrvtn_unmatched_pkey" PRIMARY KEY, btree (fish_obsrvtn_distinct_id)
```

#### `whse_fish.fiss_fish_obsrvtn_events_vw`

A materialized view showing all observations that are successfully matched to streams (not just distinct locations) plus commonly used columns.
Geometries are located on the stream to which the observation is matched.
This is probably the table to use for most queries.

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
 species_code              | character varying      |           |          |
 agency_id                 | character varying      |           |          |
 observation_date          | date                   |           |          |
 agency_name               | character varying      |           |          |
 source                    | character varying      |           |          |
 source_ref                | character varying      |           |          |
 geom                      | geometry(PointZM,3005) |           |          |
Indexes:
    "fiss_fish_obsrvtn_events_vw_blue_line_key_idx" btree (blue_line_key)
    "fiss_fish_obsrvtn_events_vw_geom_idx" gist (geom)
    "fiss_fish_obsrvtn_events_vw_linear_feature_id_idx" btree (linear_feature_id)
    "fiss_fish_obsrvtn_events_vw_localcode_ltree_idx" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_vw_localcode_ltree_idx1" gist (localcode_ltree)
    "fiss_fish_obsrvtn_events_vw_waterbody_key_idx" btree (waterbody_key)
    "fiss_fish_obsrvtn_events_vw_watershed_group_code_idx" btree (watershed_group_code)
    "fiss_fish_obsrvtn_events_vw_wscode_ltree_idx" btree (wscode_ltree)
    "fiss_fish_obsrvtn_events_vw_wscode_ltree_idx1" gist (wscode_ltree)
```

## QA results

On completion, the script runs the query `sql/qa_match_report.sql`, reporting on the number and type of matches made. Results are written to csv file `qa_match_report.csv`.

[Current result (May 31, 2020)](qa_match_report.csv)

This result can be compared with the output of `sql/qa_total_records`, the number of total observations should be the same in each query.

## Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.

### Example 1

List all species observed on the Cowichan River (`blue_line_key = 354155148`), downstream of Skutz Falls (`downstream_route_meaure = 34180`).

```
SELECT DISTINCT species_code
FROM whse_fish.fiss_fish_obsrvtn_events_vw
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
FROM whse_fish.fiss_fish_obsrvtn_events_vw e
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

What are the order, elevation and gradient of all Greyling observations in the Parsnip watershed group?

```
SELECT
  fish_observation_point_id,
  s.gradient,
  s.stream_order,
  round((ST_Z((ST_Dump(ST_LocateAlong(s.geom, e.downstream_route_measure))).geom))::numeric) as elevation
FROM whse_fish.fiss_fish_obsrvtn_events_vw e
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
