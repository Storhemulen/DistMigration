function Test-EmailAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$EmailAddress
    )
    
    $emailRegex = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return $EmailAddress -match $emailRegex
}

function Test-GroupName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$GroupName
    )
    
    # Check for invalid characters and length
    $invalidChars = '[<>*%&:\/\\\?\"]'
    if ($GroupName -match $invalidChars) {
        return $false
    }
    
    # Check length (adjust max length as needed)
    if ($GroupName.Length -gt 64 -or $GroupName.Length -lt 1) {
        return $false
    }
    
    return $true
}

function Normalize-GroupName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$GroupName
    )
    
    # Replace special characters
    $normalized = $GroupName -replace 'å', 'a' `
                            -replace 'ä', 'ae' `
                            -replace 'ö', 'o' `
                            -replace 'Å', 'A' `
                            -replace 'Ä', 'Ae' `
                            -replace 'Ö', 'O'
                            
    # Remove any remaining invalid characters
    $normalized = $normalized -replace '[^a-zA-Z0-9._-]', ''
    
    return $normalized
}

Export-ModuleMember -Function Test-EmailAddress, Test-GroupName, Normalize-GroupName
