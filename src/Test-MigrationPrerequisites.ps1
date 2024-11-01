[CmdletBinding()]
param()

# Import required modules
Import-Module -Name "$PSScriptRoot\modules\Logging.psm1" -Force

$logPath = Join-Path -Path "." -ChildPath "PrerequisiteCheck-$(Get-Date -Format 'yyyyMMddHHmmss').txt"

# Check for required PowerShell modules
$requiredModules = @(
    "ActiveDirectory",
    "ExchangeOnlineManagement"
)

$allModulesPresent = $true
foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Log -Message "Missing required module: $module" -Level "ERROR" -LogPath $logPath
        $allModulesPresent = $false
    } else {
        Write-Log -Message "Found required module: $module" -Level "INFO" -LogPath $logPath
    }
}

# Check configuration file
$configPath = "$PSScriptRoot\config.json"
if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        Write-Log -Message "Configuration file validated successfully" -Level "INFO" -LogPath $logPath
    } catch {
        Write-Log -Message "Invalid configuration file: $_" -Level "ERROR" -LogPath $logPath
        $allModulesPresent = $false
    }
} else {
    Write-Log -Message "Configuration file not found at: $configPath" -Level "ERROR" -LogPath $logPath
    $allModulesPresent = $false
}

# Test Exchange Online connectivity
try {
    Connect-ExchangeOnline -ErrorAction Stop
    Get-OrganizationConfig -ErrorAction Stop | Out-Null
    Write-Log -Message "Successfully connected to Exchange Online" -Level "INFO" -LogPath $logPath
    Disconnect-ExchangeOnline -Confirm:$false
} catch {
    Write-Log -Message "Failed to connect to Exchange Online: $_" -Level "ERROR" -LogPath $logPath
    $allModulesPresent = $false
}

if ($allModulesPresent) {
    Write-Log -Message "All prerequisites checked successfully" -Level "INFO" -LogPath $logPath
    exit 0
} else {
    Write-Log -Message "Prerequisite check failed - see log for details" -Level "ERROR" -LogPath $logPath
    exit 1
}
