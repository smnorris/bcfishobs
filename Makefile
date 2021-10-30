.PHONY: all build db clean

GENERATED_FILES = .fiss_fish_obsrvtn_pnt_sp \
	.wdic_waterbodies \
	.species_cd \
	qa_summary.csv

SPECIES = $(shell psql -AtX -c "SELECT DISTINCT b.species_id \
    FROM whse_fish.fiss_fish_obsrvtn_pnt_sp a \
    INNER JOIN whse_fish.species_cd b \
    ON a.species_code = b.code")

# Make all targets
all: $(GENERATED_FILES)

# Remove all generated targets
clean:
	rm -Rf $(GENERATED_FILES)

# load source data to db
.fiss_fish_obsrvtn_pnt_sp:
	bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP
	touch $@

# load 50k waterbody table
.wdic_waterbodies:
	wget -qNP data https://hillcrestgeo.ca/outgoing/public/whse_fish/whse_fish.wdic_waterbodies.csv.zip
	unzip -qjun -d data data/whse_fish.wdic_waterbodies.csv.zip
	# load via ogr because it makes cleaning the input file easy.
	# ?application_name=foo is a workaround for a gdal issue on macos
	ogr2ogr \
		-f PostgreSQL \
		"PG:$(DATABASE_URL)?application_name=foo" \
		-lco OVERWRITE=YES \
		-lco SCHEMA=whse_fish \
		-nln wdic_waterbodies_load \
		-nlt NONE \
		data/whse_fish.wdic_waterbodies.csv
	touch $@

# load species code table
.species_cd:
	wget -qNP data https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv
	psql -c "DROP TABLE IF EXISTS whse_fish.species_cd;"
	psql -c "CREATE TABLE whse_fish.species_cd \
	(species_id     integer primary key, \
	code            text, \
	name            text, \
	cdcgr_code      text, \
	cdclr_code      text, \
	scientific_name text, \
	spctype_code    text, \
	spcgrp_code     text);"
	psql -c "\copy whse_fish.species_cd FROM 'data/whse_fish_species_cd.csv' delimiter ',' csv header"
	touch $@

# process all queries and write qa file when done
qa_summary.csv: .species_cd .wdic_waterbodies .fiss_fish_obsrvtn_pnt_sp
	psql -c "CREATE EXTENSION IF NOT EXISTS intarray"
	psql -c "CREATE SCHEMA IF NOT EXISTS bcfishobs"
	psql -f sql/01_clean-fishobs.sql
	psql -f sql/02_clean-wdic.sql
	psql -f sql/03_create-prelim-table.sql
	psql -f sql/04_add-waterbodies.sql
	psql -f sql/05_add-streams-100m-lookup.sql
	psql -f sql/06_add-streams-100m-closest.sql
	psql -f sql/07_add-streams-100m-500m.sql
	psql -f sql/08_create-output-tables.sql
	# Tag maximal observations for each species
	for spp_id in $(SPECIES) ; do \
	  echo $$spp_id ; \
	  psql -v ON_ERROR_STOP=1 -f sql/10_tag_maximal_events.sql -v species=$$spp_id ; \
	done
	psql2csv < sql/qa_summary.sql > $@
	psql -f sql/11_cleanup.sql

