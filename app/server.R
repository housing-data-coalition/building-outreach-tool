server <- function(input, output, session) {
  
  # Geocoding ---------------------------------------------------------------

  home_bbl <- eventReactive(input$submit_info, {
    
    bbl <- geo_search(input$address)[["bbl"]]
    
    if (is.null(bbl) || is.na(bbl))
      return()
    
    bbl
  })
  

  # DB Requests -------------------------------------------------------------

  outreach_bldgs <- reactive({
    req(input$n_bldgs)
    req(input$n_mins)
    
    outreach_query <- glue_sql(
      "select * from get_outreach_bbls_from_bbl({home_bbl()}, {input$n_bldgs}, {input$n_mins})",
      .con = con
    )

    read_sf(con, query = outreach_query) %>%
      mutate(across(where(is.integer64), as.numeric)) %>%
      st_transform(4326)

  })

  home_bldg <- reactive({
    
    home_query <- glue_sql(
      "select * from hdc_building_info where bbl = {home_bbl()}", 
      .con = con
    )

    read_sf(con, query = home_query) %>%
      mutate(across(where(is.integer64), as.numeric)) %>%
      st_transform(4326)
  })


  # Map ---------------------------------------------------------------------

  # Create default map to start with on the app
  output$map <- renderLeaflet({
    leaflet() %>%
      addMapboxGL(style = "mapbox://styles/mapbox/light-v9") %>%
      setView(-73.946859, 40.653471, zoom = 12)
  })

  observe({
    
    bldgs_bbox <- rbind(home_bldg(), outreach_bldgs()) %>% sf::st_bbox()
    
    leafletProxy("map") %>%
      clearMarkers() %>% 
      addCircleMarkers(
        data = home_bldg(),
        radius = 3,
        layerId = ~bbl,
        stroke = FALSE,
        color = "black",
        fillOpacity = 1
      ) %>% 
      addCircleMarkers(
        data = outreach_bldgs(),
        radius = 3,
        layerId = ~bbl,
        stroke = FALSE,
        color = "red",
        fillOpacity = 1
      ) %>% 
      flyToBounds(
        lng1 = bldgs_bbox[["xmin"]], lng2 = bldgs_bbox[["xmax"]], 
        lat1 = bldgs_bbox[["ymin"]], lat2 = bldgs_bbox[["ymax"]]
      )
  })


  # Tables ------------------------------------------------------------------

  output$home_table = renderDT(
    st_drop_geometry(home_bldg()),
    selection = "none",
    options = list(
      dom = 'Brtip',
      language = list(zeroRecords = "Please input an address"),
      scrollX = TRUE
    )
  )

  output$outreach_table = renderDT(
    st_drop_geometry(outreach_bldgs()),
    selection = "none",
    options = list(
      dom = 'Brtip',
      language = list(zeroRecords = "Please input an address"),
      scrollX = TRUE
    )
  )
  
}
