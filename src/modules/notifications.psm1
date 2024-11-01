function Send-MigrationNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$To,
        [Parameter(Mandatory=$true)]
        [string]$GroupName,
        [Parameter(Mandatory=$true)]
        [string]$Status,
        [Parameter(Mandatory=$false)]
        [string]$ErrorDetails,
        [Parameter(Mandatory=$false)]
        [string]$LogPath
    )

    $subject = "Distribution Group Migration Status: $GroupName"
    $body = @"
Migration Status for group '$GroupName': $Status

Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

$(if ($ErrorDetails) {"Error Details: $ErrorDetails"})

$(if (Test-Path $LogPath) {"Full logs are attached."})
"@

    try {
        $params = @{
            To = $To
            Subject = $subject
            Body = $body
            From = "migration-tool@$($config.DefaultSettings.Domain)"
            SmtpServer = $config.DefaultSettings.SmtpServer
        }
        
        if (Test-Path $LogPath) {
            Send-MailMessage @params -Attachments $LogPath
        } else {
            Send-MailMessage @params
        }
    }
    catch {
        Write-Log -Message "Failed to send notification email: $_" -Level "ERROR" -LogPath $LogPath
    }
}

Export-ModuleMember -Function Send-MigrationNotification
