# Jamf Uptime Champions Report

A bash script that generates a report of the top 25 Mac users with the longest uptime in your Jamf Pro environment. Features intelligent caching to optimize API usage and reduce scan times.

## Features

- 🏆 **Rankings**: Displays top 25 users with longest uptime
- ⚡ **Smart Caching**: Only scans top 50 computers after initial full scan
- 🔄 **Auto-Refresh**: Full scan every 2 weeks to catch new long-uptime machines
- 📊 **Detailed Output**: Shows uptime in days/hours, username, email, and computer name
- 🛡️ **Error Handling**: Gracefully handles missing data and API errors

## Files in This Repository

- **uptime-champs.sh** - Main script that generates the uptime champions report
- **debug-uptime-ea.sh** - Debug tool to inspect extension attributes for a specific computer
- **list-extension-attributes.sh** - Lists all extension attributes in your Jamf instance
- **sample-computers.sh** - Shows first 10 computers for testing
- **.env.example** - Template for environment variables (copy to `.env` and fill in)
- **.env** - Your credentials (DO NOT COMMIT - excluded by .gitignore)
- **.gitignore** - Ensures sensitive files aren't committed to git
- **README.md** - This documentation

## Prerequisites

- **jq**: JSON processor for parsing API responses
  ```bash
  # macOS
  brew install jq

  # Linux
  apt-get install jq  # Debian/Ubuntu
  yum install jq      # RHEL/CentOS
  ```

- **Jamf Pro API Credentials**: OAuth client ID and secret with read access to:
  - Computer inventory
  - Extension attributes

- **Jamf Extension Attribute**: An extension attribute named "Uptime" that stores the last boot time in format: `YYYY-MM-DD HH:MM:SS`

## Setup

### 1. Configure Jamf API Credentials

Create a `.env` file in the same directory as the scripts:

```bash
# Copy the example file
cp .env.example .env

# Edit the .env file with your credentials
nano .env
```

Add your Jamf Pro API credentials to `.env`:

```bash
JAMF_CLIENT_ID="your-client-id-here"
JAMF_CLIENT_SECRET="your-client-secret-here"
JAMF_URL="https://your-instance.jamfcloud.com"
```

> **Security Note**: The `.env` file is ignored by git and will not be committed to version control. Never commit credentials to your repository.

### 2. Verify Extension Attribute Name

The script expects an extension attribute named **"Uptime"** (line 16). To verify or find your extension attribute name:

```bash
# Run the list-extension-attributes.sh helper script
./list-extension-attributes.sh
```

Or check in Jamf Pro:
- Settings → Computer Management → Extension Attributes
- Find your uptime extension attribute
- Copy the exact **Display Name**

If your extension attribute has a different name, update the `UPTIME_EA_NAME` variable in [uptime-champs.sh](uptime-champs.sh):

```bash
UPTIME_EA_NAME="Your Exact EA Name Here"
```

### 3. Configure Cache Settings (Optional)

> **Note**: You only need to modify these if you want to change the default caching behavior.

Adjust caching behavior by modifying these variables (lines 21-22):

```bash
CACHE_MAX_AGE_DAYS=14  # Days before forcing full scan (default: 14)
CACHE_TOP_N=50         # Number of top computers to cache (default: 50)
```

## Usage

### Basic Usage

```bash
# Make script executable
chmod +x uptime-champs.sh

# Run the report
./uptime-champs.sh
```

### Command Line Options

```bash
# Force a full scan of all computers (ignores cache)
./uptime-champs.sh --full-scan
./uptime-champs.sh -f
```

## How It Works

### First Run (Full Scan)
1. Authenticates with Jamf Pro API
2. Retrieves all computer IDs
3. Queries each computer for uptime data
4. Calculates uptime from boot timestamp
5. Saves top 50 results to cache file
6. Displays top 25 users

**Time**: Depends on computer count (~0.1s per computer + API latency)

### Subsequent Runs (Quick Scan)
1. Checks if cache exists and is < 14 days old
2. Only queries the 50 computers from cache
3. Recalculates their current uptime
4. Re-sorts and displays top 25

**Time**: ~5-10 seconds (only 50 API calls)

### Cache Refresh
- Automatic full scan after 14 days
- Manual full scan anytime with `--full-scan` flag
- Cache location: `~/.jamf_uptime_cache/top50_cache.txt`

## Output Example

```
=========================================
Jamf Uptime Champions Report
=========================================

Authentication successful.

Cache found (3 days old). Performing quick scan of top 50 machines...
Use --full-scan or -f flag to force a full scan of all computers.

Quick scan mode: Checking 50 computers from cache...

Processing: 50/50 computers... Done!

Updated cache with top 50 results at: /Users/admin/.jamf_uptime_cache/top50_cache.txt

=========================================
TOP 25 LONGEST UPTIME CHAMPIONS
=========================================

RANK   UPTIME          USERNAME                       EMAIL                          COMPUTER
------ --------------- ------------------------------ ------------------------------ --------------------
1.     87d 14h         john.doe@company.com           john.doe@company.com           MacBook-Pro-123
2.     76d 3h          jane.smith@company.com         jane.smith@company.com         iMac-Marketing-05
3.     68d 22h         bob.jones@company.com          bob.jones@company.com          Mac-Mini-Dev-12
...

=========================================
Report completed successfully
=========================================

Quick scan mode: Scanned top 50 computers from cache
Next full scan will run in 11 days
Run with --full-scan or -f flag to force a full scan now

Note: Uptime is based on the 'Uptime' extension attribute in Jamf
```

## Helper Scripts

### list-extension-attributes.sh
Lists all computer extension attributes in your Jamf instance with their exact names.

```bash
./list-extension-attributes.sh
```

### debug-uptime-ea.sh
Debugs a specific computer's extension attributes. Accepts computer ID or serial number.

```bash
./debug-uptime-ea.sh 123              # By computer ID
./debug-uptime-ea.sh SERIALNUMBER123  # By serial number
```

### sample-computers.sh
Shows the first 10 computers with their IDs for testing.

```bash
./sample-computers.sh
```

## Troubleshooting

### No uptime data found
- Verify the extension attribute name matches exactly (case-sensitive)
- Check that computers are reporting to Jamf and extension attribute is populated
- Run `debug-uptime-ea.sh` with a computer ID to see raw data

### Authentication failed
- Verify CLIENT_ID and CLIENT_SECRET are correct
- Ensure API credentials have proper permissions
- Check JAMF_URL is correct (include https://)

### jq command not found
- Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux)

### Invalid date format errors
- Verify your Uptime extension attribute stores dates as: `YYYY-MM-DD HH:MM:SS`
- Run `debug-uptime-ea.sh` to see actual date format

## Cache Management

Cache is stored at: `~/.jamf_uptime_cache/top50_cache.txt`

```bash
# View cache contents
cat ~/.jamf_uptime_cache/top50_cache.txt

# Clear cache (forces full scan on next run)
rm -rf ~/.jamf_uptime_cache

# Check cache age
ls -lh ~/.jamf_uptime_cache/top50_cache.txt
```

## Performance

- **Full Scan**: ~0.1s per computer + API latency
  - 500 computers: ~1-2 minutes
  - 1000 computers: ~3-4 minutes

- **Quick Scan**: ~5-10 seconds (50 computers)

## Security Considerations

- **Credentials Storage**: All credentials are stored in `.env` file, which is excluded from git via `.gitignore`
- **File Permissions**: Protect your `.env` file and scripts:
  ```bash
  chmod 600 .env                    # Only owner can read/write
  chmod 700 *.sh                     # Only owner can execute scripts
  ```
- **API Permissions**: Use least-privilege API credentials (read-only access)
- **API Roles**: Consider using Jamf API roles with specific scopes
- **Never Commit**: Never commit the `.env` file to version control
  - The `.env.example` file is provided as a template
  - The `.gitignore` file ensures `.env` is never tracked

## Contributing

Contributions welcome! Feel free to submit issues or pull requests.

## License

MIT License - feel free to use and modify as needed.

## Author

Created for Jamf Pro administrators who want to identify users who need to restart their computers.
