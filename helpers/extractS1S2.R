library(tidyverse)
library(sf)
library(raster)
library(lubridate)
library(rgee)
ee_Initialize(user = 'edgar.manrique30@gmail.com')
## Load EE asset

# year <- '2021'
# version <- '20220710'
# probes <- st_read('../geometries/ProbeMetaData.geojson')

extractS1S2 <- function(year, version, probes) {
  # GEE asset
  gee_id <- paste0('users/edgarmanrique30/c4d_s1s2Stack_10m_10D_3857_', year, '_', version)
  img <- ee$Image(gee_id)
  # Load Probes data and additional layers
  bodentyp <- raster('OtherLayers/BodentypRasterESC.grd')
  bodenart <- raster('OtherLayers/BodenartRasterESC.grd')
  landnutzung <- raster('OtherLayers/LandnutzungRasterESC.grd')
  esc <- raster('OtherLayers/ESCRasterESC.grd')
  # Extract texture, soil type,landuse, and environmental soil class from rasters to points
  probes <- probes |> 
    mutate(bodentyp = raster::extract(bodentyp, probes),
           bodenart = raster::extract(bodenart, probes),
           landnutzung = raster::extract(landnutzung, probes),
           envSoilClass = raster::extract(esc, probes))
  # Extract Sentinel 2 and Sentinel 1 bands from EE asset to points
  probes_rs <- ee_extract(x = img, y = probes[c("probe_id", 
                                                'bodentyp',
                                                'bodenart',
                                                'landnutzung',
                                                'envSoilClass')], 
                          sf = FALSE, scale = 10)
  
  # From wide to long
  Probe_RS_2021_10D <- 
    probes_rs |> 
    pivot_longer(cols = c(B1:VV_9), 
                 names_to = c('band', 'date'),
                 names_sep = '_') |> 
    mutate(
      bodentyp = case_when(bodentyp == 1 ~ 'Organish',
                           bodentyp == 2 ~ 'Semi-terrestrisch',
                           bodentyp == 3 ~ 'Stauwasser',
                           bodentyp == 4 ~ 'Terrestrisch',
                           bodentyp == 5 ~ 'Wasser'),
      bodenart = case_when(bodenart == 10 ~ 'Ton',
                           bodenart == 20 ~ 'Schutt',
                           bodenart == 30 ~ 'Lehm',
                           bodenart == 40 ~ 'Organisch',
                           bodenart == 50 ~ 'Sand',
                           bodenart == 60 ~ 'Schluff',
                           bodenart == 70 ~ 'Wasser'),
      landnutzung = case_when(landnutzung == 1100 ~ 'Nadelwald',
                              landnutzung == 1200 ~ 'Laubwald',
                              landnutzung == 1300 ~ 'Entwaldet',
                              landnutzung == 1400 ~ 'Mischwald',
                              landnutzung == 1500 ~ 'Acker',
                              landnutzung == 1600 ~ 'Grünland',
                              landnutzung == 1700 ~ 'Moor',
                              landnutzung == 1800 ~ 'Sumpf',
                              landnutzung == 1900 ~ 'Ohne vegetation',
                              landnutzung == 2000 ~ 'Siedlung',
                              landnutzung == 2100 ~ 'Strasse',
                              landnutzung == 2200 ~ 'Wasser',)) |> 
    mutate(value = replace(value, value == 1, NA)) |> 
    mutate(date = replace(date, is.na(date), 0)) 
  # Extract Doy of the year time intervals to derive date
  doy <- 
    Probe_RS_2021_10D |> 
    dplyr::filter(band == 'doy') |> 
    dplyr::select(date, value) |> 
    group_by(date) |> 
    summarise(value = mean(value)) |> 
    mutate(date2 = ymd(strptime(paste(year, value), format="%Y %j")),
           date2 = replace(date2, is.na(date2), paste0(year, '-12-31'))) |> 
    rename(doy = value)
  
  Probe_RS_2021_10D <- left_join(Probe_RS_2021_10D, doy, by = "date") |> 
    rename(time_step = date, date = date2) |> 
    filter(band != 'doy') |> 
    mutate(value = value / 10000)
  
  doy <- doy |> rename(time_step = date, date = date2) |> 
    arrange(doy)
  
  return(list('probe_sents' = Probe_RS_2021_10D, 
           'doy' = doy))
}

