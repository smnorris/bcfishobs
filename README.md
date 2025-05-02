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

    $ git clone https://github.com/smnorris/bcfishobs.git
    $ cd bcfishobs
    $ psql $DATABASE_URL -f db/v0.2.0.sql
    $ psql $DATABASE_URL -f db/v0.3.0.sql

To run the job:

    $ ./process.sh

## Output

All outputs are written to schema `bcfishobs`.

#### `bcfishobs.observations`

Source observations that have been successfully matched to a FWA stream.
Geometries are snapped to the closest point on the the stream to which the observation is matched.

```
 Column                   |          Type          
--------------------------+-------------------------+
 observation_key          | text                    
 wbody_id                 | numeric                 
 species_code             | character varying(6)    
 agency_id                | numeric                 
 point_type_code          | character varying(20)   
 observation_date         | date                    
 agency_name              | character varying(60)   
 source                   | character varying(1000) 
 source_ref               | character varying(4000) 
 utm_zone                 | numeric                 
 utm_easting              | numeric                 
 utm_northing             | numeric                 
 activity_code            | character varying(100)  
 activity                 | character varying(300)  
 life_stage_code          | character varying(100)  
 life_stage               | character varying(300)  
 species_name             | character varying(60)   
 waterbody_identifier     | character varying(9)    
 waterbody_type           | character varying(20)   
 gazetted_name            | character varying(30)   
 new_watershed_code       | character varying(56)   
 trimmed_watershed_code   | character varying(56)   
 acat_report_url          | character varying(254)  
 feature_code             | character varying(10)   
 linear_feature_id        | integer                 
 wscode                   | ltree                   
 localcode                | ltree                   
 blue_line_key            | integer                 
 watershed_group_code     | character varying(4)    
 downstream_route_measure | double precision        
 match_type               | text                    
 distances_to_stream      | double precision        
 geom                     | geometry(PointZM,3005)  
```


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

What is the slope (percent) of the stream at all distinct locations of Steelhead observations in `COWN` watershed group (on single line streams)?

```
SELECT 
  e.fish_obsrvtn_event_id,
  s.gnis_name,
  s.gradient
FROM bcfishobs.observations e
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
FROM bcfishobs.observations e
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

### Primary key and duplicates

Column `fish_observation_point_id` has been removed from the ouput, it is unique when downloaded but changes over time.

Column `observation_key` is generated by this script as a persistent unique identifier.  The value is created by hashing input columns `source, species_code, observation_date, utm_zone, utm_easting, utm_northing, life_stage_code, activity_code`. This combinaition of data is *mostly* unique in the source - any duplicates are dropped.

## Scheduled job

The `bcfishpass` scheduled workflow runs this script on a weekly basis, dumping the results to a [parquet file on NRS object storage](https://nrs.objectstore.gov.bc.ca/bchamp/bcfishobs/observations.parquet).