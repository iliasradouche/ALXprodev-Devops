# Data extraction script for Pokémon information
# Uses jq and PowerShell to extract and format data from data.json

# Extract name using jq
$name = jq -r '.name' data.json

# Extract height using jq (in decimeters, convert to meters)
$height_dm = jq -r '.height' data.json

# Extract weight using jq (in hectograms, convert to kg)
$weight_hg = jq -r '.weight' data.json

# Extract type using jq (get first type name)
$type = jq -r '.types[0].type.name' data.json

# Convert height from decimeters to meters
$height_m = [math]::Round([double]$height_dm / 10, 1)

# Convert weight from hectograms to kg
$weight_kg = [math]::Round([double]$weight_hg / 10, 0)

# Capitalize the first letter of name and type
$name_capitalized = (Get-Culture).TextInfo.ToTitleCase($name.ToLower())
$type_capitalized = (Get-Culture).TextInfo.ToTitleCase($type.ToLower())

# Format and output the final result
Write-Output "$name_capitalized is of type $type_capitalized, weighs ${weight_kg}kg, and is ${height_m}m tall."