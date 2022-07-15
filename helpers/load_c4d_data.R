library(Carbon4D)
library(tidyverse)
library(sf)

path <- '~/Documents/GitHub/Carbon4dData/'
Carbon4D::load_monthly_probe_data(path)
Carbon4D::load_probe_meta_data_monthly(path)
ProbeMetaData_sf <- st_as_sf(ProbeMetaDataMonthly, coords = c('lon', 'lat'), crs = 4326)
#st_write(ProbeMetaData_sf, 'layers/ProbeMetaData.geojson')
csv_list <- csv_list_monthly_probe_data 
ProbeMetaData <- ProbeMetaDataMonthly

for (i in 1:length(csv_list)) {
  csv_list[[i]]$probe_id <-names(csv_list)[i]
  csv_list[[i]]$probe_id <- substr(csv_list[[i]]$probe_id, 1, 7)
}

df <- bind_rows(csv_list, .id = "probe_id")
df$probe_id <- substr(df$probe_id, 1, 7)
df <- left_join(df, ProbeMetaData |> dplyr::select(probe_id, lon, lat), by = 'probe_id')
Probe_Measurements_sf <- st_as_sf(df, coords = c('lon', 'lat'), crs = 4326)

rm(df)
rm(csv_list)
rm(csv_list_monthly_probe_data)
rm(ProbeMetaData)
rm(ProbeMetaDataMonthly)
rm(ProbeMetaData_sf)
