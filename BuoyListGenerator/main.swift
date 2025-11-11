import Foundation

// MARK: - Buoy Structs
struct Buoy: Codable {
    let stationId: String
    let name: String
    let latitude: Double
    let longitude: Double
}

enum BuoyError: Error {
    case networkError(Error)
    case badURL
    case badResponse
    case dataCorrupted
    case parsingFailed
    case fileWriteFailed(Error)
}

// MARK: - Buoy TXT Parser
// This is the working parser from your original script
func parseStationTable(_ table: String) throws -> [Buoy] {
    var buoys: [Buoy] = []
    let lines = table.components(separatedBy: .newlines)

    // Skip header comment lines
    for line in lines.drop(while: { $0.starts(with: "#") }) {
        if line.isEmpty { continue }
        
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        
        guard parts.count >= 8 else { continue } // Ensure enough parts

        let stationId = parts[0]
        let type = parts[2]
        let name = parts[4]
        let locationString = parts[6]
        
        // Filter for "Buoy" types
        guard type.localizedCaseInsensitiveContains("buoy") else {
            continue
        }
        
        // Parse location: "44.794 N 87.313 W (..."
        let locationParts = locationString.components(separatedBy: .whitespaces)
        guard locationParts.count >= 4 else { continue }
        
        guard let latDegrees = Double(locationParts[0]) else { continue }
        let latDirection = locationParts[1]
        
        guard let lonDegrees = Double(locationParts[2]) else { continue }
        let lonDirection = locationParts[3]
        
        let latitude = (latDirection == "S") ? -latDegrees : latDegrees
        let longitude = (lonDirection == "W") ? -lonDegrees : lonDegrees
        
        let buoy = Buoy(
            stationId: stationId,
            name: name,
            latitude: latitude,
            longitude: longitude
        )
        buoys.append(buoy)
    }
    
    if buoys.isEmpty {
        print("Parsing finished, but no buoys were found.")
        throw BuoyError.parsingFailed
    }
    
    return buoys
}


// MARK: - Tide Structs

// This struct now correctly matches the JSON from your curl test
struct TideStationResponse: Codable {
    let stations: [NOAATideStation]
}

// FIX: This struct is now flat and uses `lat` and `lng`
struct NOAATideStation: Codable {
    let id: String
    let name: String
    let lat: Double? // Latitude (optional in case some are null)
    let lng: Double? // Longitude (optional in case some are null)
}

// This is our clean output format (unchanged)
struct TideStationReference: Codable {
    let stationId: String
    let name: String
    let latitude: Double
    let longitude: Double
}

enum TideError: Error {
    case networkError(Error)
    case badURL
    case badResponse
    case dataCorrupted
    case fileWriteFailed(Error)
}


// MARK: - Shared Helper
/// Gets the base directory of the script/executable
func getScriptDirectory() throws -> URL {
    guard let executablePath = CommandLine.arguments.first else {
        fatalError("Could not determine executable path.")
    }
    let executableURL = URL(fileURLWithPath: executablePath)
    return executableURL.deletingLastPathComponent()
}


// MARK: - Buoy Generation (REVERTED TO TXT)
func generateBuoyList() async {
    // REVERTED URL: Using the working station_table.txt file
    let urlString = "https://www.ndbc.noaa.gov/data/stations/station_table.txt"
    let outputFilename = "all_noaa_buoys.json"
    
    print("--- Starting Buoy List Generation (using TXT) ---")
    
    do {
        // 1. Fetch the data
        print("Fetching data from NDBC...")
        guard let url = URL(string: urlString) else {
            throw BuoyError.badURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("SurfReportApp (joelcook.com, fetching buoy list)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("NDBC server returned status: \(statusCode)")
            throw BuoyError.badResponse
        }
        
        // 2. Parse the TXT data
        guard let dataString = String(data: data, encoding: .utf8) else {
            throw BuoyError.dataCorrupted
        }
        
        print("Parsing station table...")
        let buoys = try parseStationTable(dataString)
        print("Found \(buoys.count) active buoys.")
        
        // 3. Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(buoys)
        
        // 4. Write to file
        let scriptDirectoryURL = try getScriptDirectory()
        let fileURL = scriptDirectoryURL.appendingPathComponent(outputFilename)
        
        try jsonData.write(to: fileURL)
        
        print("✅ Successfully generated \(outputFilename) at:")
        print("\(fileURL.path)")
        print("---------------------------------------\n")
        
    } catch {
        print("Buoy generation FAILED: \(error)")
        print("---------------------------------------\n")
    }
}

// (This function is no longer needed, as we're not parsing the .txt file)
// func parseStationTable(_ table: String) throws -> [Buoy] { ... }


// MARK: - Tide Generation (FIXED)
func generateTideList() async {
    // This URL is correct, as confirmed by your curl
    let urlString = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions"
    let outputFilename = "all_noaa_tide_stations.json"
    
    print("--- Starting Tide Station List Generation ---")
    
    do {
        // 1. Fetch the data
        print("Fetching data from NOAA Tides & Currents...")
        guard let url = URL(string: urlString) else {
            throw TideError.badURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("SurfReportApp (joelcook.com, fetching tide list)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("NOAA Tides server returned status: \(statusCode)")
            throw TideError.badResponse
        }
        
        // 2. Decode the API Response
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(TideStationResponse.self, from: data)
        print("Received \(apiResponse.stations.count) total stations.")
        
        // 3. Filter and Map to our clean format (FIXED)
        // We now read `station.lat` and `station.lng`
        let cleanStations = apiResponse.stations.compactMap { station -> TideStationReference? in
            guard let lat = station.lat, let lon = station.lng else {
                return nil // Skip stations with no location
            }
            return TideStationReference(
                stationId: station.id,
                name: station.name,
                latitude: lat,
                longitude: lon
            )
        }
        
        print("Found \(cleanStations.count) valid, plottable stations.")
        
        // 4. Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(cleanStations)
        
        // 5. Write to file
        let scriptDirectoryURL = try getScriptDirectory()
        let fileURL = scriptDirectoryURL.appendingPathComponent(outputFilename)
        
        try jsonData.write(to: fileURL)
        
        print("✅ Successfully generated \(outputFilename) at:")
        print("\(fileURL.path)")
        print("-------------------------------------------\n")
        
    } catch {
        print("Tide generation FAILED: \(error)")
        print("-------------------------------------------\n")
    }
}

// MARK: - Run All Functions
func runAllGenerators() async {
    print("Starting all data generators...\n")
    await generateBuoyList()
    await generateTideList()
    print("All data generation complete.")
}

// This runs everything when you execute the script
await runAllGenerators()
