# Distribution Group Migration Tool

This tool migrates distribution groups from hybrid Exchange to cloud-only (Exchange Online) configuration.

## Features
- Migrates distribution group settings and members
- Preserves email aliases and group properties
- Supports batch processing for large groups
- Includes detailed logging and validation
- Dry-run option for testing

## Prerequisites
- Exchange Online Management module
- Active Directory module
- Appropriate permissions in both Exchange Online and on-premises AD
- Configuration file (config.json) with proper settings

## Usage
```powershell
# Test prerequisites first
.\Test-MigrationPrerequisites.ps1

# Perform migration (with optional default owner)
.\MigrateDistributionGroup.ps1 -SourceGroupName "GroupName" [-DefaultOwner "owner@domain.com"] [-DryRun]
```

## Logging
Logs are written to the configured log directory with timestamps and full details of the migration process.
