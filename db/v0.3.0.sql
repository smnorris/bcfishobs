BEGIN;

-- fix observation geometry type - point not multipoint
drop table whse_fish.fiss_fish_obsrvtn_pnt_sp cascade;

create table whse_fish.fiss_fish_obsrvtn_pnt_sp (
 fish_observation_point_id numeric                  ,
 wbody_id                  numeric                  ,
 species_code              character varying(6)     ,
 agency_id                 numeric                  ,
 point_type_code           character varying(20)    ,
 observation_date          date                     ,
 agency_name               character varying(60)    ,
 source                    character varying(1000)  ,
 source_ref                character varying(4000)  ,
 utm_zone                  numeric                  ,
 utm_easting               numeric                  ,
 utm_northing              numeric                  ,
 activity_code             character varying(100)   ,
 activity                  character varying(300)   ,
 life_stage_code           character varying(100)   ,
 life_stage                character varying(300)   ,
 species_name              character varying(60)    ,
 waterbody_identifier      character varying(9)     ,
 waterbody_type            character varying(20)    ,
 gazetted_name             character varying(30)    ,
 new_watershed_code        character varying(56)    ,
 trimmed_watershed_code    character varying(56)    ,
 acat_report_url           character varying(254)   ,
 feature_code              character varying(10)    ,
 objectid                  numeric                  ,
 geom                      geometry(Point,3005)
);


create table bcfishobs.observations (
 observation_key           text  primary key        ,
 linear_feature_id         integer,
 wscode                    ltree,
 localcode                 ltree,
 blue_line_key             integer,
 watershed_group_code      character varying(4),
 downstream_route_measure  double precision,
 fwa_match_type            text,
 maximal_species           boolean,
 distances_to_stream       double precision,
 wbody_id                  numeric                  ,
 species_code              character varying(6)     ,
 agency_id                 numeric                  ,
 point_type_code           character varying(20)    ,
 observation_date          date                     ,
 agency_name               character varying(60)    ,
 source                    character varying(1000)  ,
 source_ref                character varying(4000)  ,
 utm_zone                  numeric                  ,
 utm_easting               numeric                  ,
 utm_northing              numeric                  ,
 activity_code             character varying(100)   ,
 activity                  character varying(300)   ,
 life_stage_code           character varying(100)   ,
 life_stage                character varying(300)   ,
 species_name              character varying(60)    ,
 waterbody_identifier      character varying(9)     ,
 waterbody_type            character varying(20)    ,
 gazetted_name             character varying(30)    ,
 new_watershed_code        character varying(56)    ,
 trimmed_watershed_code    character varying(56)    ,
 acat_report_url           character varying(254)   ,
 feature_code              character varying(10)    ,
 objectid                  numeric                  ,
 geom                      geometry(Point,3005)
);
create index on bcfishobs.observations (linear_feature_id);
create index on bcfishobs.observations (blue_line_key);
create index on bcfishobs.observations (wscode);
create index on bcfishobs.observations (localcode);
create index on bcfishobs.observations using gist (wscode);
create index on bcfishobs.observations using gist (localcode);
create index on bcfishobs.observations using gist (geom);

COMMIT;