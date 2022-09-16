-- After loading the wdic_waterbodies table, clean it up and index it.

-- create wdic_waterbodies table with correct types
DROP TABLE IF EXISTS whse_fish.wdic_waterbodies;

CREATE TABLE whse_fish.wdic_waterbodies
(id integer primary key,
 type text,
 extinct_indicator text,
 watershed_id integer,
 sequence_number text,
 waterbody_identifier text,
 gazetted_name text,
 waterbody_mouth_identifier text,
 formatted_name text
 );

-- load data to new table with correct types
INSERT INTO whse_fish.wdic_waterbodies
SELECT
  id::integer,
  type,
  extinct_indicator,
  watershed_id::integer,
  sequence_number,
  waterbody_identifier,
  gazetted_name,
  waterbody_mouth_identifier,
  formatted_name
FROM whse_fish.wdic_waterbodies_load;

-- index
CREATE INDEX wdic_waterbodies_wbtrimidx ON whse_fish.wdic_waterbodies (LTRIM(waterbody_identifier,'0'));
CREATE INDEX wdic_waterbodies_typeidx ON whse_fish.wdic_waterbodies (type);

-- drop source table
DROP TABLE IF EXISTS whse_fish.wdic_waterbodies_load;