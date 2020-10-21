# These two functions create a Shiny Module for creating the details tables for a given datset
# http://shiny.rstudio.com/articles/modules.html

# Module UI function
detailsTableOutput <- function(id, dataset_name) {
  # Create a namespace function using the provided id
  ns <- NS(id)
  
  tagList(
    h3(dataset_name),
    downloadButton(ns("details_download"), glue("Download All {dataset_name} for this Property")),
    DTOutput(ns("details_table"))
  )
}

# Module server function
detailsTable <- function(input, output, session, 
                         .con, 
                         selected_bbl, 
                         sql_function, 
                         download_file_slug, 
                         dataset_name) {
  
  # Retrieve a set of details for a bbl
  details_data <- reactive({
    req(selected_bbl)
    
    query <- glue(
      "SELECT * FROM {.fun}({.bbl})",
      .bbl = dbQuoteString(.con, selected_bbl()),
      .fun = sql_function,
    )
    
    dbGetQuery(.con, query)
  })
  
  
  output$details_table = renderDT(
    details_data(),
    selection = "none",
    rownames = FALSE,
    # callback = JS(header_tooltip_js(sql_function)), # see /tool_tips.R
    options = list(
      dom = 'Brtip',
      language = list(zeroRecords = glue("No data on {dataset_name} for this property")),
      scrollX = TRUE
    )
  )
  
  output$details_download <- downloadHandler(
    filename = function() {
      glue("{selected_bbl()}_{download_file_slug}_{Sys.Date()}.csv")
    },
    content = function(file) {
      write.csv(details_data(), file, na = "")
    }
  )
  
}