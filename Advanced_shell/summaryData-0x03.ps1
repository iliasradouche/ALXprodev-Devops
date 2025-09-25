# Pokémon Data Summary Report Script
# File: summaryData-0x03.ps1
# Description: Reads JSON files and generates a CSV report with statistics

# Configuration
$JSON_DIR = "pokemon_data"
$CSV_FILE = "pokemon_report.csv"

# Check if pokemon_data directory exists
if (!(Test-Path -Path $JSON_DIR)) {
    Write-Host "Error: Directory '$JSON_DIR' not found!" -ForegroundColor Red
    Write-Host "Please run the batch processing script first to generate Pokémon data."
    exit 1
}

# Check if JSON files exist
$JsonFiles = Get-ChildItem -Path "$JSON_DIR\*.json" -ErrorAction SilentlyContinue
if ($JsonFiles.Count -eq 0) {
    Write-Host "Error: No JSON files found in '$JSON_DIR' directory!" -ForegroundColor Red
    exit 1
}

# Create CSV header
"Name,Height (m),Weight (kg)" | Out-File -FilePath $CSV_FILE -Encoding UTF8

# Array to store data for average calculations
$HeightData = @()
$WeightData = @()

Write-Host "Processing Pokémon data..."

# Process each JSON file
foreach ($JsonFile in $JsonFiles) {
    try {
        # Read and parse JSON
        $JsonContent = Get-Content -Path $JsonFile.FullName -Raw | ConvertFrom-Json
        
        # Extract name, height (decimeters), and weight (hectograms)
        $Name = $JsonContent.name
        $HeightDm = $JsonContent.height
        $WeightHg = $JsonContent.weight
        
        # Check if extraction was successful
        if ($Name -and $HeightDm -and $WeightHg) {
            # Convert height from decimeters to meters and weight from hectograms to kg
            $HeightM = [math]::Round($HeightDm / 10, 1)
            $WeightKg = [math]::Round($WeightHg / 10, 1)
            
            # Capitalize first letter of name
            $FormattedName = (Get-Culture).TextInfo.ToTitleCase($Name.ToLower())
            
            # Add to CSV
            "$FormattedName,$HeightM,$WeightKg" | Add-Content -Path $CSV_FILE -Encoding UTF8
            
            # Store for average calculations
            $HeightData += $HeightM
            $WeightData += $WeightKg
            
            Write-Host "Processed: $FormattedName"
        } else {
            Write-Host "Warning: Failed to extract data from $($JsonFile.Name)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Warning: Error processing $($JsonFile.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "CSV Report generated at: $CSV_FILE"
Write-Host ""

# Display CSV content
Get-Content -Path $CSV_FILE
Write-Host ""

# Calculate averages
if ($HeightData.Count -gt 0) {
    $AvgHeight = [math]::Round(($HeightData | Measure-Object -Average).Average, 2)
    $AvgWeight = [math]::Round(($WeightData | Measure-Object -Average).Average, 2)
    
    Write-Host "Average Height: $AvgHeight m"
    Write-Host "Average Weight: $AvgWeight kg"
} else {
    Write-Host "No data available for average calculations."
}