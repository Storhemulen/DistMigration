#Requires -Modules ActiveDirectory
#Requires -Modules ExchangeOnlineManagement
#Requires -Modules @{ModuleName="Logging"}
#Requires -Modules @{ModuleName="Validation"}

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceGroupName,

    [Parameter(Mandatory=$false)]
    [string]$DefaultOwner,

    [Parameter(Mandatory=$false)]
    [string]$NotificationEmail,

    [switch]$DryRun,
    
    [switch]$NoRollback
)

# For progress bar
$ProgressPreference = 'Continue'

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
function Start-Rollback {
    param(
        [string]$GroupName,
        [string]$OriginalDetailsFile
    )
    
    Write-Log -Message "Starting rollback for group: $GroupName" -Level "WARNING" -LogPath $logPath
    
    try {
        # Remove the new group
        Remove-DistributionGroup -Identity $GroupName -Confirm:$false -ErrorAction Stop
        Write-Log -Message "Successfully removed migrated group" -Level "INFO" -LogPath $logPath
        
        # Log original details
        if (Test-Path $OriginalDetailsFile) {
            Write-Log -Message "Original group details preserved in: $OriginalDetailsFile" -Level "INFO" -LogPath $logPath
        }
        
        return $true
    }
    catch {
        Write-Log -Message "Failed to rollback changes: $_" -Level "ERROR" -LogPath $logPath
        return $false
    }
}

function Start-DistributionGroupMigration {
    Write-Log -Message "Starting migration process for group: $SourceGroupName" -Level "INFO" -LogPath $logPath

    # Write original group details to file
    $originalDetailsFilePath = ".\OriginalGroupDetails-$SourceGroupName-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    Write-GroupDetailsToFile -GroupName $SourceGroupName -FilePath $originalDetailsFilePath

    # Get original group details and members
    try {
        $originalGroup = Get-DistributionGroup -Identity $SourceGroupName -ErrorAction Stop
        $members = Get-DistributionGroupMember -Identity $SourceGroupName -ResultSize Unlimited
        Write-Log -Message "Retrieved $($members.Count) members from source group" -Level "INFO" -LogPath $logPath
    }
    catch {
        Write-Log -Message "Failed to get original group details: $_" -Level "ERROR" -LogPath $logPath
        return
    }

    if ($DryRun) {
        Write-Log -Message "Dry run - would migrate these settings:" -Level "INFO" -LogPath $logPath
        Write-Log -Message "Group Name: $($originalGroup.Name)" -Level "INFO" -LogPath $logPath
        Write-Log -Message "Members Count: $($members.Count)" -Level "INFO" -LogPath $logPath
        Write-Log -Message "Dry run completed. No changes made." -Level "INFO" -LogPath $logPath
        return
    }

    # Perform the migration
    try {
        # Verify target OU exists
        if (-not (Get-ADOrganizationalUnit -Identity $nonAzureSyncedOU)) {
            Write-Log -Message "Target OU does not exist: $nonAzureSyncedOU" -Level "ERROR" -LogPath $logPath
            return
        }

        # Create new distribution group in non-synced OU
        $newGroupParams = @{
            Name = $originalGroup.Name
            DisplayName = $originalGroup.DisplayName
            PrimarySmtpAddress = $originalGroup.PrimarySmtpAddress
            Type = "Distribution"
            OrganizationalUnit = $nonAzureSyncedOU
        }
        
        Write-Log -Message "Creating new distribution group..." -Level "INFO" -LogPath $logPath
        $newGroup = New-DistributionGroup @newGroupParams -ErrorAction Stop
        
        # Copy group properties including aliases
        $groupProps = @{
            Identity = $newGroup.Name
            Description = $originalGroup.Description
            HiddenFromAddressListsEnabled = $originalGroup.HiddenFromAddressListsEnabled
            MemberDepartRestriction = $originalGroup.MemberDepartRestriction
            MemberJoinRestriction = $originalGroup.MemberJoinRestriction
        }
        Set-DistributionGroup @groupProps

        # Copy email aliases
        $originalGroup.EmailAddresses | Where-Object {$_ -cne $originalGroup.PrimarySmtpAddress} | ForEach-Object {
            Set-DistributionGroup -Identity $newGroup.Name -EmailAddresses @{add=$_}
        }

        # Set owner (use DefaultOwner if specified, otherwise copy from original)
        if ($DefaultOwner) {
            Set-DistributionGroup -Identity $newGroup.Name -ManagedBy $DefaultOwner
        } elseif ($originalGroup.ManagedBy) {
            Set-DistributionGroup -Identity $newGroup.Name -ManagedBy $originalGroup.ManagedBy
        }
        
        # Add members in batches with throttling and progress
        $memberCount = 0
        $totalMembers = $members.Count
        $activity = "Migrating distribution group members"
        
        for ($i = 0; $i -lt $totalMembers; $i += $batchSize) {
            $batch = $members | Select-Object -Skip $i -First $batchSize
            $batchErrors = @()
            
            foreach ($member in $batch) {
                $percentComplete = [math]::Round(($memberCount / $totalMembers) * 100)
                Write-Progress -Activity $activity -Status "Processing member $memberCount of $totalMembers" -PercentComplete $percentComplete
                
                try {
                    Add-DistributionGroupMember -Identity $newGroup.Name -Member $member.PrimarySmtpAddress -ErrorAction Stop
                    Start-Sleep -Milliseconds $config.DefaultSettings.ThrottleDelayMs
                }
                catch {
                    $batchErrors += "Failed to add member $($member.PrimarySmtpAddress): $_"
                }
                $memberCount++
            }
            
            if ($batchErrors.Count -gt 0) {
                Write-Log -Message "Errors in batch:" -Level "WARNING" -LogPath $logPath
                $batchErrors | ForEach-Object { Write-Log -Message $_ -Level "WARNING" -LogPath $logPath }
                
                if ($batchErrors.Count -gt ($batch.Count * 0.5) -and -not $NoRollback) {
                    Write-Log -Message "Too many errors, initiating rollback..." -Level "ERROR" -LogPath $logPath
                    if (Start-Rollback -GroupName $newGroup.Name -OriginalDetailsFile $originalDetailsFilePath) {
                        Send-MigrationNotification -To $NotificationEmail -GroupName $SourceGroupName -Status "Failed - Rolled Back" -ErrorDetails ($batchErrors -join "`n") -LogPath $logPath
                        return
                    }
                }
            }
            
            Write-Log -Message "Added $memberCount of $totalMembers members..." -Level "INFO" -LogPath $logPath
        }
        
        Write-Progress -Activity $activity -Completed
        
        Write-Log -Message "Migration completed successfully" -Level "INFO" -LogPath $logPath
        
        if ($NotificationEmail -or $config.DefaultSettings.NotificationEmail) {
            $notifyTo = $NotificationEmail ?? $config.DefaultSettings.NotificationEmail
            Send-MigrationNotification -To $notifyTo -GroupName $SourceGroupName -Status "Completed Successfully" -LogPath $logPath
        }
    }
    catch {
        Write-Log -Message "Error during migration: $_" -Level "ERROR" -LogPath $logPath
        return
    }

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

# Helper function to verify required modules
function Test-RequiredModule {
    param([string]$ModuleName)
    
    if (!(Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Log -Message "Required module '$ModuleName' is not installed." -Level "ERROR" -LogPath $logPath
        return $false
    }
    return $true
}

# Main execution
if (-not (Test-RequiredModule "ActiveDirectory")) { exit }
if (-not (Test-RequiredModule "ExchangeOnlineManagement")) { exit }

# Connect to Exchange Online and Active Directory
try {
    Connect-ExchangeOnline -ErrorAction Stop
    Write-Log -Message "Successfully connected to Exchange Online" -Level "INFO" -LogPath $logPath
    
    # Test AD connection
    Get-ADDomain -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to Active Directory" -Level "INFO" -LogPath $logPath
} 
catch {
    Write-Log -Message "Failed to connect to required services: $_" -Level "ERROR" -LogPath $logPath
    exit
}

try {
    Start-DistributionGroupMigration
} catch {
    Write-Log -Message "An unexpected error occurred during migration: $_" -Level "ERROR" -LogPath $logPath
}
