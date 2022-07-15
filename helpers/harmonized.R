library(tidyverse)
library(sf)
library(raster)
library(lubridate)
library(rgee)
source('helpers/aggProbeInSitu.R')

year <- '2021'
version <- '20220710'
probes <- st_read('layers/ProbeMetaData.geojson')
T_layer <- 'T_15'
M_layer <- 'M_15'

df2021 <- aggProbeInSitu(year, version, probes, T_layer, M_layer)
sents2021 <- df2021$probe_sents
doy2021 <- df2021$doy
insitu2021 <- df2021$probe_insitu
rm(df2021)

df2022 <- aggProbeInSitu('2022', version, probes, T_layer, M_layer)
sents2022 <- df2022$probe_sents
doy2022 <- df2022$doy
insitu2022 <- df2022$probe_insitu
rm(df2022)

sents <- rbind(sents2021, sents2022)
rm(sents2021)
rm(sents2022)

doy <- rbind(doy2021, doy2022)
rm(doy2021)
rm(doy2022)

insitu <- rbind(insitu2021, insitu2022)
rm(insitu2021)
rm(insitu2022)

sents_wide <- 
  sents |> 
  pivot_wider(names_from = band, values_from = value)

harmonized <- inner_join(insitu, sents_wide, by = c('probe_id', 'date'))

st_write(harmonized, 'layers/harmonized.geojson')

