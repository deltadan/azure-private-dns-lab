<#
.SYNOPSIS
    Creates a conditional forwarder on a DNS server.

.DESCRIPTION
    This script creates a conditional forwarder for a specified domain name, directing queries
    to one or more target DNS servers. Supports both AD-integrated and standard forwarders.

.PARAMETER DomainName
    The domain name for which to create the conditional forwarder (e.g., "contoso.com")

.PARAMETER ForwarderIPAddress
    The IP address(es) of the DNS server(s) to forward queries to. Can be a single IP or an array of IPs.

.PARAMETER ADIntegrated
    If specified, creates an AD-integrated conditional forwarder (default: false)

.PARAMETER ReplicationScope
    Specifies the replication scope for AD-integrated forwarders.
    Valid values: "Forest", "Domain", "Legacy", "Custom"
    Default: "Domain"

.PARAMETER DirectoryPartitionName
    The directory partition name (only used when ReplicationScope is "Custom")

.PARAMETER Force
    If specified, will replace an existing conditional forwarder with the same name

.EXAMPLE
    .\New-DNSConditionalForwarder.ps1 -DomainName "contoso.com" -ForwarderIPAddress "10.0.0.10"

.EXAMPLE
    .\New-DNSConditionalForwarder.ps1 -DomainName "fabrikam.com" -ForwarderIPAddress "10.0.0.10","10.0.0.11"

.EXAMPLE
    .\New-DNSConditionalForwarder.ps1 -DomainName "external.com" -ForwarderIPAddress "8.8.8.8" -ADIntegrated -ReplicationScope Forest

.EXAMPLE
    .\New-DNSConditionalForwarder.ps1 -DomainName "partner.com" -ForwarderIPAddress "192.168.1.10" -Force

.NOTES
    Requires:
    - Run as Administrator
    - DNS Server PowerShell module
    - Must be run on a DNS server
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The domain name for the conditional forwarder")]
    [ValidateNotNullOrEmpty()]
    [string]$DomainName,

    [Parameter(Mandatory = $false, HelpMessage = "IP address(es) of the DNS server(s) to forward to")]
    [ValidateNotNullOrEmpty()]
    [string[]]$ForwarderIPAddress = @("168.63.129.16"),

    [Parameter(Mandatory = $false)]
    [bool]$ADIntegrated = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Forest", "Domain", "Legacy", "Custom")]
    [string]$ReplicationScope = "Domain",

    [Parameter(Mandatory = $false)]
    [string]$DirectoryPartitionName,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Import required modules
try {
    Import-Module DnsServer -ErrorAction Stop
    Write-Host "DNS Server module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load DNS Server module. Please ensure DNS Server role and RSAT tools are installed."
    exit 1
}

# Validate IP addresses
Write-Host "`nValidating IP addresses..." -ForegroundColor Cyan
foreach ($ip in $ForwarderIPAddress) {
    try {
        $null = [System.Net.IPAddress]::Parse($ip)
        Write-Host "  Valid IP: $ip" -ForegroundColor Green
    }
    catch {
        Write-Error "Invalid IP address format: $ip"
        exit 1
    }
}

# Normalize domain name (remove trailing dot if present)
$DomainName = $DomainName.TrimEnd('.')

# Check if conditional forwarder already exists
Write-Host "`nChecking for existing conditional forwarder..." -ForegroundColor Cyan
$existingForwarder = Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue

if ($existingForwarder) {
    if ($existingForwarder.ZoneType -eq "Forwarder") {
        Write-Warning "Conditional forwarder for '$DomainName' already exists"

        # Show current configuration
        $currentMasters = (Get-DnsServerZone -Name $DomainName).MasterServers.IPAddressToString
        Write-Host "Current forwarders: $($currentMasters -join ', ')" -ForegroundColor Yellow

        if ($Force) {
            Write-Host "Removing existing conditional forwarder due to -Force parameter..." -ForegroundColor Yellow
            Remove-DnsServerZone -Name $DomainName -Force -ErrorAction Stop
            Write-Host "Existing conditional forwarder removed" -ForegroundColor Yellow
        }
        else {
            Write-Error "Use -Force to replace the existing conditional forwarder"
            exit 1
        }
    }
    else {
        Write-Error "A zone named '$DomainName' already exists but is not a conditional forwarder (Type: $($existingForwarder.ZoneType))"
        exit 1
    }
}

# Create the conditional forwarder
Write-Host "`nCreating conditional forwarder for '$DomainName'..." -ForegroundColor Cyan
Write-Host "Forwarder IP(s): $($ForwarderIPAddress -join ', ')" -ForegroundColor Cyan

try {
    if ($ADIntegrated) {
        # Create AD-integrated conditional forwarder
        Write-Host "Type: AD-Integrated" -ForegroundColor Cyan
        Write-Host "Replication Scope: $ReplicationScope" -ForegroundColor Cyan

        $params = @{
            Name             = $DomainName
            MasterServers    = $ForwarderIPAddress
            ReplicationScope = $ReplicationScope
            ErrorAction      = 'Stop'
        }

        # Add DirectoryPartitionName only if ReplicationScope is Custom
        if ($ReplicationScope -eq "Custom") {
            if ([string]::IsNullOrWhiteSpace($DirectoryPartitionName)) {
                Write-Error "DirectoryPartitionName is required when ReplicationScope is 'Custom'"
                exit 1
            }
            $params.DirectoryPartitionName = $DirectoryPartitionName
            Write-Host "Directory Partition: $DirectoryPartitionName" -ForegroundColor Cyan
        }

        Add-DnsServerConditionalForwarderZone @params
        Write-Host "`nAD-integrated conditional forwarder created successfully!" -ForegroundColor Green
    }
    else {
        # Create standard (non-AD-integrated) conditional forwarder
        Write-Host "Type: Standard (not AD-integrated)" -ForegroundColor Cyan

        Add-DnsServerConditionalForwarderZone -Name $DomainName `
            -MasterServers $ForwarderIPAddress `
            -ErrorAction Stop

        Write-Host "`nConditional forwarder created successfully!" -ForegroundColor Green
    }

    # Verify the forwarder was created
    Start-Sleep -Milliseconds 500
    $newForwarder = Get-DnsServerZone -Name $DomainName -ErrorAction SilentlyContinue

    if ($newForwarder) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Conditional Forwarder Details" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Domain Name: $($newForwarder.ZoneName)" -ForegroundColor White
        Write-Host "Zone Type: $($newForwarder.ZoneType)" -ForegroundColor White
        Write-Host "AD-Integrated: $($newForwarder.IsDsIntegrated)" -ForegroundColor White

        if ($newForwarder.IsDsIntegrated) {
            Write-Host "Replication Scope: $($newForwarder.ReplicationScope)" -ForegroundColor White
            if ($newForwarder.DirectoryPartitionName) {
                Write-Host "Directory Partition: $($newForwarder.DirectoryPartitionName)" -ForegroundColor White
            }
        }

        $masters = (Get-DnsServerZone -Name $DomainName).MasterServers.IPAddressToString
        Write-Host "Forwarder Server(s): $($masters -join ', ')" -ForegroundColor White

        # Test the forwarder
        Write-Host "`nTesting conditional forwarder..." -ForegroundColor Cyan
        try {
            $testResult = Resolve-DnsName -Name $DomainName -Server localhost -ErrorAction Stop
            Write-Host "Test Result: SUCCESS" -ForegroundColor Green
        }
        catch {
            Write-Warning "Test query did not return results. This may be normal if the forwarded domain has no records or is unreachable."
            Write-Host "Test Result: No response (this may be expected)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Warning "Conditional forwarder was created but could not be verified"
    }
}
catch {
    Write-Error "Failed to create conditional forwarder: $_"
    exit 1
}

Write-Host "`nOperation completed successfully!" -ForegroundColor Green
