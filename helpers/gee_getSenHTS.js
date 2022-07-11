// https://github.com/SoilWatch/ee-dynamic-time-warping/blob/master/examples/twdtw_sudan.js

var roi = ee.Geometry.Polygon(
    [[[11.73463, 50.0568 ],
      [12.00268, 50.0568 ],
      [12.00268, 50.22379 ],
      [11.73463, 50.22379 ]]], null, false);


var roi_points = ee.FeatureCollection("users/edgarmanrique30/ProbeMetaData");
var start_date = '2022-01-01';
var end_date = '2023-01-01';
//------ Import external dependencies
var palettes = require('users/gena/packages:palettes');
var wrapper = require('users/adugnagirma/gee_s1_ard:wrapper');
var S2Masks = require('users/soilwatch/soilErosionApp:s2_masks.js');
var composites = require('users/soilwatch/soilErosionApp:composites.js');

//------ Input data parameters
var AGG_INTERVAL = 10; // Number of days to use to create the temporal composite
//var TIMESERIES_LEN = 12; // Number of timestamps in the time series
//var PATTERNS_LEN = 12; // Number of timestamps for the reference data points
var S2_BAND_LIST = ['B1','B2', 'B3','B4','B5','B6','B7','B8','B9', 'NDVI', 'EVI', 'NDWI', 'SAVI', 'GCVI']; // S2 Bands to use as input
var S1_BAND_LIST = ['VV', 'VH']; // S1 Bands to use as input
var BAND_NO = S1_BAND_LIST.concat(S2_BAND_LIST).length; // Number of bands to use.
var DOY_BAND = 'doy'; // Name of the Day of Year band

// Import external water mask dataset
var not_water = ee.Image("JRC/GSW1_2/GlobalSurfaceWater").select('max_extent').eq(0); // JRC Global Surface Water mask

// Import ALOS AW3D30 latest DEM version v3.2
var dem = ee.ImageCollection("JAXA/ALOS/AW3D30/V3_2").select("DSM");
dem = dem.mosaic().setDefaultProjection(dem.first().select(0).projection());

//Remove mountain areas that are not suitable for crop growth
var slope = ee.Terrain.slope(dem); // Calculate slope from the DEM data
var dem_mask = dem.lt(3600); // Mask elevation above 3600m, where no crops grow.
var slope_mask = slope.lt(30); // Mask slopes steeper than 30°, where no crops grow.
var crop_mask = dem_mask.and(slope_mask); // Combine the two conditions

// Function to calculate the indices
function addIndeces(img) {
var ndvi = img.expression('(NIR-RED)/(NIR+RED)', {
          'NIR': img.select('B8'),
          'RED': img.select('B4')
          }).multiply(10000).toInt16().rename('NDVI');

var ndwi = img.expression('(NIR-SWIR)/(NIR+SWIR)', {
          'NIR': img.select('B8'),
          'SWIR': img.select('B11')
          }).multiply(10000).toInt16().rename('NDWI');
          
var evi = img.expression(
  '2.5 * ((NIR - RED) / (NIR + 6 * RED - 7.5 * BLUE + 1))', {
  'NIR': img.select('B8'),
  'RED': img.select('B4'),
  'BLUE': img.select('B2')}).multiply(10000).toInt16().rename('EVI');

var savi = img.expression(
  '1.5 * ((NIR - RED) / (NIR + RED + 0.5))', {
  'NIR': img.select('B8'),
  'RED': img.select('B4')}).multiply(10000).toInt16().rename('SAVI');
  
var gcvi = img.expression(
  '(NIR / GREEN) - 1', {
  'NIR': img.select('B8'),
  'GREEN': img.select('B3')}).multiply(10000).toInt16().rename('GCVI');

return img.addBands(ndvi).addBands(ndwi).addBands(evi).addBands(savi).addBands(gcvi);

}
var date_range = ee.Dictionary({'start': start_date, 'end': end_date}); 
// Load the Sentinel-2 collection for the time period and area requested
var collection_type = "COPERNICUS/S2_SR"
var s2_cl = S2Masks.loadImageCollection(collection_type, date_range, roi);

// Perform cloud masking using the S2 cloud probabilities assets from s2cloudless,
// courtesy of Sentinelhub/EU/Copernicus/ESA
var masked_collection = s2_cl
                    .filterDate(date_range.get('start'), date_range.get('end'))
                    .map(S2Masks.addCloudShadowMask(not_water, 1e4))
                    .map(S2Masks.applyCloudShadowMask)
                    .map(addIndeces); 

// Generate a list of time intervals for which to generate a harmonized time series
var time_intervals = composites.extractTimeRanges(date_range.get('start'), date_range.get('end'), 10);

// Generate harmonized monthly time series of FCover as input to the vegetation factor V
var s2_stack = composites.harmonizedTS(masked_collection, S2_BAND_LIST, time_intervals, {agg_type: 'geomedian'});

// Define S1 preprocessing parameters, as per:
// Version: v1.2
// Date: 2021-03-10
// Authors: Mullissa A., Vollrath A., Braun, C., Slagter B., Balling J., Gou Y., Gorelick N.,  Reiche J.
// Sentinel-1 SAR Backscatter Analysis Ready Data Preparation in Google Earth Engine. Remote Sensing 13.10 (2021): 1954.
// Description: This script creates an analysis ready S1 image collection.
// License: This code is distributed under the MIT License.
var parameter = {//1. Data Selection
             START_DATE: date_range.get('start'),
             STOP_DATE: date_range.get('end'),
             POLARIZATION:'VVVH', // The polarization available may differ depending on where you are on the globe
             ORBIT : 'DESCENDING', // The orbit availability may differ depending on where you are on the globe
             // Check out this page to find out what parameters suit your area:
             // https://sentinels.copernicus.eu/web/sentinel/missions/sentinel-1/observation-scenario
             GEOMETRY: roi,
             //2. Additional Border noise correction
             APPLY_ADDITIONAL_BORDER_NOISE_CORRECTION: true,
             //3.Speckle filter
             APPLY_SPECKLE_FILTERING: true,
             SPECKLE_FILTER_FRAMEWORK: 'MULTI',
             SPECKLE_FILTER: 'LEE',
             SPECKLE_FILTER_KERNEL_SIZE: 9,
             SPECKLE_FILTER_NR_OF_IMAGES: 10,
             //4. Radiometric terrain normalization
             APPLY_TERRAIN_FLATTENING: true,
             DEM: dem,
             TERRAIN_FLATTENING_MODEL: 'VOLUME', // More desirable for vegetation monitoring.
                                                 //Use "SURFACE" if working on urban or bare soil applications
             TERRAIN_FLATTENING_ADDITIONAL_LAYOVER_SHADOW_BUFFER: 0,
             //5. Output
             FORMAT : 'DB',
             CLIP_TO_ROI: false,
             SAVE_ASSETS: false
}

//Preprocess the S1 collection
var s1_ts = wrapper.s1_preproc(parameter)[1]
        .map(function(image){return image.multiply(1e4).toInt16() // Convert to Int16 using 10000 scaling factor
                                    .set({'system:time_start': image.get('system:time_start')})});

// Create equally-spaced temporal composites covering the date range and convert to multi-band image
var s1_stack = composites.harmonizedTS(s1_ts, S1_BAND_LIST, time_intervals, {agg_type: 'geomedian'});
                    //.iterate(function(image, previous){return ee.Image(previous).addBands(image)}, ee.Image([])));

var filter = ee.Filter.equals({
leftField: 'system:time_start',
rightField: 'system:time_start'
});

// Create the join.
var simpleJoin = ee.Join.inner();

// Inner join
var innerJoin = ee.ImageCollection(simpleJoin.apply(s1_stack, s2_stack, filter))

var joined = innerJoin.map(function(feature) {
return ee.Image.cat(feature.get('primary'), feature.get('secondary'));
});

joined = joined.map(function(image){
var currentDate = ee.Date(image.get('system:time_start'));
var meanImage = joined.filterDate(currentDate.advance(-AGG_INTERVAL-1, 'day'),
                                   currentDate.advance(AGG_INTERVAL+1, 'day')).mean();
// replace all masked values
var ddiff = currentDate.difference(ee.Date(ee.String(date_range.get('start')))
                                 .format('YYYY').cat('-01-01'),
                                 'day');
return meanImage.where(image, image).unmask(0)
.addBands(ee.Image(ddiff).rename('doy').toInt16())
.set({'doy': ddiff.toInt16()})
.copyProperties(image, ['system:time_start']);
}).sort('system:time_start');

var s1s2_stack = ee.Image(joined.iterate(function(image, previous){return ee.Image(previous).addBands(image)}, ee.Image([])))
             .select(ee.List(S1_BAND_LIST.concat(S2_BAND_LIST)).add(DOY_BAND).map(function(band){return ee.String(band).cat('.*')}));

var band_names = s1s2_stack.bandNames();

//print(band_names)

// Image Visualization Parameters for the multi-temporal ndvi composite
var imageVisParam = {bands: ["NDVI_5", "NDVI_3", "NDVI_1"],
                 gamma: 1,
                 max: 7000,
                 min: 1000,
                 opacity: 1
};
/*
// Visualization

Map.setCenter(11.8687, 50.1059, 12)
Map.addLayer(s1s2_stack.clip(roi), imageVisParam, 'ndvi stack');

imageVisParam['bands'] = ["VV_5", "VV_3", "VV_1"];
Map.addLayer(s1s2_stack.clip(roi), imageVisParam, 'VV stack');
*/


// Export image to asset

Export.image.toAsset({
image: s1s2_stack,
region: roi,
scale: 10,
description: 'c4d_s1s2Stack_10m_10D_3857_2022_20220710',
assetId:  'c4d_s1s2Stack_10m_10D_3857_2022_20220710',
maxPixels: 1e13
})
/*
// Export
var sampledReg = ee.Image(s1s2_stack)
  .sampleRegions({
    // Get the sample from the points FeatureCollection.
    collection: roi_points,
    // Properties from the points collection to pass on to the sampled info
    properties: ['probe_d'],
    // Set the scale to get Sentinel pixels in the FeatureCollection.
    scale: 10,
    tileScale: 8,
    // Return geometries
    geometries: true
  });
  
// Transform coordinates into properties in the table.
var featColExport = sampledReg.map(function (feature) {
// Get geometry
var coordinates = feature.geometry()
                      // Transform it to the desired EPSG code. Here WGS 84
                      .transform('epsg:4326')
                      // Get coordinates as a list
                      .coordinates();
// Get both entries of coordinates and set them as new properties
var resul = feature.set('lon', coordinates.get(0), 
                 'lat', coordinates.get(1));
// Remove geometry                   
return resul.setGeometry(null);
});

Export.table.toDrive({
collection: featColExport,
description: 'carbon4d_S1S2_20220708',
fileFormat: 'CSV',
folder: 'carbon4dGEExport',
});
*/