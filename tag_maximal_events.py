import click
import pgdata

db = pgdata.connect()

species_codes = db.query(
    """
    SELECT DISTINCT species_code
    FROM whse_fish.fiss_fish_obsrvtn_pnt_sp
    ORDER BY species_code
    """
).fetchall()

# tag maximal species
for row in species_codes:
    species = row["species_code"]
    click.echo("Processing species: " + species)
    sql = db.queries["10_tag_maximal_events"]
    db.execute(sql, (species, species, species, species))
