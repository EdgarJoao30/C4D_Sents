library(sf)
library(tidyverse)

roi <- st_read('layers/StudyArea.gpkg')

roi_bbox <- st_bbox(roi |> st_transform(4326))
roi_bbox
