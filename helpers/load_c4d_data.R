library(Carbon4D)
library(tidyverse)
library(sf)
path <- '~/Documents/GitHub/Carbon4dData/'
Carbon4D::load_probe_data(path)
Carbon4D::load_probe_meta_data(path)
ProbeMetaData_sf <- st_as_sf(ProbeMetaData, coords = c('lon', 'lat'), crs = 4326)

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
rm(ProbeMetaData)
rm(ProbeMetaData_sf)
