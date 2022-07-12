library(tidyverse)
library(sf)
library(raster)
library(lubridate)
library(rgee)
source('extractS1S2.R')
source('load_c4d_data.R')

# base parameters
# year <- '2021'
# version <- '20220710'
# probes <- st_read('../geometries/ProbeMetaData.geojson')
# T_layer <- 'T_15'
# M_layer <- 'M_15'

aggProbeInSitu <- function(year, version, probes, T_layer, M_layer) {
  
  df <- extractS1S2(year, version, probes)
  probe_sents <- df$probe_sents
  doy <- df$doy
  
  # select and filter probe data
  PM <- 
    Probe_Measurements_sf |> 
    dplyr::select(probe_id, datetime, T_layer, M_layer) |> 
    mutate(datetime = ymd_hms(datetime),
           date = date(datetime),
           doy = yday(date)) |> 
    filter(year(date) == year)
  
  # Create list dates that match S1 S2 stack
  list_dates <- doy[year(doy$date) == year & 
                     doy$date > range(PM$date)[1] &
                     doy$date < range(PM$date)[2],]
  
  # Aggregate probe data based on list dates
  PM2 <-
    PM |> 
    dplyr::select(-doy) |> 
    group_by(probe_id, dr = cut(date, 
                                breaks = c(range(date), 
                                                 as.Date(list_dates$date)), 
                                include.lowest=TRUE)) |> 
    summarise(across(where(is.numeric), function(x) { mean(x, na.rm=T)})) |> 
    rename(date = dr) |> 
    mutate(date = ymd(date))
  
  return(list('probe_sents' = probe_sents, 
              'doy' = doy,
              'probe_insitu' = PM2))
}



