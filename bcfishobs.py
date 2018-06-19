import zipfile
try:
    from urllib.parse import urlparse
except ImportError:
     from urlparse import urlparse

import click
import gdal
from sqlalchemy.sql import text
import requests

import pgdata


def validate_email(ctx, param, value):
    if not value:
        raise click.BadParameter('Provide --email or set $BCDATA_EMAIL')
    else:
        return value


@click.group()
def cli():
    pass


@cli.command()
@click.option('--email',
              help="Email address. Default: $BCDATA_EMAIL",
              envvar='BCDATA_EMAIL',
              callback=validate_email)
@click.option('--db_url',
              help='Target database Default: $FWA_DB',
              envvar='FWA_DB')
def download(email, db_url):
    """Download observation data and load to postgres
    """

    db = pgdata.connect(db_url)
    dataset = 'known-bc-fish-observations-and-bc-fish-distributions'
    info = db.bcdata2pg(dataset, email)
    click.echo('Loaded observations to '+info['schema']+'.'+info['table'])

    # get wdic_waterbodies table
    url = 'https://hillcrestgeo.ca/outgoing/whse_fish/whse_fish.wdic_waterbodies.csv.zip'
    file_name = 'wdic_waterbodies.csv.zip'
    r = requests.get(url, stream=True)
    with open(file_name, 'wb') as f:
        for chunk in r.iter_content():
            f.write(chunk)
    zip_ref = zipfile.ZipFile(file_name, 'r')
    zip_ref.extractall()
    zip_ref.close()

    # get species table
    url = 'https://hillcrestgeo.ca/outgoing/whse_fish/species_cd.csv.zip'
    file_name = 'species_cd.csv.zip'
    r = requests.get(url, stream=True)
    with open(file_name, 'wb') as f:
        for chunk in r.iter_content():
            f.write(chunk)
    zip_ref = zipfile.ZipFile(file_name, 'r')
    zip_ref.extractall()
    zip_ref.close()

    # load the waterbodies and species to the db by letting ogr parse the csvs
    u = urlparse(db_url)
    gdal_pg = "PG:host='{h}' port='{p}' dbname='{db}' user='{usr}' password='{pwd}'".format(
        h=u.hostname,
        p=u.port,
        db=u.path[1:],
        usr=u.username,
        pwd=u.password
    )
    gdal.VectorTranslate(
        gdal_pg,
        'whse_fish.wdic_waterbodies.csv',
        format='PostgreSQL',
        layerName='wdic_waterbodies_load',
        accessMode='overwrite',
        layerCreationOptions=['OVERWRITE=YES',
                              'SCHEMA=whse_fish']
    )
    gdal.VectorTranslate(
        gdal_pg,
        'species_cd.csv',
        format='PostgreSQL',
        layerName='species_cd',
        accessMode='overwrite',
        layerCreationOptions=['OVERWRITE=YES',
                              'SCHEMA=whse_fish']
    )


@cli.command()
@click.option('--db_url',
              help='Target database Default: $FWA_DB',
              envvar='FWA_DB')
@click.option('--no-cleanup', '-c', is_flag=True, default=False)
def process(db_url, no_cleanup):
    """ Clean observations, reference to the stream network, write outputs
    """
    db = pgdata.connect(db_url)

    db.execute(db.queries['01_clean-fishobs'])
    db.execute(db.queries['02_clean-wdic'])
    db.execute(db.queries['03_create-prelim-table'])
    db.execute(db.queries['04_add-waterbodies'])
    db.execute(db.queries['05_add-streams-100m-lookup'])
    db.execute(db.queries['06_add-streams-100m-closest'])
    db.execute(db.queries['07_add-streams-100m-500m'])
    db.execute(db.queries['08_create-outputs'])
    db.execute(db.queries['09_create-events-vw'])

    # for all species in the database, flag observation events that have no
    # other observations of the same species upstream - 'maximal' events
    species_codes = db.query("""SELECT DISTINCT species_code
                                FROM whse_fish.fiss_fish_obsrvtn_pnt_sp
                                ORDER BY species_code""").fetchall()
    for row in species_codes:
        species = row['species_code']
        click.echo('Processing species: ' + species)
        sql = db.queries['10_tag_maximal_events']
        db.execute(sql, (species, species, species, species))

    if not no_cleanup:
        db.execute(db.queries['11_cleanup'])

    # report on the results, dumping to stdout
    matches = db.query(db.queries['qa_match_report'])
    click.echo(
        "{}| {}| {}".format(
            'match_type'.ljust(65),
            'n_distinct_events'.ljust(15),
            'n_observations'.ljust(15)
        )
    )
    click.echo('----------------------------------------------------------------------'
               '----------------------------')
    for row in matches:
        click.echo(
            "{}| {}| {}".format(
                row['match_type'].ljust(65),
                str(row['n_distinct_events']).ljust(15),
                str(row['n_observations']).ljust(15)
            )
        )


if __name__ == '__main__':
    cli()
