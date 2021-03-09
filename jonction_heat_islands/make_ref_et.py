import logging
from os import environ

import click
import dotenv
import numpy as np
import pyeto
import rasterio as rio
import rioxarray
import salem
import swiss_uhi_utils as suhi
import xarray as xr
from rasterio import features
from shapely import geometry

from jonction_heat_islands import settings

# 46.2012 degrees in radians
JONCTION_LAT = 0.8063630583724042


@click.command()
@click.argument('ref_raster_filepath', type=click.Path(exists=True))
@click.argument('year')
@click.argument('dst_filepath', type=click.Path())
@click.option('--align/--no-align', default=True)
@click.option('--buffer-dist', type=float, default=2000)
def main(ref_raster_filepath, year, dst_filepath, align, buffer_dist):
    logger = logging.getLogger(__name__)

    suhi.settings.METEOSWISS_S3_CLIENT_KWARGS = {
        'endpoint_url': environ.get('S3_ENDPOINT_URL')
    }

    with rio.open(ref_raster_filepath) as src:
        # get the (valid data) extent of the raster
        ref_raster_extent_geom = [
            geometry.shape(geom)
            for geom, val in features.shapes(src.dataset_mask(),
                                             transform=src.transform)
            if val != 0
        ][0]

        # get the monthly mean temperature data array of the reference year for
        # the raster extent
        monthly_T_da = suhi.open_meteoswiss_s3_ds(
            year,
            'TabsD',
            geom=ref_raster_extent_geom.buffer(buffer_dist),
            crs=src.crs.to_string(),
            roi=False)['TabsD']
    attrs = monthly_T_da.attrs.copy()
    monthly_T_da = monthly_T_da.resample(time='1MS').mean(dim='time')

    # select the hottest month
    hottest_month_i = monthly_T_da.mean(dim=['x', 'y']).argmax()
    hottest_month_T_da = monthly_T_da.isel(time=hottest_month_i)
    # hottest_month_T_da.attrs['pyproj_srs'] = attrs['pyproj_srs']

    # potential evapotranspiration (Thornthwaite, 1948)
    year_heat_index = monthly_T_da.groupby('time').apply(
        lambda temp: (temp / 5)**1.514).sum(dim='time')
    year_alpha = .49239 + .01792 * year_heat_index - \
        .0000771771 * year_heat_index**2 + .000000675 * year_heat_index**3
    pe_da = xr.full_like(hottest_month_T_da, np.nan)
    pe_da = pe_da.where(
        ~(hottest_month_T_da >= 26.5),
        -415.85 + 32.24 * hottest_month_T_da - .43 * hottest_month_T_da**2)
    pe_da = pe_da.where(
        ~((hottest_month_T_da > 0) & (hottest_month_T_da < 26.5)),
        16 * ((10 * (hottest_month_T_da / year_heat_index))**year_alpha))
    pe_da = pe_da.where(~(hottest_month_T_da <= 0), 0)
    pe_da *= pyeto.monthly_mean_daylight_hours(JONCTION_LAT)[
        hottest_month_i.item()] / 12
    pe_da.attrs['pyproj_srs'] = attrs['pyproj_srs']

    if align:
        # align it to the reference raster
        ref_ds = salem.open_xr_dataset(ref_raster_filepath)
        pe_da = suhi.align_ds(pe_da, ref_ds)

    # write the raster
    pe_da.rio.set_crs(pe_da.attrs['pyproj_srs']).rio.to_raster(dst_filepath)
    logger.info("dumped reference evapotranspiration raster to %s",
                dst_filepath)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format=settings.DEFAULT_LOG_FMT)

    # find .env automagically by walking up directories until it's found, then
    # load up the .env entries as environment variables
    dotenv.load_dotenv(dotenv.find_dotenv())

    main()
