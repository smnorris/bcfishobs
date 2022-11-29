.PHONY: all clean

PSQL = psql $(DATABASE_URL) -v ON_ERROR_STOP=1

all: qa_summary.csv

clean:
	rm -Rf .make
	rm -Rf data
	$(PSQL) -c "drop schema if exists bcfishobs cascade"

# create empty output tables and load stable supporting data
.make/setup:
	mkdir -p .make
	mkdir -p data
	# wdic waterbodies table for relating 50k waterbodies to fwa
	wget -qNP data https://hillcrestgeo.ca/outgoing/public/whse_fish/whse_fish.wdic_waterbodies.csv.zip
	unzip -qjun -d data data/whse_fish.wdic_waterbodies.csv.zip
	# load via ogr because it makes cleaning the input file easy.
	ogr2ogr \
		-f PostgreSQL \
		"PG:$(DATABASE_URL)" \
		-lco OVERWRITE=YES \
		-lco SCHEMA=whse_fish \
		-nln wdic_waterbodies_load \
		-nlt NONE \
		data/whse_fish.wdic_waterbodies.csv
	$(PSQL) -f sql/wdic_waterbodies.sql
	# species code table
	wget -qNP data https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv
	$(PSQL) -c "DROP TABLE IF EXISTS whse_fish.species_cd;"
	$(PSQL) -c "CREATE TABLE whse_fish.species_cd \
	(species_id     integer primary key, \
	code            text, \
	name            text, \
	cdcgr_code      text, \
	cdclr_code      text, \
	scientific_name text, \
	spctype_code    text, \
	spcgrp_code     text);"
	$(PSQL) -c "\copy whse_fish.species_cd FROM 'data/whse_fish_species_cd.csv' delimiter ',' csv header"
	# create empty observation table so the view query works
	bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP -s
	# create empty output tables and views
	$(PSQL) -f sql/schema.sql
	touch $@

# load source data to db, do not include "Summary" records
.make/fiss_fish_obsrvtn_pnt_sp: .make/setup
	$(PSQL) -c "truncate whse_fish.fiss_fish_obsrvtn_pnt_sp"
	bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP --query "POINT_TYPE_CODE = 'Observation'" -a
	touch $@

# process all queries and write qa file when done
qa_summary.csv: .make/setup .make/fiss_fish_obsrvtn_pnt_sp 
	$(PSQL) -f sql/01_clean-fishobs.sql
	$(PSQL) -f sql/02_create-prelim-table.sql
	$(PSQL) -f sql/03_add-waterbodies.sql
	$(PSQL) -f sql/04_add-streams-100m-lookup.sql
	$(PSQL) -f sql/05_add-streams-100m-closest.sql
	$(PSQL) -f sql/06_add-streams-100m-500m.sql
	$(PSQL) -f sql/07_load-output-tables.sql

	# Tag maximal observations for each species
	for spp_id in $(shell psql -AtX -c "SELECT DISTINCT b.species_id \
    	FROM whse_fish.fiss_fish_obsrvtn_pnt_sp a \
    	INNER JOIN whse_fish.species_cd b \
    	ON a.species_code = b.code") ; do \
	  echo $$spp_id ; \
	  $(PSQL) -f sql/08_tag_maximal_events.sql -v species=$$spp_id ; \
	done
	set -e ; psql2csv $(DATABASE_URL) < sql/qa_summary.sql > $@
	$(PSQL) -f sql/09_cleanup.sql