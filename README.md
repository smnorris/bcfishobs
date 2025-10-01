# bcfishobs

[Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is documented as the *most current and comprehensive information source on fish presence for the province*. These scripts locate these observation points as linear referencing events on the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater).

The scripts:

- download `whse_fish.fiss_fish_obsrvtn_pnt_sp`, the latest observation data from DataBC
- download a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- download a lookup table `species_cd`, linking the fish species code found in the observation table to species name and scientific name
- load above tables to a PostgreSQL database
- discard any observations not coded as `point_type_code = 'Observation'` (`Summary` records are all duplicates of `Observation` records)
- references the observation points to their position on the FWA stream network (as outlined below)
- creates output table `bcfishobs.observations`, as documented below

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

To set up the database/create schema:

    $ bcdata bc2pg -e -c 1 whse_fish.fiss_fish_obsrvtn_pnt_sp
    $ git clone https://github.com/smnorris/bcfishobs.git
    $ cd bcfishobs
    $ psql $DATABASE_URL -f db/v0.2.0.sql
    $ psql $DATABASE_URL -f db/v0.3.0.sql
    $ psql $DATABASE_URL -f db/v0.3.1.sql

To run the job:

    $ ./process.sh

## Output table

#### `bcfishobs.observations`

Source observations that have been successfully matched to a FWA stream.
Geometries are snapped to the closest point on the the stream network to which the observation is matched.

For a list of columns and descriptions, see [db/v0.3.0.sql](db/v0.3.0.sql) or the [bcfishpass feature service](https://features.hillcrestgeo.ca/bcfishpass/collections/bcfishobs.observations.html).


## Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.

### Example 1

List all species observed on the Cowichan River (`blue_line_key = 354155148`), downstream of Skutz Falls (`downstream_route_meaure = 34180`).

```
SELECT DISTINCT species_code
FROM bcfishobs.observations
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

What is the slope (percent) of the stream at observations of Steelhead in `COWN` watershed group (on single line streams)?

```
SELECT 
  e.observation_key,
  s.gnis_name,
  s.gradient
FROM bcfishobs.observations e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
WHERE e.species_code = 'ST'
AND e.watershed_group_code = 'COWN'
AND s.edge_type = 1000
ORDER BY e.wscode, e.localcode, e.downstream_route_measure;

 observation_key |      gnis_name       | gradient
-----------------+----------------------+----------
 7367b743b4      | Cowichan River       |   0.0071
 57ac3d846b      | Cowichan River       |   0.0614
 ed8506273b      | Cowichan River       |   0.0614
 78e91acb40      | Koksilah River       |   0.0058
 6904a74c2d      | Koksilah River       |   0.0369
 8fe2263fa4      | Koksilah River       |   0.0761
...
```

### Example 3

What are the order, elevation and gradient of all Arctic Grayling observations in the Parsnip watershed group?

```
SELECT
  observation_key,
  s.gradient,
  s.stream_order,
  round((ST_Z((ST_Dump(ST_LocateAlong(s.geom, e.downstream_route_measure))).geom))::numeric) as elevation
FROM bcfishobs.observations e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
WHERE e.species_code = 'GR'
AND e.watershed_group_code = 'PARS'
ORDER BY e.wscode, e.localcode, e.downstream_route_measure;

 observation_key | gradient | stream_order | elevation
-----------------+----------+--------------+-----------
 c91700c9d1      |        0 |            7 |       674
 f60bc8c392      |   0.0007 |            7 |       675
 e8209ab836      |   0.0007 |            7 |       675
 bd3162b43f      |   0.0004 |            7 |       685
 0ba700a120      |        0 |            6 |       694
 49d94cdb5c      |   0.0003 |            7 |       696
 fee71785e4      |   0.0003 |            7 |       698
...
```

## Warnings

### Primary key and duplicates

Column `fish_observation_point_id` is present in the ouput table but should generally be disregarded, it is unique when downloaded but unstable over time.

Column `observation_key` is generated by this script as a persistent unique identifier.  The value is created by hashing input columns `source, species_code, observation_date, utm_zone, utm_easting, utm_northing, life_stage_code, activity_code`. This combinaition of data is *mostly* unique in the source - any duplicates are dropped.

## Scheduled job

This script is run weekly by workflows in the [`bcfishpass` repository](https://github.com/smnorris/bcfishpass). The resulting parquet file is available at [https://nrs.objectstore.gov.bc.ca/bchamp/bcfishobs/observations.parquet](https://nrs.objectstore.gov.bc.ca/bchamp/bcfishobs/observations.parquet).