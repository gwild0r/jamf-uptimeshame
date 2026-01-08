#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "Error: jq is required but not installed."
    exit 1
fi

# Check if computer ID/serial argument was provided
if [ -z "$1" ]; then
    echo "Error: Computer ID or Serial Number is required."
    echo "Usage: $0 <computer_id_or_serial>"
    echo "Example: $0 123"
    echo "Example: $0 SERIALNUMBER123"
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
IDENTIFIER="$1"

echo "========================================="
echo "Extension Attribute Debug Script"
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

# Determine if we have an ID (numeric) or serial number (alphanumeric)
if [[ "$IDENTIFIER" =~ ^[0-9]+$ ]]; then
    # It's a numeric ID
    echo "Using computer ID: $IDENTIFIER..."
    ENDPOINT="id/$IDENTIFIER"
else
    # It's likely a serial number
    echo "Using serial number: $IDENTIFIER..."
    ENDPOINT="serialnumber/$IDENTIFIER"
fi

# Get detailed computer information
echo "Retrieving data..."
COMPUTER_DATA=$(curl -s -X GET \
  "$JAMF_URL/JSSResource/computers/$ENDPOINT" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer $TOKEN")

# Check if we got data
if [ -z "$COMPUTER_DATA" ]; then
  echo "Error: No data returned."
  exit 1
fi

# Check if the response is valid JSON
if ! echo "$COMPUTER_DATA" | jq empty 2>/dev/null; then
  echo "Error: Invalid JSON response received."
  echo "Raw Response (first 500 characters):"
  echo "----------------------------------------"
  echo "$COMPUTER_DATA" | head -c 500
  echo ""
  echo "----------------------------------------"
  exit 1
fi

# Check if computer was found
if echo "$COMPUTER_DATA" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error: Computer not found or API error."
  echo "$COMPUTER_DATA" | jq '.'
  exit 1
fi

# Display computer basic info
echo "Computer Information:"
echo "----------------------------------------"
COMPUTER_NAME=$(echo "$COMPUTER_DATA" | jq -r '.computer.general.name // "N/A"')
USERNAME=$(echo "$COMPUTER_DATA" | jq -r '.computer.location.username // "N/A"')
COMPUTER_ID=$(echo "$COMPUTER_DATA" | jq -r '.computer.general.id // "N/A"')
echo "Computer ID: $COMPUTER_ID"
echo "Computer Name: $COMPUTER_NAME"
echo "Username: $USERNAME"
echo ""

# Display ALL extension attributes for this computer
echo "ALL Extension Attributes:"
echo "----------------------------------------"
echo "$COMPUTER_DATA" | jq -r '.computer.extension_attributes[] | "ID: \(.id)\nName: \(.name)\nValue: \(.value)\n---"'
echo ""

# Look for uptime-related attributes
echo "Searching for 'uptime' (case-insensitive):"
echo "----------------------------------------"
echo "$COMPUTER_DATA" | jq -r '.computer.extension_attributes[] | select(.name | ascii_downcase | contains("uptime")) | "ID: \(.id)\nName: \(.name)\nValue: \(.value)\nType: \(.type)\n---"'

echo ""
echo "========================================="
echo "Raw JSON for extension_attributes:"
echo "========================================="
echo "$COMPUTER_DATA" | jq '.computer.extension_attributes'
