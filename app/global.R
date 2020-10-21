library(shiny)
library(dplyr) # dataframe manipulation
library(sf) # Spatial data
library(leaflet) # interactive maps
# remotes::install_github("rstudio/leaflet.mapboxgl")
library(leaflet.mapboxgl) # mapbox basemap
# remotes::install_github("austensen/geoclient")
library(geoclient) # address-to-bbl geocoding
library(pool) # Database Connection Pooling
library(config) # Manage configuration values across multiple environments
library(glue) # Interpreted string literals
library(DT) # JS DataTables


# Set Secrets -------------------------------------------------------------

nycdb <- get("nycdb")

con <- dbPool(
  drv = RPostgres::Postgres(),
  dbname = nycdb$dbname,
  host = nycdb$host,
  user = nycdb$user,
  password = nycdb$password,
  port = nycdb$port
)

mapbox <- get("mapbox")

# Set API token for MapboxGL basemap
options(mapbox.accessToken = mapbox$token)


geoclient <- get("geoclient")

# Set API tokens for Geoclient service
geoclient_api_keys(id = geoclient$id, key = geoclient$key)


# Load Modules ------------------------------------------------------------

source("details_module.R")

enableBookmarking("url")

# Helper Functions --------------------------------------------------------

bbl_links <- function(bbl) {
  glue(
    "<a 
      href='https://portal.displacementalert.org/property/{bbl}'
      target='_blank'>
    DAP Portal
    </a>",
    "</br>",
    "<a 
      href='https://whoownswhat.justfix.nyc/en/bbl/{bbl}'
      target='_blank'>
    Who-Owns-What
    </a>"
  )
}

bbl_button <- function(bbl) {
  glue(
    "<button 
      id='button_{bbl}' 
      type='button' 
      class='btn btn-default action-button' 
      onclick='Shiny.onInputChange(&quot;bbl_button&quot;, this.id)'>
    {bbl}
    </button>"
  )
}


# temporary fixes.. -------------------------------------------------------

glue_sql <- function(..., .con) {
  connection <- pool::poolCheckout(.con)
  on.exit(pool::poolReturn(connection))  
  glue::glue_sql(..., .con = connection, .envir = parent.frame())  
}

is.integer64 <- function(x){
  result = class(x) == "integer64"
  result[1]
}
