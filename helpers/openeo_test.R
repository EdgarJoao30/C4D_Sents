library(openeo)
con = connect(host = "https://openeo.cloud")
#con2 = connect(host="https://earthengine.openeo.org")
login()

collections = list_collections()

p <- processes()

aoa <- list(west = 11.73463, south = 50.0568, east = 12.00268, north = 50.22379) 
t <- c("2021-01-01", "2022-07-13")

cube_s2 <- p$load_collection(
  id = 'SENTINEL2_L2A_SENTINELHUB',
  spatial_extent = aoa,
  temporal_extent = t,
  bands=c("B02", "B03", "B04", "B05", "B06", "B07", "B08", "B8A", "B11", "B12")
)

cube_SCL <- p$load_collection(
  id = 'SENTINEL2_L2A_SENTINELHUB',
  spatial_extent = aoa,
  temporal_extent = t,
  bands=c("SCL")
)

clouds_ <- function(data, context) {
  SCL <- data[1] # select SCL band
  # we wanna keep:
  veg <- p$eq(SCL, 4) # select pixels with the respective codes
  no_veg <- p$eq(SCL, 5)
  water <- p$eq(SCL, 6)
  unclassified <- p$eq(SCL, 7)
  snow <- p$eq(SCL, 11)
  # or has only 2 arguments so..
  or1 <- p$or(veg, no_veg)
  or2 <- p$or(water, unclassified)
  or3 <- p$or(or2, snow)
  # create mask
  return(p$not(p$or(or1, or3)))
}

cube_SCL_mask <- p$reduce_dimension(data = cube_SCL, reducer = clouds_, dimension = "bands")

cube_s2_masked <- p$mask(cube_s2, cube_SCL_mask)

cube_s2_yearly_composite <- p$reduce_dimension(cube_s2_masked, function(x, context) {
  p$median(x, ignore_nodata = TRUE)
}, "t")

ndvi_ <- function(x, context) {
  b4 <- x[3]
  b8 <- x[7]
  return(p$normalized_difference(b8, b4))
}

evi_ <- function(x, context) {
  b2 <- x[1]
  b4 <- x[3]
  b8 <- x[7]
  return((2.5 * (b8 - b4)) / ((b8 + 6 * b4 - 7.5 * b2) + 1))
}

cube_s2_yearly_ndvi <- p$reduce_dimension(cube_s2_yearly_composite, ndvi_, "bands")
cube_s2_yearly_ndvi <- p$add_dimension(cube_s2_yearly_ndvi, name = "bands", label = "NDVI", type = "bands")

cube_s2_yearly_evi <- p$reduce_dimension(cube_s2_yearly_composite, evi_, "bands")
cube_s2_yearly_evi <- p$add_dimension(cube_s2_yearly_evi, name = "bands", label = "EVI", type = "bands")

cube_s2_yearly_merge1 <- p$merge_cubes(cube_s2_yearly_composite, cube_s2_yearly_ndvi)
cube_s2_yearly_merge2 <- p$merge_cubes(cube_s2_yearly_merge1, cube_s2_yearly_evi)

res <- p$save_result(data = cube_s2_yearly_merge2, format = "GTiff")
