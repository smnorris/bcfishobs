import click
import pgdata

db = pgdata.connect()

species_ids = db.query(
    """
    SELECT DISTINCT a.species_code, b.species_id
    FROM whse_fish.fiss_fish_obsrvtn_pnt_sp a
    INNER JOIN whse_fish.species_cd b
    ON a.species_code = b.code
    ORDER BY species_code
    """
).fetchall()

# tag maximal species
for row in species_ids:
    click.echo("Processing species: " + row["species_code"])
    sql = db.queries["10_tag_maximal_events"]
    db.execute(sql, (row["species_id"], row["species_id"], row["species_id"], row["species_id"]))
