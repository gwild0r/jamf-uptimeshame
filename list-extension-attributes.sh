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
echo "Jamf Extension Attributes List"
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

# Get list of all computer extension attributes
echo "Retrieving extension attributes..."
EXTENSION_ATTRIBUTES=$(curl -s -X GET \
  "$JAMF_URL/JSSResource/computerextensionattributes" \
  -H 'accept: application/json' \
  -H "Authorization: Bearer $TOKEN")

# Check if data was retrieved
if [ -z "$EXTENSION_ATTRIBUTES" ]; then
  echo "Error: Failed to retrieve extension attributes."
  exit 1
fi

# Display extension attributes in a formatted table
echo "Computer Extension Attributes:"
echo "----------------------------------------"
printf "%-5s %-50s %-15s\n" "ID" "NAME" "ENABLED"
printf "%-5s %-50s %-15s\n" "-----" "--------------------------------------------------" "---------------"

echo "$EXTENSION_ATTRIBUTES" | jq -r '.computer_extension_attributes[] | "\(.id)|\(.name)|\(.enabled)"' | \
while IFS='|' read -r ID NAME ENABLED; do
    printf "%-5s %-50s %-15s\n" "$ID" "$NAME" "$ENABLED"
done

echo "----------------------------------------"
echo ""
echo "Look for an extension attribute related to 'uptime' in the list above."
echo "Copy the exact NAME value and use it in the uptime-champs.sh script."
