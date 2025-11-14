<#
.SYNOPSIS
    Imports an Active Directory-integrated DNS zone and all its records from a JSON export file.

.DESCRIPTION
    This script imports a DNS zone configuration and all DNS records that were previously exported.
    It will create the AD-integrated zone and recreate all resource records.

.PARAMETER ImportFilePath
    The path to the JSON export file created by Export-DNSZone.ps1

.PARAMETER Force
    If specified, will remove existing zone with the same name before importing

.PARAMETER SkipSOA
    If specified, will skip importing SOA records (useful if zone auto-creates SOA)

.EXAMPLE
    .\Import-DNSZone.ps1 -ImportFilePath "C:\DNSBackups\contoso.com_20250114_120000.json"

.EXAMPLE
    .\Import-DNSZone.ps1 -ImportFilePath "C:\DNSBackups\contoso.com_20250114_120000.json" -Force

.NOTES
    Requires:
    - Run as Administrator
    - Active Directory Domain Services PowerShell module
    - DNS Server PowerShell module
    - Must be run on a domain controller or server with DNS role
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImportFilePath,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSOA
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

# Verify import file exists
if (-not (Test-Path $ImportFilePath)) {
    Write-Error "Import file not found: $ImportFilePath"
    exit 1
}

# Load the export data
try {
    $importData = Get-Content -Path $ImportFilePath -Raw | ConvertFrom-Json
    Write-Host "Import file loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load import file: $_"
    exit 1
}

$zoneConfig = $importData.ZoneConfiguration
$records = $importData.Records

Write-Host "`nZone to import: $($zoneConfig.ZoneName)" -ForegroundColor Cyan
Write-Host "Records to import: $($records.Count)" -ForegroundColor Cyan
Write-Host "Original export date: $($zoneConfig.ExportDate)" -ForegroundColor Cyan

# Check if zone already exists
$existingZone = Get-DnsServerZone -Name $zoneConfig.ZoneName -ErrorAction SilentlyContinue

if ($existingZone) {
    if ($Force) {
        Write-Warning "Zone '$($zoneConfig.ZoneName)' already exists. Removing due to -Force parameter..."
        Remove-DnsServerZone -Name $zoneConfig.ZoneName -Force -ErrorAction Stop
        Write-Host "Existing zone removed" -ForegroundColor Yellow
    }
    else {
        Write-Error "Zone '$($zoneConfig.ZoneName)' already exists. Use -Force to overwrite."
        exit 1
    }
}

# Create the DNS zone
Write-Host "`nCreating DNS zone..." -ForegroundColor Cyan

try {
    if ($zoneConfig.IsDsIntegrated) {
        # Create AD-integrated zone
        $zoneParams = @{
            Name              = $zoneConfig.ZoneName
            ReplicationScope  = $zoneConfig.ReplicationScope
            DynamicUpdate     = $zoneConfig.DynamicUpdate
        }

        # Only add DirectoryPartitionName if ReplicationScope is Custom
        if ($zoneConfig.ReplicationScope -eq "Custom" -and $zoneConfig.DirectoryPartitionName) {
            $zoneParams.DirectoryPartitionName = $zoneConfig.DirectoryPartitionName
        }

        Add-DnsServerPrimaryZone @zoneParams -ErrorAction Stop
        Write-Host "AD-integrated DNS zone created successfully" -ForegroundColor Green
    }
    else {
        # Create standard primary zone (non-AD integrated)
        Add-DnsServerPrimaryZone -Name $zoneConfig.ZoneName -DynamicUpdate $zoneConfig.DynamicUpdate -ErrorAction Stop
        Write-Host "Standard primary DNS zone created successfully" -ForegroundColor Green
    }
}
catch {
    Write-Error "Failed to create DNS zone: $_"
    exit 1
}

# Import DNS records
Write-Host "`nImporting DNS records..." -ForegroundColor Cyan

$successCount = 0
$skipCount = 0
$errorCount = 0
$importErrors = @()

foreach ($record in $records) {
    # Skip SOA and default NS records if requested (they're auto-created)
    if ($SkipSOA -and $record.RecordType -eq "SOA") {
        Write-Verbose "Skipping SOA record (auto-created by zone)"
        $skipCount++
        continue
    }

    # Skip root NS records (auto-created)
    if ($record.RecordType -eq "NS" -and $record.HostName -eq "@") {
        Write-Verbose "Skipping root NS record (auto-created by zone)"
        $skipCount++
        continue
    }

    try {
        $ttl = New-TimeSpan -Seconds $record.TimeToLive

        # Create record based on type
        switch ($record.RecordType) {
            "A" {
                Add-DnsServerResourceRecordA -ZoneName $zoneConfig.ZoneName `
                    -Name $record.HostName `
                    -IPv4Address $record.RecordData.IPv4Address `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "AAAA" {
                Add-DnsServerResourceRecordAAAA -ZoneName $zoneConfig.ZoneName `
                    -Name $record.HostName `
                    -IPv6Address $record.RecordData.IPv6Address `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "CNAME" {
                Add-DnsServerResourceRecordCName -ZoneName $zoneConfig.ZoneName `
                    -Name $record.HostName `
                    -HostNameAlias $record.RecordData.HostNameAlias `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "MX" {
                Add-DnsServerResourceRecordMX -ZoneName $zoneConfig.ZoneName `
                    -Name $record.HostName `
                    -MailExchange $record.RecordData.MailExchange `
                    -Preference $record.RecordData.Preference `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "NS" {
                Add-DnsServerResourceRecord -ZoneName $zoneConfig.ZoneName `
                    -NS -Name $record.HostName `
                    -NameServer $record.RecordData.NameServer `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "PTR" {
                Add-DnsServerResourceRecordPtr -ZoneName $zoneConfig.ZoneName `
                    -Name $record.HostName `
                    -PtrDomainName $record.RecordData.PtrDomainName `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "SRV" {
                Add-DnsServerResourceRecord -ZoneName $zoneConfig.ZoneName `
                    -Srv -Name $record.HostName `
                    -DomainName $record.RecordData.DomainName `
                    -Port $record.RecordData.Port `
                    -Priority $record.RecordData.Priority `
                    -Weight $record.RecordData.Weight `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "TXT" {
                Add-DnsServerResourceRecord -ZoneName $zoneConfig.ZoneName `
                    -Txt -Name $record.HostName `
                    -DescriptiveText $record.RecordData.DescriptiveText `
                    -TimeToLive $ttl `
                    -ErrorAction Stop
            }
            "SOA" {
                # SOA records are auto-created with the zone and cannot be added manually
                # We'll skip them by default as they're automatically generated
                Write-Verbose "Skipping SOA record (auto-created by zone)"
                $skipCount++
                continue
            }
            default {
                Write-Warning "Unsupported record type: $($record.RecordType) for $($record.HostName)"
                $skipCount++
                continue
            }
        }

        $successCount++
        Write-Verbose "Imported: $($record.RecordType) - $($record.HostName)"
    }
    catch {
        $errorCount++
        $errorMsg = "Failed to import $($record.RecordType) record '$($record.HostName)': $_"
        $importErrors += $errorMsg
        Write-Warning $errorMsg
    }
}

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Import Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Zone Name: $($zoneConfig.ZoneName)" -ForegroundColor White
Write-Host "Total Records: $($records.Count)" -ForegroundColor White
Write-Host "Successfully Imported: $successCount" -ForegroundColor Green
Write-Host "Skipped: $skipCount" -ForegroundColor Yellow
Write-Host "Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })

if ($errorCount -gt 0) {
    Write-Host "`nErrors encountered:" -ForegroundColor Red
    foreach ($err in $importErrors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
}

Write-Host "`nImport completed!" -ForegroundColor Green
