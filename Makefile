.PHONY: all clean

PSQL = psql $(DATABASE_URL)?keepalives_idle=240 -v ON_ERROR_STOP=1

all: .make/process

clean:
	rm -Rf .make
	rm -Rf data
	$(PSQL) -f sql/clean.sql

# create empty output tables and load stable supporting data
.make/setup:
	mkdir -p .make
	mkdir -p data
	# create db schema
	bcdata bc2pg -e -c 1 WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP
	$(PSQL) -f sql/schema.sql
	touch $@

.make/load_static: .make/setup
	$(PSQL) -c "truncate whse_fish.wdic_waterbodies"
	$(PSQL) -c "\copy whse_fish.wdic_waterbodies FROM PROGRAM 'curl -s https://www.hillcrestgeo.ca/outgoing/public/whse_fish/whse_fish.wdic_waterbodies.csv.gz | gunzip' delimiter ',' csv header"
	$(PSQL) -c "truncate whse_fish.species_cd"
	$(PSQL) -c "\copy whse_fish.species_cd FROM PROGRAM 'curl -s https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv' delimiter ',' csv header"
	touch $@

# load/refresh observation data
.make/fiss_fish_obsrvtn_pnt_sp: .make/setup
	bcdata bc2pg -r WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP --query "POINT_TYPE_CODE = 'Observation'"
	touch $@

# run the job
.make/process: .make/setup .make/load_static .make/fiss_fish_obsrvtn_pnt_sp
	$(PSQL) -f sql/01_clean-fishobs.sql
	$(PSQL) -f sql/02_create-prelim-table.sql
	$(PSQL) -f sql/03_add-waterbodies.sql
	$(PSQL) -f sql/04_add-streams.sql
	$(PSQL) -f sql/05_fiss_fish_obsrvtn_events.sql
	$(PSQL) -f sql/06_fiss_fish_obsrvtn_unmatched.sql
	$(PSQL) -f sql/07_summary.sql