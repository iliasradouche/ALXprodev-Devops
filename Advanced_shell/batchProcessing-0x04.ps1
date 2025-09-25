# Parallel Batch Processing Script for Pokémon API Data Retrieval
# File: batchProcessing-0x04.ps1
# Description: Fetches data for multiple Pokémon in parallel using PowerShell background jobs

# API base URL
$API_URL = "https://pokeapi.co/api/v2/pokemon"

# List of Pokémon to fetch
$POKEMON_LIST = @("bulbasaur", "ivysaur", "venusaur", "charmander", "charmeleon")

# Get current script directory for absolute paths
$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) {
    $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $SCRIPT_DIR) {
    $SCRIPT_DIR = Get-Location
}

# Output directory (absolute path)
$OUTPUT_DIR = Join-Path $SCRIPT_DIR "pokemon_data"

# Configuration
$MAX_RETRIES = 3
$RETRY_DELAY = 1
$LOG_FILE = Join-Path $SCRIPT_DIR "pokemon_parallel_fetch.log"
$TEMP_DIR = Join-Path $SCRIPT_DIR "temp_parallel"
$MAX_PARALLEL_JOBS = 5

# Create output and temp directories if they don't exist
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    Write-Host "Created directory: $OUTPUT_DIR"
}

if (-not (Test-Path $TEMP_DIR)) {
    New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
    Write-Host "Created temporary directory: $TEMP_DIR"
}

# Initialize log file
"=== Parallel Pokémon Fetch Log - $(Get-Date) ===" | Out-File -FilePath $LOG_FILE -Encoding UTF8

# Function to log messages
function Write-LogMessage {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Level`: $Message"
    
    # Write to log file
    $logEntry | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
    
    # Write to console with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "INFO"  { Write-Host $logEntry -ForegroundColor Green }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        default { Write-Host $logEntry }
    }
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
        $response = Invoke-WebRequest -Uri "https://pokeapi.co" -Method Head -TimeoutSec 10 -UseBasicParsing
        return $true
    }
    catch {
        return $false
    }
}

# Function to fetch a single Pokémon's data (runs as background job)
$FetchPokemonWorkerScript = {
    param(
        [string]$PokemonName,
        [int]$WorkerId,
        [string]$OutputDir,
        [string]$TempDir,
        [string]$ApiUrl,
        [int]$MaxRetries,
        [int]$RetryDelay
    )
    
    $outputFile = Join-Path $OutputDir "$PokemonName.json"
    $statusFile = Join-Path $TempDir "${PokemonName}_status.txt"
    $errorFile = Join-Path $TempDir "${PokemonName}_error.txt"
    $attempt = 1
    
    # Initialize status file
    "STARTED" | Out-File -FilePath $statusFile -Encoding UTF8
    
    # Function to validate Pokémon name (redefined in job scope)
    function Test-PokemonNameLocal {
        param([string]$Name)
        return ($Name -match '^[a-z-]+$') -and ($Name.Length -ge 3)
    }
    
    # Function to check network connectivity (redefined in job scope)
    function Test-NetworkConnectivityLocal {
        try {
            Invoke-WebRequest -Uri "https://pokeapi.co" -Method Head -TimeoutSec 10 -UseBasicParsing | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
    
    # Function to log messages (redefined in job scope)
    function Write-JobLog {
        param([string]$Level, [string]$Message)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        return "[$timestamp] $Level`: $Message"
    }
    
    # Validate Pokémon name
    if (-not (Test-PokemonNameLocal $PokemonName)) {
        "FAILED" | Out-File -FilePath $statusFile -Encoding UTF8
        "Invalid Pokémon name format: $PokemonName" | Out-File -FilePath $errorFile -Encoding UTF8
        return @{
            Status = "FAILED"
            Error = "Invalid Pokémon name format: $PokemonName"
            LogMessages = @(Write-JobLog "ERROR" "[Worker $WorkerId] Invalid Pokémon name format: $PokemonName")
        }
    }
    
    $logMessages = @()
    $logMessages += Write-JobLog "INFO" "[Worker $WorkerId] Starting fetch for $PokemonName"
    
    # Retry loop
    while ($attempt -le $MaxRetries) {
        $logMessages += Write-JobLog "INFO" "[Worker $WorkerId] Attempt $attempt/$MaxRetries for $PokemonName"
        
        # Check network connectivity before attempting
        if (-not (Test-NetworkConnectivityLocal)) {
            $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Network connectivity issue (attempt $attempt for $PokemonName)"
            if ($attempt -eq $MaxRetries) {
                "FAILED" | Out-File -FilePath $statusFile -Encoding UTF8
                "Network connectivity failed after $MaxRetries attempts" | Out-File -FilePath $errorFile -Encoding UTF8
                return @{
                    Status = "FAILED"
                    Error = "Network connectivity failed after $MaxRetries attempts"
                    LogMessages = $logMessages
                }
            }
            Start-Sleep -Seconds $RetryDelay
            $attempt++
            continue
        }
        
        try {
            # Make API request with timeout and error handling
            $response = Invoke-WebRequest -Uri "$ApiUrl/$PokemonName" -TimeoutSec 30 -UseBasicParsing
            
            # Check if response is successful
            if ($response.StatusCode -eq 200) {
                # Validate JSON content
                try {
                    $jsonContent = $response.Content | ConvertFrom-Json
                    $response.Content | Out-File -FilePath $outputFile -Encoding UTF8
                    
                    "SUCCESS" | Out-File -FilePath $statusFile -Encoding UTF8
                    $logMessages += Write-JobLog "INFO" "[Worker $WorkerId] Successfully fetched $PokemonName on attempt $attempt"
                    
                    return @{
                        Status = "SUCCESS"
                        LogMessages = $logMessages
                    }
                }
                catch {
                    $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Invalid JSON received (attempt $attempt for $PokemonName)"
                    if (Test-Path $outputFile) { Remove-Item $outputFile -Force }
                }
            }
            else {
                $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] HTTP error $($response.StatusCode) (attempt $attempt for $PokemonName)"
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            
            # Handle specific HTTP errors
            if ($errorMessage -match "404") {
                "FAILED" | Out-File -FilePath $statusFile -Encoding UTF8
                "Pokémon '$PokemonName' not found (HTTP 404)" | Out-File -FilePath $errorFile -Encoding UTF8
                $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Pokémon '$PokemonName' not found (HTTP 404)"
                if (Test-Path $outputFile) { Remove-Item $outputFile -Force }
                return @{
                    Status = "FAILED"
                    Error = "Pokémon '$PokemonName' not found (HTTP 404)"
                    LogMessages = $logMessages
                }
            }
            elseif ($errorMessage -match "429") {
                $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Rate limit exceeded (HTTP 429) (attempt $attempt for $PokemonName)"
                Start-Sleep -Seconds ($RetryDelay * 2)
            }
            elseif ($errorMessage -match "timeout") {
                $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Request timeout (attempt $attempt for $PokemonName)"
            }
            else {
                $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Request failed: $errorMessage (attempt $attempt for $PokemonName)"
            }
        }
        
        # If this was the last attempt, give up
        if ($attempt -eq $MaxRetries) {
            "FAILED" | Out-File -FilePath $statusFile -Encoding UTF8
            "Failed to fetch $PokemonName after $MaxRetries attempts" | Out-File -FilePath $errorFile -Encoding UTF8
            $logMessages += Write-JobLog "ERROR" "[Worker $WorkerId] Giving up on $PokemonName after $MaxRetries attempts"
            if (Test-Path $outputFile) { Remove-Item $outputFile -Force }
            return @{
                Status = "FAILED"
                Error = "Failed to fetch $PokemonName after $MaxRetries attempts"
                LogMessages = $logMessages
            }
        }
        
        # Wait before retrying
        Start-Sleep -Seconds $RetryDelay
        $attempt++
    }
    
    "FAILED" | Out-File -FilePath $statusFile -Encoding UTF8
    return @{
        Status = "FAILED"
        Error = "Unknown failure"
        LogMessages = $logMessages
    }
}

# Function to monitor background jobs
function Wait-ParallelJobs {
    param([array]$Jobs)
    
    $total = $Jobs.Count
    Write-Host "Monitoring $total background jobs..."
    
    while ($true) {
        $completed = ($Jobs | Where-Object { $_.State -eq "Completed" -or $_.State -eq "Failed" }).Count
        $running = ($Jobs | Where-Object { $_.State -eq "Running" }).Count
        
        Write-Host "Progress: $completed/$total jobs completed, $running running"
        
        if ($completed -eq $total) {
            Write-Host "All background jobs completed!"
            break
        }
        
        Start-Sleep -Seconds 1
    }
}

# Function to collect results from all jobs
function Get-JobResults {
    param([array]$Jobs)
    
    $successfulCount = 0
    $failedCount = 0
    
    Write-Host ""
    Write-Host "=== COLLECTING RESULTS ==="
    
    foreach ($job in $Jobs) {
        $pokemonName = $job.Name
        
        try {
            $result = Receive-Job -Job $job -Wait
            
            # Write job log messages to main log
            if ($result.LogMessages) {
                foreach ($logMessage in $result.LogMessages) {
                    $logMessage | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
                }
            }
            
            switch ($result.Status) {
                "SUCCESS" {
                    Write-Host "✅ $pokemonName`: Successfully fetched" -ForegroundColor Green
                    $successfulCount++
                }
                "FAILED" {
                    Write-Host "❌ $pokemonName`: Failed" -ForegroundColor Red
                    if ($result.Error) {
                        Write-Host "   Error: $($result.Error)" -ForegroundColor Red
                    }
                    $failedCount++
                }
                default {
                    Write-Host "⚠️  $pokemonName`: Unknown status ($($result.Status))" -ForegroundColor Yellow
                    $failedCount++
                }
            }
        }
        catch {
            Write-Host "❌ $pokemonName`: Job execution failed - $($_.Exception.Message)" -ForegroundColor Red
            $failedCount++
        }
        
        # Clean up job
        Remove-Job -Job $job -Force
    }
    
    Write-Host ""
    Write-Host "=== FINAL SUMMARY ==="
    Write-Host "Total Pokémon processed: $($POKEMON_LIST.Count)"
    Write-Host "Successful: $successfulCount" -ForegroundColor Green
    Write-Host "Failed: $failedCount" -ForegroundColor Red
    Write-Host "Success rate: $([math]::Round($successfulCount * 100 / $POKEMON_LIST.Count, 1))%"
    
    # Log final summary
    Write-LogMessage "INFO" "Parallel processing complete: $successfulCount successful, $failedCount failed"
    
    return $failedCount
}

# Function to cleanup temporary files
function Remove-TempFiles {
    Write-Host "Cleaning up temporary files..."
    if (Test-Path $TEMP_DIR) {
        Remove-Item -Path $TEMP_DIR -Recurse -Force
    }
    Write-Host "Cleanup completed."
}

# Main execution
function Start-ParallelProcessing {
    $startTime = Get-Date
    
    Write-Host "Starting parallel batch processing of $($POKEMON_LIST.Count) Pokémon..."
    Write-Host "Output directory: $OUTPUT_DIR"
    Write-Host "Max parallel jobs: $MAX_PARALLEL_JOBS"
    Write-Host "Max retries per Pokémon: $MAX_RETRIES"
    Write-Host "Log file: $LOG_FILE"
    Write-Host ""
    
    # Array to store background jobs
    $jobs = @()
    $workerId = 1
    
    # Launch background jobs for each Pokémon
    Write-Host "Launching parallel workers..."
    foreach ($pokemon in $POKEMON_LIST) {
        Write-Host "Starting worker $workerId for $pokemon..."
        
        $job = Start-Job -Name $pokemon -ScriptBlock $FetchPokemonWorkerScript -ArgumentList @(
            $pokemon,
            $workerId,
            $OUTPUT_DIR,
            $TEMP_DIR,
            $API_URL,
            $MAX_RETRIES,
            $RETRY_DELAY
        )
        
        $jobs += $job
        $workerId++
        
        # Optional: Add small delay to prevent overwhelming the API
        Start-Sleep -Milliseconds 100
    }
    
    Write-Host "All workers launched. Job IDs: $($jobs.Id -join ', ')"
    Write-Host ""
    
    # Monitor and wait for all background jobs to complete
    Wait-ParallelJobs -Jobs $jobs
    
    # Calculate execution time
    $endTime = Get-Date
    $executionTime = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    
    Write-Host ""
    Write-Host "All parallel processes completed in $executionTime seconds!"
    
    # Collect and display results
    $failedCount = Get-JobResults -Jobs $jobs
    
    # Cleanup temporary files
    Remove-TempFiles
    
    # Display performance summary
    Write-Host ""
    Write-Host "=== PERFORMANCE SUMMARY ==="
    Write-Host "Total execution time: $executionTime seconds"
    Write-Host "Average time per Pokémon: $([math]::Round($executionTime * 1000 / $POKEMON_LIST.Count, 0)) ms"
    Write-Host "Parallel efficiency: ~$([math]::Round($POKEMON_LIST.Count * 100 / $executionTime, 0))% faster than sequential"
    
    if ($failedCount -eq 0) {
        Write-Host "✅ All Pokémon data retrieved successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "⚠️  Some requests failed. Check the log file: $LOG_FILE" -ForegroundColor Yellow
        exit 1
    }
}

# Set up cleanup on exit
try {
    # Run main function
    Start-ParallelProcessing
}
finally {
    # Ensure cleanup happens even if script is interrupted
    Remove-TempFiles
}