# Distribution Group Migration Script

A PowerShell script for migrating distribution groups while maintaining their members and properties.

## Prerequisites

- PowerShell 5.1 or higher
- Required PowerShell modules:
  - ActiveDirectory
  - Exchange Online PowerShell V2

## Installation

1. Clone this repository or download the script files
2. Ensure all files are in the correct directory structure:
   ```
   src/
   ├── MigrateDistributionGroup.ps1
   ├── config.json
   ├── modules/
   │   ├── logging.psm1
   │   └── validation.psm1
   ```
3. Update the `config.json` file with your environment-specific settings

## Configuration

Edit `config.json` to configure default settings:

```json
{
    "DefaultSettings": {
        "Domain": "your-domain.com",
        "ADSyncServer": "your-sync-server",
        "NonAzureSyncedOU": "OU=NonSynced,DC=domain,DC=com",
        "LogPath": "./logs",
        "SyncTimeout": 1200,
        "BatchSize": 100
    }
}
```

## Usage

```powershell
.\MigrateDistributionGroup.ps1 -SourceGroupName "GroupName" [-DefaultOwner "owner@domain.com"] [-DryRun]
```

### Parameters

- `-SourceGroupName` (Required): Name of the distribution group to migrate
- `-DefaultOwner` (Optional): Email address of the default owner if none exists
- `-DryRun` (Switch): Perform a test run without making actual changes

### Examples

```powershell
# Basic migration
.\MigrateDistributionGroup.ps1 -SourceGroupName "Marketing Team"

# Migration with default owner
.\MigrateDistributionGroup.ps1 -SourceGroupName "Sales Team" -DefaultOwner "admin@company.com"

# Test run without making changes
.\MigrateDistributionGroup.ps1 -SourceGroupName "IT Support" -DryRun
```

## Features

- Validates input parameters and group names
- Comprehensive logging with timestamps
- Backs up original group details before migration
- Verifies migration success
- Supports dry run mode for testing
- Handles special characters in group names
- Error handling and detailed logging

## Logging

Logs are written to both the console and a file (if specified in config.json):
- INFO: Normal operations (green)
- WARNING: Non-critical issues (yellow)
- ERROR: Critical issues (red)
- DEBUG: Detailed information (gray)

Log files are created with the naming pattern:
`MigrationLog-{GroupName}-{Timestamp}.txt`

## Error Handling

The script includes comprehensive error handling:
- Input validation
- Group existence checks
- Member migration verification
- Detailed error messages in logs

## Support Files

- `logging.psm1`: Handles all logging functionality
- `validation.psm1`: Contains validation functions for emails and group names
- `config.json`: Stores default configuration settings

## Troubleshooting

1. Check the log files in the configured log directory
2. Ensure all required PowerShell modules are installed
3. Verify proper permissions for the executing account
4. Review the original group details file for comparison

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
