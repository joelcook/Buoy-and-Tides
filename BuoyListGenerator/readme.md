# **NOAA Data List Generator**

This is the simple command-line tool that builds the data files for the "What's The Call?" app.

## **What's The Call on this?**

Why not just have the app fetch these giant lists? Because that's slow, wastes data, and is just a bad call.  
This tool does the heavy lifting *once* so the app doesn't have to. It fetches the massive lists of every buoy and tide station from NOAA, parses their terrible .txt and JSON formats, and spits out two clean, simple files the app can actually use.  

## **How It Works**

1. It runs generateBuoyList(), which hits the NDBC .txt file, parses it line-by-line, and saves all\_noaa\_buoys.json.  
2. It runs generateTideList(), which hits the NOAA JSON API, and saves all\_noaa\_tide\_stations.json.

## **How to Use It**

This is a developer tool. It's not part of the main app. You only run this when you want to refresh the station data (maybe every 6 months?).

1. Build the project in Xcode (⌘+B).  
2. Find the compiled executable (in the "Products" folder).  
3. Run it from your terminal.  
   \# cd to wherever you put the executable  
   ./generate\_data\_lists
