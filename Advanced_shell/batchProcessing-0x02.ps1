# Batch Processing Script for Pokémon API Data Retrieval with Enhanced Error Handling
# File: batchProcessing-0x02.ps1
# Description: Fetches data for multiple Pokémon with retry logic and robust error handling

# API base URL
$API_URL = "https://pokeapi.co/api/v2/pokemon"

# List of Pokémon to fetch
$POKEMON_LIST = @("bulbasaur", "ivysaur", "venusaur", "charmander", "charmeleon")

# Output directory
$OUTPUT_DIR = "pokemon_data"

# Configuration
$MAX_RETRIES = 3
$RETRY_DELAY = 2
$LOG_FILE = "pokemon_fetch_errors.log"

# Create output directory if it doesn't exist
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    Write-Host "Created directory: $OUTPUT_DIR"
}

# Initialize log file
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"=== Pokémon Fetch Error Log - $timestamp ===" | Out-File -FilePath $LOG_FILE -Encoding UTF8

# Function to log errors
function Log-Error {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] ERROR: $Message"
    $logEntry | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
    Write-Host $logEntry -ForegroundColor Red
}

# Function to log info
function Log-Info {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] INFO: $Message"
    $logEntry | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

# Function to validate Pokémon name
function Test-PokemonName {
    param([string]$PokemonName)
    
    # Check if name contains only lowercase letters and hyphens
    if ($PokemonName -notmatch '^[a-z-]+$') {
        return $false
    }
    
    # Check minimum length
    if ($PokemonName.Length -lt 3) {
        return $false
    }
    
    return $true
}

# Function to check network connectivity
function Test-NetworkConnectivity {
    try {
        $response = Invoke-WebRequest -Uri "https://pokeapi.co" -Method Head -TimeoutSec 10 -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Enhanced function to fetch Pokémon data with retry logic
function Get-PokemonData {
    param([string]$PokemonName)
    
    $outputFile = Join-Path $OUTPUT_DIR "$PokemonName.json"
    $attempt = 1
    
    # Validate Pokémon name
    if (-not (Test-PokemonName $PokemonName)) {
        Log-Error "Invalid Pokémon name format: $PokemonName"
        return $false
    }
    
    Write-Host "Fetching data for $PokemonName..."
    Log-Info "Starting fetch for $PokemonName"
    
    # Retry loop
    while ($attempt -le $MAX_RETRIES) {
        Write-Host "  Attempt $attempt/$MAX_RETRIES..."
        
        # Check network connectivity before attempting
        if (-not (Test-NetworkConnectivity)) {
            Log-Error "Network connectivity issue detected (attempt $attempt for $PokemonName)"
            if ($attempt -eq $MAX_RETRIES) {
                Write-Host "  ❌ Network connectivity failed after $MAX_RETRIES attempts" -ForegroundColor Red
                return $false
            }
            Write-Host "  ⚠️  Network issue, retrying in ${RETRY_DELAY}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RETRY_DELAY
            $attempt++
            continue
        }
        
        try {
            # Make API request with timeout and error handling
            $response = Invoke-WebRequest -Uri "$API_URL/$PokemonName" -TimeoutSec 30 -ErrorAction Stop
            
            # Check if response is successful
            if ($response.StatusCode -eq 200) {
                # Validate JSON content
                try {
                    $jsonContent = $response.Content | ConvertFrom-Json
                    $response.Content | Out-File -FilePath $outputFile -Encoding UTF8
                    Write-Host "  ✅ Saved data to $outputFile" -ForegroundColor Green
                    Log-Info "Successfully fetched $PokemonName on attempt $attempt"
                    return $true
                }
                catch {
                    Log-Error "Invalid JSON received (attempt $attempt for $PokemonName): $($_.Exception.Message)"
                    if (Test-Path $outputFile) {
                        Remove-Item $outputFile -Force
                    }
                }
            }
            else {
                Log-Error "Unexpected HTTP status $($response.StatusCode) (attempt $attempt for $PokemonName)"
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            
            # Handle specific error types
            if ($errorMessage -match "404") {
                Log-Error "Pokémon '$PokemonName' not found (HTTP 404)"
                if (Test-Path $outputFile) {
                    Remove-Item $outputFile -Force
                }
                Write-Host "  ❌ Pokémon '$PokemonName' not found" -ForegroundColor Red
                return $false
            }
            elseif ($errorMessage -match "429") {
                Log-Error "Rate limit exceeded (HTTP 429) (attempt $attempt for $PokemonName)"
                Write-Host "  ⚠️  Rate limit exceeded, waiting longer..." -ForegroundColor Yellow
                Start-Sleep -Seconds ($RETRY_DELAY * 2)
            }
            elseif ($errorMessage -match "timeout") {
                Log-Error "Operation timeout (attempt $attempt for $PokemonName)"
            }
            elseif ($errorMessage -match "resolve") {
                Log-Error "Could not resolve host (attempt $attempt for $PokemonName)"
            }
            elseif ($errorMessage -match "connect") {
                Log-Error "Failed to connect to host (attempt $attempt for $PokemonName)"
            }
            else {
                Log-Error "Request error (attempt $attempt for $PokemonName): $errorMessage"
            }
        }
        
        # If this was the last attempt, give up
        if ($attempt -eq $MAX_RETRIES) {
            Write-Host "  ❌ Failed to fetch $PokemonName after $MAX_RETRIES attempts" -ForegroundColor Red
            Log-Error "Giving up on $PokemonName after $MAX_RETRIES attempts"
            if (Test-Path $outputFile) {
                Remove-Item $outputFile -Force
            }
            return $false
        }
        
        # Wait before retrying
        Write-Host "  ⚠️  Retrying in ${RETRY_DELAY}s..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RETRY_DELAY
        $attempt++
    }
    
    return $false
}

# Main execution
Write-Host "Starting batch processing of $($POKEMON_LIST.Count) Pokémon..."
Write-Host "Output directory: $OUTPUT_DIR"
Write-Host "Rate limiting: 1 second delay between requests"
Write-Host "Max retries per Pokémon: $MAX_RETRIES"
Write-Host "Error log: $LOG_FILE"
Write-Host

$successfulCount = 0
$failedCount = 0

# Process each Pokémon
for ($i = 0; $i -lt $POKEMON_LIST.Count; $i++) {
    $pokemon = $POKEMON_LIST[$i]
    
    if (Get-PokemonData $pokemon) {
        $successfulCount++
    }
    else {
        $failedCount++
    }
    
    # Add delay to respect rate limiting (except for the last request)
    if ($i -lt ($POKEMON_LIST.Count - 1)) {
        Write-Host "Waiting 1 second..."
        Start-Sleep -Seconds 1
    }
    Write-Host
}

# Summary
Write-Host "=== BATCH PROCESSING COMPLETE ===" -ForegroundColor Cyan
Write-Host "Total Pokémon processed: $($POKEMON_LIST.Count)"
Write-Host "Successful: $successfulCount" -ForegroundColor Green
Write-Host "Failed: $failedCount" -ForegroundColor Red
Write-Host "Output directory: $OUTPUT_DIR"
Write-Host "Error log: $LOG_FILE"

# Log final summary
Log-Info "Batch processing complete: $successfulCount successful, $failedCount failed"

if ($failedCount -gt 0) {
    Write-Host "⚠️  Some requests failed. Check the error log: $LOG_FILE" -ForegroundColor Yellow
    Write-Host "Failed Pokémon files (if any) have been removed from $OUTPUT_DIR"
    exit 1
}
else {
    Write-Host "✅ All Pokémon data retrieved successfully!" -ForegroundColor Green
    exit 0
}