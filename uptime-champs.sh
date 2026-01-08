#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is required but not installed."
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load environment variables from .env file
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    # Export variables from .env file
    export $(cat "$ENV_FILE" | grep -v '^#' | grep -v '^[[:space:]]*$' | xargs)
else
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please create a .env file with your Jamf credentials."
    echo "See .env.example for template."
    exit 1
fi

# Verify required environment variables are set
if [ -z "$JAMF_CLIENT_ID" ] || [ -z "$JAMF_CLIENT_SECRET" ] || [ -z "$JAMF_URL" ]; then
    echo "Error: Missing required environment variables in .env file"
    echo "Required: JAMF_CLIENT_ID, JAMF_CLIENT_SECRET, JAMF_URL"
    exit 1
fi

# Use environment variables
CLIENT_ID="$JAMF_CLIENT_ID"
CLIENT_SECRET="$JAMF_CLIENT_SECRET"
JAMF_URL="$JAMF_URL"

# Extension Attribute name for uptime
UPTIME_EA_NAME="Uptime"  # Modify this to match your exact EA name in Jamf

# Cache configuration
CACHE_DIR="$HOME/.jamf_uptime_cache"
CACHE_FILE="$CACHE_DIR/top50_cache.txt"
CACHE_MAX_AGE_DAYS=14  # 2 weeks
CACHE_TOP_N=50

# Force full scan flag
FORCE_FULL_SCAN=false
if [ "$1" == "--full-scan" ] || [ "$1" == "-f" ]; then
    FORCE_FULL_SCAN=true
fi

echo "========================================="
echo "Jamf Uptime Champions Report"
echo "========================================="
echo ""

# Get the Bearer token
echo "Authenticating with Jamf..."
TOKEN=$(curl -s -X POST \
  "$JAMF_URL/api/oauth/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" | jq -r '.access_token')

# Check if the token was retrieved successfully
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Error: Failed to retrieve Bearer token."
  exit 1
fi

echo "Authentication successful."
echo ""

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Check if cache exists and is recent
CACHE_VALID=false
SCAN_MODE="full"

if [ -f "$CACHE_FILE" ] && [ "$FORCE_FULL_SCAN" = false ]; then
    # Get cache file age in days
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        CACHE_AGE_SECONDS=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE") ))
    else
        # Linux
        CACHE_AGE_SECONDS=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    fi
    CACHE_AGE_DAYS=$((CACHE_AGE_SECONDS / 86400))

    if [ "$CACHE_AGE_DAYS" -lt "$CACHE_MAX_AGE_DAYS" ]; then
        CACHE_VALID=true
        SCAN_MODE="quick"
        echo "Cache found (${CACHE_AGE_DAYS} days old). Performing quick scan of top $CACHE_TOP_N machines..."
        echo "Use --full-scan or -f flag to force a full scan of all computers."
    else
        echo "Cache is ${CACHE_AGE_DAYS} days old (older than $CACHE_MAX_AGE_DAYS days). Performing full scan..."
    fi
else
    if [ "$FORCE_FULL_SCAN" = true ]; then
        echo "Full scan requested. Scanning all computers..."
    else
        echo "No cache found. Performing initial full scan..."
    fi
fi

echo ""

# Determine which computers to scan
if [ "$CACHE_VALID" = true ]; then
    # Quick scan: only scan the top 50 from cache
    COMPUTER_IDS=$(cut -d'|' -f8 "$CACHE_FILE" | head -${CACHE_TOP_N})
    COMPUTER_COUNT=$(echo "$COMPUTER_IDS" | wc -l)
    echo "Quick scan mode: Checking $COMPUTER_COUNT computers from cache..."
else
    # Full scan: get all computers
    echo "Retrieving computer list..."
    ALL_COMPUTERS=$(curl -s -X GET \
      "$JAMF_URL/JSSResource/computers" \
      -H 'accept: application/json' \
      -H "Authorization: Bearer $TOKEN")

    # Extract computer IDs
    COMPUTER_IDS=$(echo "$ALL_COMPUTERS" | jq -r '.computers[].id')

    if [ -z "$COMPUTER_IDS" ]; then
      echo "Error: Failed to retrieve computer list."
      exit 1
    fi

    COMPUTER_COUNT=$(echo "$COMPUTER_IDS" | wc -l)
    echo "Found $COMPUTER_COUNT computers. Retrieving uptime data..."
fi

echo ""

# Create temporary file to store results
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Counter for progress
COUNTER=0

# Loop through each computer and extract uptime
for COMPUTER_ID in $COMPUTER_IDS; do
    COUNTER=$((COUNTER + 1))

    # Show progress every 10 computers
    if [ $((COUNTER % 10)) -eq 0 ]; then
        echo "Processing: $COUNTER/$COMPUTER_COUNT computers..."
    fi

    # Get detailed computer information
    COMPUTER_DATA=$(curl -s -X GET \
      "$JAMF_URL/JSSResource/computers/id/$COMPUTER_ID" \
      -H 'accept: application/json' \
      -H "Authorization: Bearer $TOKEN")

    # Check if we got valid data back
    if [ -z "$COMPUTER_DATA" ]; then
        continue
    fi

    # Verify the response contains computer data
    if ! echo "$COMPUTER_DATA" | jq -e '.computer' > /dev/null 2>&1; then
        continue
    fi

    # Extract relevant fields with error suppression
    USERNAME=$(echo "$COMPUTER_DATA" | jq -r '.computer.location.username // "N/A"' 2>/dev/null)
    EMAIL=$(echo "$COMPUTER_DATA" | jq -r '.computer.location.email_address // "N/A"' 2>/dev/null)
    COMPUTER_NAME=$(echo "$COMPUTER_DATA" | jq -r '.computer.general.name // "N/A"' 2>/dev/null)
    SERIAL=$(echo "$COMPUTER_DATA" | jq -r '.computer.general.serial_number // "N/A"' 2>/dev/null)

    # Extract uptime from extension attributes with null check
    BOOT_TIME=$(echo "$COMPUTER_DATA" | jq -r --arg ea_name "$UPTIME_EA_NAME" \
      'if .computer.extension_attributes then (.computer.extension_attributes[] | select(.name == $ea_name) | .value) else empty end' 2>/dev/null)

    # Only add to results if boot time value exists and is not empty
    if [ -n "$BOOT_TIME" ] && [ "$BOOT_TIME" != "N/A" ] && [ "$BOOT_TIME" != "null" ]; then
        # Calculate uptime in days from boot timestamp (format: YYYY-MM-DD HH:MM:SS)
        # Convert boot time to epoch seconds
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS date command
            BOOT_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$BOOT_TIME" +%s 2>/dev/null)
        else
            # Linux date command
            BOOT_EPOCH=$(date -d "$BOOT_TIME" +%s 2>/dev/null)
        fi

        # Only process if we successfully converted the date
        if [ -n "$BOOT_EPOCH" ] && [ "$BOOT_EPOCH" -gt 0 ]; then
            # Get current time in epoch seconds
            CURRENT_EPOCH=$(date +%s)

            # Calculate uptime in seconds and convert to days
            UPTIME_SECONDS=$((CURRENT_EPOCH - BOOT_EPOCH))
            UPTIME_DAYS=$((UPTIME_SECONDS / 86400))

            # Calculate hours for display
            REMAINING_HOURS=$(( (UPTIME_SECONDS % 86400) / 3600 ))

            # Format display string
            UPTIME_DISPLAY="${UPTIME_DAYS}d ${REMAINING_HOURS}h"

            # Only add if uptime is positive
            if [ "$UPTIME_DAYS" -ge 0 ]; then
                # Format: UPTIME_DAYS|USERNAME|EMAIL|COMPUTER_NAME|SERIAL|UPTIME_DISPLAY|BOOT_TIME|COMPUTER_ID
                echo "$UPTIME_DAYS|$USERNAME|$EMAIL|$COMPUTER_NAME|$SERIAL|$UPTIME_DISPLAY|$BOOT_TIME|$COMPUTER_ID" >> "$TEMP_FILE"
            fi
        fi
    fi

    # Small delay to avoid overwhelming the API
    sleep 0.1
done

echo "Processing: $COUNTER/$COMPUTER_COUNT computers... Done!"
echo ""
echo "========================================="
echo "TOP 25 LONGEST UPTIME CHAMPIONS"
echo "========================================="
echo ""

# Check if we have any results
if [ ! -s "$TEMP_FILE" ]; then
    echo "No uptime data found. Please verify:"
    echo "1. The extension attribute name is correct: '$UPTIME_EA_NAME'"
    echo "2. Computers have reported uptime data"
    exit 1
fi

# Sort by uptime (descending) and save top 50 to cache
sort -t'|' -k1 -rn "$TEMP_FILE" | head -${CACHE_TOP_N} > "$CACHE_FILE"

echo "Updated cache with top ${CACHE_TOP_N} results at: $CACHE_FILE"
echo ""

# Sort by uptime (descending) and display top 25
printf "%-6s %-15s %-30s %-30s %-20s\n" "RANK" "UPTIME" "USERNAME" "EMAIL" "COMPUTER"
printf "%-6s %-15s %-30s %-30s %-20s\n" "------" "---------------" "------------------------------" "------------------------------" "--------------------"

RANK=1
sort -t'|' -k1 -rn "$TEMP_FILE" | head -25 | while IFS='|' read -r UPTIME_DAYS USERNAME EMAIL COMPUTER_NAME SERIAL UPTIME_DISPLAY BOOT_TIME COMPUTER_ID; do
    # Truncate long values for display
    USERNAME_SHORT=$(echo "$USERNAME" | cut -c1-30)
    EMAIL_SHORT=$(echo "$EMAIL" | cut -c1-30)
    COMPUTER_SHORT=$(echo "$COMPUTER_NAME" | cut -c1-20)

    printf "%-6s %-15s %-30s %-30s %-20s\n" "$RANK." "$UPTIME_DISPLAY" "$USERNAME_SHORT" "$EMAIL_SHORT" "$COMPUTER_SHORT"

    RANK=$((RANK + 1))
done

echo ""
echo "========================================="
echo "Report completed successfully"
echo "========================================="
echo ""
if [ "$SCAN_MODE" = "quick" ]; then
    echo "Quick scan mode: Scanned top $CACHE_TOP_N computers from cache"
    echo "Next full scan will run in $((CACHE_MAX_AGE_DAYS - CACHE_AGE_DAYS)) days"
    echo "Run with --full-scan or -f flag to force a full scan now"
else
    echo "Full scan mode: Scanned all $COMPUTER_COUNT computers"
    echo "Cache saved. Next run will use quick scan for $CACHE_MAX_AGE_DAYS days"
fi
echo ""
echo "Note: Uptime is based on the '$UPTIME_EA_NAME' extension attribute in Jamf"
