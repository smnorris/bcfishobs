.PHONY: all clean

GENERATED_FILES = .make/fiss_fish_obsrvtn_pnt_sp \
	.make/wdic_waterbodies \
	.make/species_cd \
	qa_summary.csv

SPECIES = $(shell psql -AtX -c "SELECT DISTINCT b.species_id \
    FROM whse_fish.fiss_fish_obsrvtn_pnt_sp a \
    INNER JOIN whse_fish.species_cd b \
    ON a.species_code = b.code")

PSQL = psql $(DATABASE_URL) -v ON_ERROR_STOP=1

# Make all targets
all: $(GENERATED_FILES)

# Remove all generated targets
clean:
	rm -Rf .make
	rm -Rf data
	$(PSQL) -c "drop schema if exists bcfishobs cascade"

# load source data to db, do not include "Summary" records
.make/fiss_fish_obsrvtn_pnt_sp:
	bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP --query "POINT_TYPE_CODE = 'Observation'"
	mkdir -p .make
	touch $@

# load 50k waterbody table
.make/wdic_waterbodies: sql/wdic_waterbodies.sql
	mkdir -p data
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
	$(PSQL) -f $<
	mkdir -p .make
	touch $@

# load species code table
.make/species_cd:
	mkdir -p data
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
	mkdir -p .make
	touch $@

# process all queries and write qa file when done
qa_summary.csv: .make/species_cd .make/wdic_waterbodies .make/fiss_fish_obsrvtn_pnt_sp
	$(PSQL) -c "CREATE EXTENSION IF NOT EXISTS intarray"
	$(PSQL) -c "CREATE SCHEMA IF NOT EXISTS bcfishobs"
	$(PSQL) -f sql/01_clean-fishobs.sql
	$(PSQL) -f sql/02_create-prelim-table.sql
	$(PSQL) -f sql/03_add-waterbodies.sql
	$(PSQL) -f sql/04_add-streams-100m-lookup.sql
	$(PSQL) -f sql/05_add-streams-100m-closest.sql
	$(PSQL) -f sql/06_add-streams-100m-500m.sql
	$(PSQL) -f sql/07_create-output-tables.sql

	# Tag maximal observations for each species
	for spp_id in $(SPECIES) ; do \
	  echo $$spp_id ; \
	  $(PSQL) -f sql/08_tag_maximal_events.sql -v species=$$spp_id ; \
	done
	psql2csv $(DATABASE_URL) < sql/qa_summary.sql > $@
	$(PSQL) -f sql/09_cleanup.sql

