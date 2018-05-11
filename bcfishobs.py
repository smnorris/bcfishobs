import zipfile
try:
    from urllib.parse import urlparse
except ImportError:
     from urlparse import urlparse

import click
import gdal
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
    click.echo('Loaded observations to '+info['schema']+'.'+info['table'] + ' loaded')

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

    # load the waterbodies to the db by letting ogr parse the csv
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


@cli.command()
@click.option('--db_url',
              help='Target database Default: $FWA_DB',
              envvar='FWA_DB')
def process(db_url):
    """ Clean observation data and reference it to the stream network
    """
    db = pgdata.connect(db_url)
    db.execute(db.queries['01_fishobs_clean'])
    db.execute(db.queries['02_wdic_clean'])
    db.execute(db.queries['03_fishobs_reference'])


if __name__ == '__main__':
    cli()
