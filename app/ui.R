ui <- function(request) {
  navbarPage(
    title = "Building Outreach Tool",
    id = "inTabset",
    
    tabPanel(
      title = "Buildings",
      value = "bldgsTab",
      
      fluidRow(
        column(4, 
          textInput("address", "Enter a NYC address", value = NULL, width = "100%"),
          numericInput("n_bldgs", "Number of nearby buildings", value = 10, min = 1, max = 100, step = 1, width = "100%"),
          numericInput("n_mins", "Number of minutes walk", value = 10, min = 1, max = 60, step = 1, width = "100%"),
          actionButton(inputId = "submit_info", label = "Submit"),
          leafletOutput("map", width = "100%", height = "400px"),
        ),
        column(8, 
          downloadButton("download_all", "Download Buildings Info"),
          DTOutput("home_table"),
          DTOutput("outreach_table"),
        )
      )
    ),
    
    
    tabPanel(
      title = "Property Details",
      value = "detailsTab",
      
      # BBL Selector
      textInput("bbl", "Enter a BBL or choose one from Propertries Overview", value = NULL, width = "400px"),
      
      # Single BBL Tables
      h2(textOutput("bbl_address")),
      detailsTableOutput("hpd_complaints_table", "Open HPD Complaints since 2019"),
    ),
    
    tabPanel(
      title = "About",
      value = "aboutTab",

      includeMarkdown("about.md")
    )
  )
}