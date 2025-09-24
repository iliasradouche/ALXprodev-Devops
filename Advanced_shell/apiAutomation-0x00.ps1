# apiAutomation-0x00.ps1
# PowerShell script to fetch Pikachu data from the Pokémon API
# Saves successful responses to data.json and errors to errors.txt

# API endpoint for Pikachu
$API_URL = "https://pokeapi.co/api/v2/pokemon/pikachu"

# Output files
$DATA_FILE = "data.json"
$ERROR_FILE = "errors.txt"

# Function to log errors with timestamp
function Log-Error {
    param([string]$ErrorMessage)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] ERROR: $ErrorMessage"
    Add-Content -Path $ERROR_FILE -Value $logEntry
}

# Function to make API request
function Fetch-PokemonData {
    Write-Host "Fetching Pikachu data from Pokémon API..." -ForegroundColor Yellow
    
    try {
        # Make the API request using Invoke-RestMethod
        $response = Invoke-RestMethod -Uri $API_URL -Method Get -ErrorAction Stop
        
        # Convert response to JSON and save to file
        $jsonContent = $response | ConvertTo-Json -Depth 10
        Set-Content -Path $DATA_FILE -Value $jsonContent -Encoding UTF8
        
        Write-Host "Success! Pikachu data saved to $DATA_FILE" -ForegroundColor Green
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        
        # Handle different types of errors
        if ($_.Exception -is [System.Net.WebException]) {
            $httpResponse = $_.Exception.Response
            if ($httpResponse) {
                $statusCode = [int]$httpResponse.StatusCode
                switch ($statusCode) {
                    404 {
                        Log-Error "HTTP 404 - Pokémon not found"
                        Write-Host "Error: Pokémon not found (HTTP 404)" -ForegroundColor Red
                    }
                    429 {
                        Log-Error "HTTP 429 - Rate limit exceeded"
                        Write-Host "Error: Rate limit exceeded. Please try again later." -ForegroundColor Red
                    }
                    { $_ -in 500, 502, 503, 504 } {
                        Log-Error "HTTP $statusCode - Server error"
                        Write-Host "Error: Server error (HTTP $statusCode). Please try again later." -ForegroundColor Red
                    }
                    default {
                        Log-Error "HTTP $statusCode - Unexpected response"
                        Write-Host "Error: Unexpected HTTP status code: $statusCode" -ForegroundColor Red
                    }
                }
            } else {
                Log-Error "Network error: $errorMessage"
                Write-Host "Error: Network connection failed. Check your internet connection." -ForegroundColor Red
            }
        } else {
            Log-Error "General error: $errorMessage"
            Write-Host "Error: $errorMessage" -ForegroundColor Red
        }
        
        # Remove invalid data file if it exists
        if (Test-Path $DATA_FILE) {
            Remove-Item $DATA_FILE -Force
        }
        
        return $false
    }
}

# Function to validate JSON response
function Test-JsonResponse {
    if (Test-Path $DATA_FILE) {
        try {
            $content = Get-Content -Path $DATA_FILE -Raw
            $null = $content | ConvertFrom-Json
            return $true
        }
        catch {
            Log-Error "Invalid JSON response received"
            Write-Host "Error: Invalid JSON response" -ForegroundColor Red
            Remove-Item $DATA_FILE -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    return $false
}

# Main execution
function Main {
    Write-Host "=== Pokémon API Automation Script ===" -ForegroundColor Cyan
    Write-Host "Target: Pikachu" -ForegroundColor White
    Write-Host "API URL: $API_URL" -ForegroundColor White
    Write-Host ""
    
    # Remove previous data file if it exists
    if (Test-Path $DATA_FILE) {
        Remove-Item $DATA_FILE -Force
    }
    
    # Fetch the data
    if (Fetch-PokemonData) {
        # Validate the JSON
        if (Test-JsonResponse) {
            Write-Host ""
            Write-Host "=== Operation Completed Successfully ===" -ForegroundColor Green
            Write-Host "Data file: $DATA_FILE" -ForegroundColor White
            
            # Display file size
            if (Test-Path $DATA_FILE) {
                $fileSize = (Get-Item $DATA_FILE).Length
                Write-Host "File size: $fileSize bytes" -ForegroundColor White
            }
            
            # Show first few lines
            Write-Host ""
            Write-Host "Preview (first 10 lines):" -ForegroundColor Yellow
            $content = Get-Content -Path $DATA_FILE -Raw
            $jsonObject = $content | ConvertFrom-Json
            $prettyJson = $jsonObject | ConvertTo-Json -Depth 3
            $lines = $prettyJson -split "`n"
            $lines[0..9] | ForEach-Object { Write-Host $_ }
            
            if ($lines.Count -gt 10) {
                Write-Host "..." -ForegroundColor Gray
            }
        } else {
            exit 1
        }
    } else {
        Write-Host ""
        Write-Host "=== Operation Failed ===" -ForegroundColor Red
        Write-Host "Check $ERROR_FILE for details" -ForegroundColor Yellow
        exit 1
    }
}

# Run the main function
Main