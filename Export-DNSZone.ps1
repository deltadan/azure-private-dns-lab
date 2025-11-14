<#
.SYNOPSIS
    Exports an Active Directory-integrated DNS zone and all its records to a JSON file.

.DESCRIPTION
    This script exports a DNS zone configuration and all DNS records from an AD-integrated zone.
    The export includes zone properties and all resource records which can be reimported later.

.PARAMETER ZoneName
    The name of the DNS zone to export (e.g., "contoso.com")

.PARAMETER ExportPath
    The path where the export file will be saved. Defaults to current directory.

.EXAMPLE
    .\Export-DNSZone.ps1 -ZoneName "contoso.com" -ExportPath "C:\DNSBackups"

.NOTES
    Requires:
    - Run as Administrator
    - Active Directory Domain Services PowerShell module
    - DNS Server PowerShell module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZoneName,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = "."
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
    Write-Error "Failed to load DNS Server module. Please ensure RSAT tools are installed."
    exit 1
}

# Verify the zone exists
try {
    $zone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop
    Write-Host "Found DNS zone: $ZoneName" -ForegroundColor Green
}
catch {
    Write-Error "DNS zone '$ZoneName' not found. Please verify the zone name."
    exit 1
}

# Check if zone is AD-integrated
if ($zone.ZoneType -ne "Primary" -or -not $zone.IsDsIntegrated) {
    Write-Warning "Zone '$ZoneName' is not an Active Directory-integrated primary zone."
    Write-Warning "Zone Type: $($zone.ZoneType), AD-Integrated: $($zone.IsDsIntegrated)"
    $continue = Read-Host "Do you want to continue anyway? (Y/N)"
    if ($continue -ne "Y") {
        exit 0
    }
}

Write-Host "Exporting DNS zone configuration..." -ForegroundColor Cyan

# Export zone configuration
$zoneConfig = @{
    ZoneName            = $zone.ZoneName
    ZoneType            = $zone.ZoneType
    IsDsIntegrated      = $zone.IsDsIntegrated
    DynamicUpdate       = $zone.DynamicUpdate
    ReplicationScope    = $zone.ReplicationScope
    DirectoryPartitionName = $zone.DirectoryPartitionName
    IsAutoCreated       = $zone.IsAutoCreated
    IsPaused            = $zone.IsPaused
    IsReadOnly          = $zone.IsReadOnly
    IsReverseLookupZone = $zone.IsReverseLookupZone
    IsShutdown          = $zone.IsShutdown
    SecureSecondaries   = $zone.SecureSecondaries
    ExportDate          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

Write-Host "Retrieving all DNS records from zone..." -ForegroundColor Cyan

# Get all DNS records
$allRecords = Get-DnsServerResourceRecord -ZoneName $ZoneName

Write-Host "Found $($allRecords.Count) DNS records" -ForegroundColor Green

# Export records with their properties
$exportedRecords = @()
foreach ($record in $allRecords) {
    $recordData = @{
        HostName       = $record.HostName
        RecordType     = $record.RecordType
        TimeToLive     = $record.TimeToLive.TotalSeconds
        Timestamp      = $record.Timestamp
        RecordData     = @{}
    }

    # Export record-specific data based on type
    switch ($record.RecordType) {
        "A" {
            $recordData.RecordData = @{
                IPv4Address = $record.RecordData.IPv4Address.IPAddressToString
            }
        }
        "AAAA" {
            $recordData.RecordData = @{
                IPv6Address = $record.RecordData.IPv6Address.IPAddressToString
            }
        }
        "CNAME" {
            $recordData.RecordData = @{
                HostNameAlias = $record.RecordData.HostNameAlias
            }
        }
        "MX" {
            $recordData.RecordData = @{
                MailExchange = $record.RecordData.MailExchange
                Preference   = $record.RecordData.Preference
            }
        }
        "NS" {
            $recordData.RecordData = @{
                NameServer = $record.RecordData.NameServer
            }
        }
        "PTR" {
            $recordData.RecordData = @{
                PtrDomainName = $record.RecordData.PtrDomainName
            }
        }
        "SRV" {
            $recordData.RecordData = @{
                DomainName = $record.RecordData.DomainName
                Port       = $record.RecordData.Port
                Priority   = $record.RecordData.Priority
                Weight     = $record.RecordData.Weight
            }
        }
        "TXT" {
            $recordData.RecordData = @{
                DescriptiveText = $record.RecordData.DescriptiveText
            }
        }
        "SOA" {
            $recordData.RecordData = @{
                PrimaryServer   = $record.RecordData.PrimaryServer
                ResponsiblePerson = $record.RecordData.ResponsiblePerson
                SerialNumber    = $record.RecordData.SerialNumber
                TimeToZoneRefresh = $record.RecordData.TimeToZoneRefresh
                TimeToZoneFailureRetry = $record.RecordData.TimeToZoneFailureRetry
                TimeToExpiration = $record.RecordData.TimeToExpiration
                MinimumTimeToLive = $record.RecordData.MinimumTimeToLive
            }
        }
        default {
            # For any other record types, attempt to capture available properties
            $recordData.RecordData = @{
                RawData = $record.RecordData | ConvertTo-Json -Depth 10
            }
        }
    }

    $exportedRecords += $recordData
}

# Combine zone config and records
$exportData = @{
    ZoneConfiguration = $zoneConfig
    Records           = $exportedRecords
}

# Create export path if it doesn't exist
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

# Generate export filename
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$exportFileName = "$ZoneName`_$timestamp.json"
$exportFilePath = Join-Path $ExportPath $exportFileName

# Export to JSON
try {
    $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $exportFilePath -Encoding UTF8
    Write-Host "`nExport completed successfully!" -ForegroundColor Green
    Write-Host "Export file: $exportFilePath" -ForegroundColor Cyan
    Write-Host "Zone: $ZoneName" -ForegroundColor Cyan
    Write-Host "Records exported: $($exportedRecords.Count)" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to export DNS zone: $_"
    exit 1
}
