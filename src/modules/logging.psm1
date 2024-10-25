function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "$timestamp [$Level] - $Message"
    
    # Always write to console
    switch ($Level) {
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "INFO"    { Write-Host $logMessage -ForegroundColor Green }
        "DEBUG"   { Write-Host $logMessage -ForegroundColor Gray }
    }
    
    # Write to file if path is specified
    if ($LogPath) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop
        }
        catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }
}

Export-ModuleMember -Function Write-Log
