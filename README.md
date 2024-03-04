# bcfishobs

[Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is documented as the *most current and comprehensive information source on fish presence for the province*. These scripts locate these observation points as linear referencing events on the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater).

The scripts:

- download `whse_fish.fiss_fish_obsrvtn_pnt_sp`, the latest observation data from DataBC
- download a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- download a lookup table `species_cd`, linking the fish species code found in the observation table to species name and scientific name
- load above tables to a PostgreSQL database
- discard any observations not coded as `point_type_code = 'Observation'` (`Summary` records are all be duplicates of `Observation` records)
- references the observation points to their position on the FWA stream network (as outlined below)
- create two ouputs (see below for descriptions)

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

## General requirements

- PostgreSQL/PostGIS 
- a FWA database created by [fwapg](https://github.com/smnorris/fwapg)
- GDAL >= 3.4
- Python (>=3.6)
- [bcdata](https://github.com/smnorris/bcdata)


## Run the scripts

Scripts presume that:

- environment variable `DATABASE_URL` points to the appropriate db
- FWA data are loaded to the db via `fwapg`

To set up the output tables and run the job:

    $ git clone https://github.com/smnorris/bcfishobs.git
    $ cd bcfishobs
    $ make


To refresh the observation data from DataBC and re-run the analysis (without tearing down the output tables):

    $ rm .make/fiss_fish_obsrvtn_pnt_sp
    $ make


To tear down `bcfishobs` schema and re-run the analysis from scratch:

    $ make clean
    $ make


## Outputs

All outputs are written to schema `bcfishobs`.

#### `bcfishobs.fiss_fish_obsrvtn_events_vw`

Contains a record for each observation that is successfully matched to a stream 
(not just distinct locations), and commonly used columns.
Geometries are located on the stream to which the observation is matched.

```
          Column           |          Type           |
---------------------------+-------------------------+
 fish_observation_point_id | integer                 |
 fish_obsrvtn_event_id     | bigint                  |
 linear_feature_id         | bigint                  |
 wscode_ltree              | ltree                   |
 localcode_ltree           | ltree                   |
 blue_line_key             | integer                 |
 waterbody_key             | integer                 |
 downstream_route_measure  | double precision        |
 distance_to_stream        | double precision        |
 match_type                | text                    |
 watershed_group_code      | character varying(4)    |
 species_id                | integer                 |
 species_code              | character varying(6)    |
 agency_id                 | numeric                 |
 observation_date          | date                    |
 agency_name               | character varying(60)   |
 source                    | character varying(1000) |
 source_ref                | character varying(4000) |
 activity_code             | character varying(100)  |
 activity                  | character varying(300)  |
 life_stage_code           | character varying(100)  |
 life_stage                | character varying(300)  |
 acat_report_url           | character varying(254)  |
 geom                      | geometry(PointZM,3005)  |
```

#### `bcfishobs.fiss_fish_obsrvtn_events`

Distinct locations of observations matched to streams.
Geometries are located on the stream to which the observation is matched.

```
          Column          |          Type          |
--------------------------+------------------------+
 fish_obsrvtn_event_id    | bigint                 |
 linear_feature_id        | integer                |
 wscode_ltree             | ltree                  |
 localcode_ltree          | ltree                  |
 blue_line_key            | integer                |
 watershed_group_code     | character varying(4)   |
 downstream_route_measure | double precision       |
 match_types              | text[]                 |
 obs_ids                  | integer[]              |
 species_codes            | text[]                 |
 species_ids              | integer[]              |
 maximal_species          | integer[]              |
 distances_to_stream      | double precision[]     |
 geom                     | geometry(PointZM,3005) |
Indexes:
    "fiss_fish_obsrvtn_events_pkey" PRIMARY KEY, btree (fish_obsrvtn_event_id)
    "fiss_fish_obsrvtn_events_blue_line_key_idx" btree (blue_line_key)
    "fiss_fish_obsrvtn_events_linear_feature_id_idx" btree (linear_feature_id)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_obs_ids_idx" gist (obs_ids gist__intbig_ops)
    "fiss_fish_obsrvtn_events_species_ids_idx" gist (species_ids gist__intbig_ops)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx" btree (wscode_ltree)
```

#### `bcfishobs.fiss_fish_obsrvtn_unmatched`

Unique observation locations that the scripts are unable to match to FWA streams.

```
            Column            |         Type         | Collation | Nullable | Default
------------------------------+----------------------+-----------+----------+---------
 fish_obsrvtn_pnt_distinct_id | integer              |           | not null |
 obs_ids                      | integer[]            |           |          |
 species_ids                  | integer[]            |           |          |
 distance_to_stream           | double precision     |           |          |
 geom                         | geometry(Point,3005) |           |          |
Indexes:
    "fiss_fish_obsrvtn_unmatched_pkey" PRIMARY KEY, btree (fish_obsrvtn_pnt_distinct_id)
    "fiss_fish_obsrvtn_unmatched_geom_idx" gist (geom)
```

#### `bcfishobs.summary`

Report on total number of observations processed and matched to streams, and the type of match used.

```
      Column       |  Type   |
-------------------+---------+
 match_type        | text    |
 n_distinct_events | integer |
 n_observations    | integer |
```

## Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.

### Example 1

List all species observed on the Cowichan River (`blue_line_key = 354155148`), downstream of Skutz Falls (`downstream_route_meaure = 34180`).

```
SELECT DISTINCT species_code
FROM bcfishobs.fiss_fish_obsrvtn_events_vw
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

What is the slope (percent) of the stream at all distinct locations of Steelhead observations in `COWN` watershed group (on single line streams)?

```
SELECT 
  e.fish_obsrvtn_event_id,
  s.gnis_name,
  s.gradient
FROM bcfishobs.fiss_fish_obsrvtn_events e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
WHERE e.species_codes && ARRAY['ST']
AND e.watershed_group_code = 'COWN'
AND s.edge_type = 1000
ORDER BY e.wscode_ltree, e.localcode_ltree, e.downstream_route_measure

 fish_obsrvtn_event_id |      gnis_name       | gradient 
-----------------------+----------------------+----------
          675380033961 | Cowichan River       |   0.0071
          675380034170 | Cowichan River       |   0.0614
          641720026729 | Koksilah River       |   0.0058
          641720036829 | Koksilah River       |   0.0369
          641720037394 | Koksilah River       |   0.0761
          581370001848 | Kelvin Creek         |   0.0061
          581370006510 | Kelvin Creek         |   0.0167
          564060000660 | Glenora Creek        |   0.0137
          564060008058 | Glenora Creek        |   0.0843
...
```

### Example 3

What are the order, elevation and gradient of all Arctic Grayling observations in the Parsnip watershed group?

```
SELECT
  fish_observation_point_id,
  s.gradient,
  s.stream_order,
  round((ST_Z((ST_Dump(ST_LocateAlong(s.geom, e.downstream_route_measure))).geom))::numeric) as elevation
FROM bcfishobs.fiss_fish_obsrvtn_events_vw e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
WHERE e.species_code = 'GR'
AND e.watershed_group_code = 'PARS'
ORDER BY e.wscode_ltree, e.localcode_ltree, e.downstream_route_measure;

 fish_observation_point_id | gradient | stream_order | elevation 
---------------------------+----------+--------------+-----------
                    233425 |        0 |            7 |       674
                    233402 |   0.0007 |            7 |       675
                    318578 |   0.0007 |            7 |       675
                    233432 |   0.0004 |            7 |       685
                     96418 |        0 |            6 |       694
                    233458 |   0.0003 |            7 |       696
...
```

## Warnings

### `fish_observation_point_id`

Column `fish_observation_point_id` is not an immutable primary key in the source table.
`fish_observation_point_id` is guaranteed to be unique for a given extract but values will change over time.
- if current id values are required, run a fresh extract
- if referring to a specific observation in communications, use some combination of `source`, `species_code`, `life_cycle_code`, coordinates, etc

### Duplicates

Duplicate rows (for all fields) exist in the source table and are replicated in the output view. 
Use observation counts with caution. 

## Scheduled job

The workflow is processed weekly and dumped to file.
Acces the latest extract as a geopackage [here](https://bcfishpass.s3.us-west-2.amazonaws.com/bcfishobs.gpkg.zip).