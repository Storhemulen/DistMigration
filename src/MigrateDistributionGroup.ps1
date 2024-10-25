#Requires -Modules ActiveDirectory
#Requires -Modules @{ModuleName="Logging";ModuleVersion="1.0.0"}
#Requires -Modules @{ModuleName="Validation";ModuleVersion="1.0.0"}

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceGroupName,

    [Parameter(Mandatory=$false)]
    [string]$DefaultOwner,

    [switch]$DryRun
)

# Import required modules
Import-Module -Name "$PSScriptRoot\modules\Logging.psm1" -Force
Import-Module -Name "$PSScriptRoot\modules\Validation.psm1" -Force

# Load configuration
$config = Get-Content -Path "$PSScriptRoot\config.json" -Raw | ConvertFrom-Json
$defaultSettings = $config.DefaultSettings

# Validate input parameters
if (-not (Test-GroupName -GroupName $SourceGroupName)) {
    Write-Log -Message "Invalid group name: $SourceGroupName" -Level "ERROR"
    return
}

if ($DefaultOwner -and -not (Test-EmailAddress -EmailAddress $DefaultOwner)) {
    Write-Log -Message "Invalid default owner email: $DefaultOwner" -Level "ERROR"
    return
}

# Set default values from configuration
$domain = $defaultSettings.Domain
$adSyncServer = $defaultSettings.ADSyncServer
$nonAzureSyncedOU = $defaultSettings.NonAzureSyncedOU
$logPath = Join-Path -Path $defaultSettings.LogPath -ChildPath "MigrationLog-$SourceGroupName-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
$syncTimeout = $defaultSettings.SyncTimeout
$batchSize = $defaultSettings.BatchSize

# Main migration function
function Start-DistributionGroupMigration {
    Write-Log -Message "Starting migration process for group: $SourceGroupName" -Level "INFO"

    # Write original group details to file
    $originalDetailsFilePath = ".\OriginalGroupDetails-$SourceGroupName-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    Write-GroupDetailsToFile -GroupName $SourceGroupName -FilePath $originalDetailsFilePath

    # Perform migration steps here...

    # Verify migration
    try {
        $newGroup = Get-DistributionGroup -Identity $SourceGroupName
        $newMembers = Get-DistributionGroupMember -Identity $SourceGroupName -ResultSize Unlimited
        $memberDifference = Compare-Object -ReferenceObject $members -DifferenceObject $newMembers -Property PrimarySmtpAddress
        if ($memberDifference.Count -eq 0) {
            Write-Log -Message "Migration completed successfully. All members match." -Level "INFO"
        } else {
            Write-Log -Message "Migration completed with discrepancies. Please review the results:" -Level "WARNING"
            $memberDifference | ForEach-Object {
                if ($_.SideIndicator -eq "<=") {
                    Write-Log -Message "  Member missing from new group: $($_.PrimarySmtpAddress)" -Level "WARNING"
                } else {
                    Write-Log -Message "  Extra member in new group: $($_.PrimarySmtpAddress)" -Level "WARNING"
                }
            }
        }
    } catch {
        Write-Log -Message "Error verifying migration: $_" -Level "ERROR"
    }
}

# Function to write group details to a file
function Write-GroupDetailsToFile {
    param(
        [string]$GroupName,
        [string]$FilePath
    )
    try {
        $group = Get-DistributionGroup -Identity $GroupName -ErrorAction Stop
        $members = Get-DistributionGroupMember -Identity $GroupName -ResultSize Unlimited

        $details = @"
Group Name: $($group.Name)
Display Name: $($group.DisplayName)
Alias: $($group.Alias)
Primary Email: $($group.PrimarySmtpAddress)
Description: $($group.Description)
Members: $($members | ForEach-Object { $_.PrimarySmtpAddress } | Out-String)
"@

        Set-Content -Path $FilePath -Value $details
        Write-Log -Message "Group details written to $FilePath" -Level "INFO" -LogPath $logPath
    } catch {
        Write-Log -Message "Error writing group details to file: $_" -Level "ERROR" -LogPath $logPath
    }
}

# Main execution
if (-not (Test-Module "ActiveDirectory")) { exit }

try {
    Start-DistributionGroupMigration
} catch {
    Write-Log -Message "An unexpected error occurred during migration: $_" -Level "ERROR" -LogPath $logPath
}
