# bcfishobs

BC [Known BC Fish Observations](https://catalogue.data.gov.bc.ca/dataset/known-bc-fish-observations-and-bc-fish-distributions) is a table described as the *most current and comprehensive information source on fish presence for the province*. However, the point locations in the table are not referenced to the most current and comprehensive stream network currently available for BC, the [Freshwater Atlas](https://www2.gov.bc.ca/gov/content/data/geographic-data-services/topographic-data/freshwater). 

The script:

- downloads observation data from DataBC
- downloads a lookup table `whse_fish.wdic_waterbodies` used to match the 50k waterbody codes in the observations table to FWA waterbodies
- loads each table to postgres
- cleans the observations to retain only distinct species/location combinations that are coded as `point_type_code = 'Observation'`
- references the observation points to their position on the FWA stream network in two ways:
    + for records associated with a stream (with a `wbody_id` that is not associated with a lake/wetland), match to nearest stream within 300m
    + for records associated with a lake or wetland (according to `wbody_id`) , match to the lake/wetland that matches the `wbody_id` - or if that fails, with the nearest lake/wetland (within 1500m)

# Requirements

- PostgreSQL/PostGIS
- Python
- GDAL and GDAL Python bindings
- [fwakit](https://github.com/smnorris/fwakit) and a FWA database

# Installation

With `fwakit` installed, all required Python libraries should be available, no further installation should be necessary.  

Download/clone the scripts to your system and navigate to the folder: 

```
$ git clone bcfishobs
$ cd bcfishobs
```

# Run the script

Usage presumes that you have installed `fwakit`, the FWA database is loaded, and the `$FWA_DB` environment variable is correct. See the instructions for this [here](https://github.com/smnorris/fwakit#configuration).

Run the script in two steps, one to download the data, the next to do the linear referencing:  

```
$ python bcfishobs.py download
$ python bcfishobs.py process
```

Time to complete the `download` command will vary.  
The `process` command completes in ~7 min running time on a 2 core 2.8GHz laptop. 

Four tables are created by the script:

|         TABLE                        | DESCRIPTION                 |
|--------------------------------------|-----------------------------|
|`fiss_fish_obsrvtn_pnt_sp`            | Source fish observation points | 
|`wdic_waterbodies`                    | Source lookup for relating 1:50,000 waterbody identifiers | 
|`whse_fish.fiss_fish_obsrvtn_distinct`| Output distinct observation points |
|`whse_fish.fiss_fish_obsrvtn_events`  | Output distinct observation points stored as linear locations on `whse_basemapping.fwa_stream_networks_sp` |

Note that the two output tables store the source id and species codes values (`fish_observation_point_id`, `species_code`) as arrays in columns `obs_ids` and `species_codes`. This enables storing multiple observations at a single location within a single record.

```
postgis=# \d whse_fish.fiss_fish_obsrvtn_distinct
                      Table "whse_fish.fiss_fish_obsrvtn_distinct"
            Column             |         Type          | Collation | Nullable | Default
-------------------------------+-----------------------+-----------+----------+---------
 fiss_fish_obsrvtn_distinct_id | bigint                |           | not null |
 obs_ids                       | integer[]             |           |          |
 utm_zone                      | smallint              |           |          |
 utm_easting                   | integer               |           |          |
 utm_northing                  | integer               |           |          |
 wbody_id                      | double precision      |           |          |
 waterbody_type                | character varying(20) |           |          |
 new_watershed_code            | character varying(56) |           |          |
 species_codes                 | character varying[]   |           |          |
 geom                          | geometry              |           |          |
 watershed_group_code          | text                  |           |          |
Indexes:
    "fiss_fish_obsrvtn_distinct_pkey" PRIMARY KEY, btree (fiss_fish_obsrvtn_distinct_id)
    "fiss_fish_obsrvtn_distinct_gidx" gist (geom)
    "fiss_fish_obsrvtn_distinct_wbidix" btree (wbody_id)


postgis=# \d whse_fish.fiss_fish_obsrvtn_events
                      Table "whse_fish.fiss_fish_obsrvtn_events"
            Column             |        Type         | Collation | Nullable | Default
-------------------------------+---------------------+-----------+----------+---------
 fiss_fish_obsrvtn_distinct_id | bigint              |           | not null |
 wscode_ltree                  | ltree               |           |          |
 localcode_ltree               | ltree               |           |          |
 blue_line_key                 | integer             |           |          |
 downstream_route_measure      | double precision    |           |          |
 distance_to_stream            | double precision    |           |          |
 obs_ids                       | integer[]           |           |          |
 species_codes                 | character varying[] |           |          |
Indexes:
    "fiss_fish_obsrvtn_events_pkey" PRIMARY KEY, btree (fiss_fish_obsrvtn_distinct_id)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx" gist (localcode_ltree)
    "fiss_fish_obsrvtn_events_localcode_ltree_idx1" btree (localcode_ltree)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx" gist (wscode_ltree)
    "fiss_fish_obsrvtn_events_wscode_ltree_idx1" btree (wscode_ltree)

```

Also note that not all distinct observations can be matched to a stream. Currently, about 1,200 distinct points are not close enough to a stream (or waterbody) to be matched:

```
postgis=# SELECT count(*) FROM whse_fish.fiss_fish_obsrvtn_distinct;
 count
-------
 77440
(1 row)

postgis=# SELECT count(*) FROM whse_fish.fiss_fish_obsrvtn_events;
 count
-------
 76201
(1 row)
```

# Use the data

With the observations now linked to the Freswater Atlas, we can write queries to find fish observations relative to their location on the stream network.  

For example, we could list all species observed on the Cowichan River, downstream of Skutz Falls (about 34km from the river's mouth):

```
SELECT
    array_agg(distinct_spp) AS species_codes
FROM (
    SELECT DISTINCT unnest(species_codes) AS distinct_spp
    FROM whse_fish.fiss_fish_obsrvtn_events
    WHERE
        blue_line_key = 354155148
        AND downstream_route_measure < 34180
    ORDER BY unnest(species_codes)
) AS dist_spp;

                               species_codes
----------------------------------------------------------------------------
 {ACT,AS,BNH,BT,C,CAL,CAS,CH,CM,CO,CT,DV,EB,GB,KO,L,MARFAL,RB,SA,ST,TR,TSB}
(1 row)

```

Note the use of [`unnest`](https://www.postgresql.org/docs/10/static/functions-array.html#ARRAY-FUNCTIONS-TABLE) to find distinct species.