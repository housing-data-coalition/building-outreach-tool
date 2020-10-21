server <- function(input, output, session) {
  
  # Bookmarking -------------------------------------------------------------
  
  # Only want to include bbl input for bookmark url, so exclude all others
  ExcludedIDs <- reactiveVal(value = NULL)
  
  observe({
    toExclude <- setdiff(names(input), "bbl")
    setBookmarkExclude(toExclude)
    ExcludedIDs(toExclude)
  })
  
  # Update the url with each bbl input change
  observe({
    bbl <- reactiveValuesToList(input)$bbl
    if (bbl != "") session$doBookmark()
  })
  
  onBookmarked(function(url) {
    updateQueryString(url)
  })
  
  # Restore to details tab
  onRestored(function(state) {
    updateTabsetPanel(session, "inTabset", selected = "detailsTab")
  })
  
  
  
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
      mutate(
        bbl_button = bbl_button(bbl),
        bbl_links = bbl_links(bbl),
        .after = bbl
      ) %>% 
      st_transform(4326)

  })

  home_bldg <- reactive({
    
    home_query <- glue_sql(
      "select * from hdc_building_info where bbl = {home_bbl()}", 
      .con = con
    )

    read_sf(con, query = home_query) %>%
      mutate(across(where(is.integer64), as.numeric)) %>%
      mutate(
        bbl_button = bbl_button(bbl),
        bbl_links = bbl_links(bbl),
        .after = bbl
      ) %>% 
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
    home_bldg() %>% select(-bbl) %>% st_drop_geometry(),
    selection = "none",
    escape = FALSE,
    rownames = FALSE,
    options = list(
      dom = 'Brt',
      language = list(zeroRecords = "Please input an address"),
      scrollX = TRUE
    )
  )

  output$outreach_table = renderDT(
    outreach_bldgs() %>% select(-bbl) %>% st_drop_geometry(),
    selection = "none",
    escape = FALSE,
    rownames = FALSE,
    options = list(
      dom = 'BSrtip',
      language = list(zeroRecords = "Please input an address"),
      pageLength = 4,
      scrollX = TRUE
    )
  )
  
  
  output$download_all <- downloadHandler(
    filename = function() {
      glue("{home_bbl()}_bldgs-{input$n_bldgs}_walk-{input$n_mins}_{Sys.Date()}.csv")
    },
    content = function(file) {
      bind_rows(home_bldg(), outreach_bldgs()) %>% 
        select(-starts_with("bbl_")) %>% 
        st_drop_geometry() %>% 
        write.csv(file, na = "")
    }
  )
  
  
  # Selected BBL ------------------------------------------------------------
  
  bbl_address <- reactive({
    req(input$bbl)
    
    query <- glue_sql("
      SELECT 
        bbl || ': ' || address 
      FROM ridgewood.hdc_building_info
      WHERE bbl = {input$bbl}
    ", .con = con)
    
    dbGetQuery(con, query)[[1]]
  })
  
  output$bbl_address <- renderText(bbl_address())
  
  observeEvent(input$bbl_button, {
    req(input$bbl_button)
    
    clicked_bbl <- gsub("button_", "", input$bbl_button) # Get bbl out of button id
    updateTextInput(session, "bbl", value = clicked_bbl)
    
    # Move  to details tab
    updateTabsetPanel(session, "inTabset", selected = "detailsTab")
  })
  

  # HPD Complaints Details --------------------------------------------------

  callModule(
    module = detailsTable, 
    id = "hpd_complaints_table", 
    .con = con,
    selected_bbl = reactive(input$bbl), 
    sql_function = "ridgewood.get_hpd_complaints_for_bbl", 
    download_file_slug = "hpd-complaints-details", 
    dataset_name = "HPD Complaints"
  )
}
