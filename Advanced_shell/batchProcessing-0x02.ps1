# Batch Processing Script for Pokémon API Data Retrieval
# File: batchProcessing-0x02.ps1
# Description: Fetches data for multiple Pokémon and saves to separate JSON files

# API base URL
$API_URL = "https://pokeapi.co/api/v2/pokemon"

# List of Pokémon to fetch
$POKEMON_LIST = @("bulbasaur", "ivysaur", "venusaur", "charmander", "charmeleon")

# Output directory
$OUTPUT_DIR = "pokemon_data"

# Create output directory if it doesn't exist
if (!(Test-Path -Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    Write-Host "Created directory: $OUTPUT_DIR"
}

# Function to fetch Pokémon data
function Fetch-PokemonData {
    param(
        [string]$PokemonName
    )
    
    $OutputFile = "$OUTPUT_DIR\$PokemonName.json"
    
    Write-Host "Fetching data for $PokemonName..."
    
    try {
        # Make API request and save to file
        $Response = Invoke-RestMethod -Uri "$API_URL/$PokemonName" -Method Get
        $Response | ConvertTo-Json -Depth 100 | Out-File -FilePath $OutputFile -Encoding UTF8
        
        # Check if the file was created successfully
        if (Test-Path -Path $OutputFile) {
            Write-Host "Saved data to $OutputFile ✅"
            return $true
        } else {
            Write-Host "❌ Failed to save data for $PokemonName"
            return $false
        }
    }
    catch {
        Write-Host "❌ Failed to fetch data for $PokemonName"
        Write-Host "Error: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
Write-Host "Starting batch Pokémon data retrieval..."
Write-Host "========================================="

# Counter for successful fetches
$SuccessCount = 0
$TotalCount = $POKEMON_LIST.Count

# Loop through each Pokémon
foreach ($Pokemon in $POKEMON_LIST) {
    if (Fetch-PokemonData -PokemonName $Pokemon) {
        $SuccessCount++
    }
    
    # Add delay to handle rate limiting (1 second between requests)
    if ($Pokemon -ne $POKEMON_LIST[-1]) {
        Start-Sleep -Seconds 1
    }
}

Write-Host "========================================="
Write-Host "Batch processing completed!"
Write-Host "Successfully fetched: $SuccessCount/$TotalCount Pokémon"

# List the created files
if ($SuccessCount -gt 0) {
    Write-Host ""
    Write-Host "Created files:"
    Get-ChildItem -Path "$OUTPUT_DIR\*.json" -ErrorAction SilentlyContinue | Format-Table Name, Length, LastWriteTime
}