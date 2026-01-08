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

echo "========================================="
echo "Sample Computer List"
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

# Get list of all computers
echo "Retrieving computer list..."
ALL_COMPUTERS=$(curl -s -X GET \
  "$JAMF_URL/JSSResource/computers" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer $TOKEN")

# Display first 10 computers with their IDs, names, and serial numbers
echo "First 10 computers in your Jamf instance:"
echo "----------------------------------------"
printf "%-8s %-30s %-20s\n" "ID" "NAME" "SERIAL"
printf "%-8s %-30s %-20s\n" "--------" "------------------------------" "--------------------"

echo "$ALL_COMPUTERS" | jq -r '.computers[0:10][] | "\(.id)|\(.name)|\(.serial_number)"' | \
while IFS='|' read -r ID NAME SERIAL; do
    NAME_SHORT=$(echo "$NAME" | cut -c1-30)
    SERIAL_SHORT=$(echo "$SERIAL" | cut -c1-20)
    printf "%-8s %-30s %-20s\n" "$ID" "$NAME_SHORT" "$SERIAL_SHORT"
done

echo ""
echo "Use one of these IDs with the debug script:"
echo "./debug-uptime-ea.sh <ID>"
