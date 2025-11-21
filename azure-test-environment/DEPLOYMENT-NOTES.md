# Deployment Notes

## Simplified Configuration

This deployment has been optimized for lab/testing purposes with several key design decisions.

## Domain Controller Configuration

**VM Specification:**
- **OS**: Windows Server 2022 Datacenter
- **Size**: Standard_D2s_v3 (2 vCPUs, 8 GB RAM)
- **OS Disk**: 128 GB Premium SSD
- **Data Disks**: None (simplified for lab)
- **Network**: Static IP 10.0.1.4
- **Security**: RDP restricted to 47.199.28.203

**Active Directory Setup:**
- Uses **Custom Script Extension** (not DSC) for maximum reliability
- Single inline PowerShell command installs AD DS and promotes to DC
- All AD databases stored on OS disk (acceptable for lab/test)
- Automatic restart after promotion
- No external dependencies or downloads required

**Installation Command:**
```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Install-ADDSForest `
  -DomainName contoso.local `
  -SafeModeAdministratorPassword (SecureString) `
  -InstallDns `
  -Force
# Automatic restart
```

**Why Custom Script Extension vs DSC?**
- ✅ **More reliable** - No external zip file dependencies
- ✅ **Simpler** - Single inline PowerShell command
- ✅ **Faster** - No DSC module downloads or configuration compilation
- ✅ **Easier to debug** - Logs at `C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension`
- ✅ **No GitHub dependencies** - Previous approach relied on external DSC zip file

## Storage Configuration

**Storage Account:**
- Standard LRS (cheapest for testing)
- Public network access disabled
- Private endpoint in dedicated subnet
- Blob service only

**Private DNS:**
- Azure-managed Private DNS Zone: `privatelink.blob.core.windows.net`
- Automatically linked to VNet
- DNS records auto-created for private endpoint
- Integrated with VNet DNS configuration

## Network Configuration

**Hub-Spoke Topology:**
- **Hub VNet**: 10.0.0.0/16 (shared services)
  - DNS servers: 10.0.1.4 (Domain Controller)
  - Contains: DC, Bastion, DNS Resolver
- **Spoke VNet**: 10.1.0.0/16 (workloads)
  - DNS servers: DNS Resolver Inbound Endpoint
  - Contains: Windows 11 Client, Storage with Private Endpoint
- **VNet Peering**: Bidirectional with allowForwardedTraffic enabled

**DNS Flow:**
1. Spoke VNet DNS points to DNS Resolver Inbound Endpoint
2. DNS Resolver receives queries from spoke
3. DNS Resolver Outbound forwards contoso.local queries to DC (10.0.1.4)
4. DC resolves contoso.local (AD-integrated)
5. DC can forward other queries to Azure DNS (168.63.129.16) via conditional forwarders
6. Azure DNS resolves private endpoint IPs
7. Storage accessed via private IP (10.1.2.x in spoke VNet)

**Network Security:**
- DC NSG: RDP restricted to single IP (parameterized), DNS and AD ports open to VNet
- Client NSG: RDP allowed from VirtualNetwork
- Bastion provides secure access to both hub and spoke VMs

## Password Generation

**Auto-Generated Password:**
- 16 characters long
- Includes: uppercase, lowercase, digits, special characters
- Excludes ambiguous characters (I, O, l, 0, 1) for clarity
- Displayed prominently during deployment
- Saved to connection-info.txt

**Generation Algorithm:**
```powershell
# Ensure at least one of each type
$password = @(
    $uppercase[random]  # A-Z (excluding I, O)
    $lowercase[random]  # a-z (excluding l)
    $digits[random]     # 2-9 (excluding 0, 1)
    $special[random]    # !@#$%^&*
)
# Add 12 more random characters
# Shuffle the result
```

**Why Auto-Generate?**
- ✅ Eliminates password complexity validation errors
- ✅ Guaranteed to meet Azure requirements
- ✅ Simpler user experience
- ✅ No need to remember complex rules

## Deployment Script (Azure CLI)

**Technology Choice:**
- Uses **Azure CLI** (az) instead of Az PowerShell modules
- Cross-platform compatible (Windows, macOS, Linux)
- No PowerShell module installation required
- JSON output parsing for deployment results

**Key Features:**
1. **Auto password generation** with prominent display
2. **Azure CLI validation** - checks if az is installed
3. **Login check** - verifies Azure authentication
4. **Password validation** - only for user-provided passwords
5. **Extension monitoring** - waits for DC promotion to complete
6. **VNet DNS verification** - ensures DNS is configured correctly
7. **Connection info export** - saves all details to text file

**Deployment Flow:**
```
1. Check Azure CLI installed
2. Generate/validate password
3. Check Azure login
4. Create/verify resource group
5. Deploy Bicep template
   ├─ VNet with DNS
   ├─ NSG with rules
   ├─ DC VM
   ├─ Custom Script Extension
   ├─ Storage Account
   ├─ Private Endpoint
   └─ Private DNS Zone
6. Monitor extension status (every 60s)
7. Verify VNet DNS configuration
8. Display connection info
9. Save to connection-info.txt
```

## Design Decisions

### Hub-Spoke Network Topology

**Why Hub-Spoke?**
- ✅ **Realistic architecture** - Mirrors production patterns
- ✅ **Service isolation** - Shared services (DC, Bastion, DNS Resolver) in hub
- ✅ **Workload isolation** - Applications and data in spoke
- ✅ **Scalability** - Easy to add more spoke VNets
- ✅ **Cost optimization** - Single Bastion and DNS Resolver serve multiple spokes
- ✅ **DNS testing** - Perfect for testing DNS Resolver with hybrid scenarios

**Hub VNet Components:**
- Domain Controller (10.0.1.4)
- Azure Bastion (secure access)
- DNS Private Resolver (inbound + outbound endpoints)
- All shared infrastructure services

**Spoke VNet Components:**
- Windows 11 Client VM (domain member)
- Storage Account with Private Endpoint
- Workload resources

**Why DNS Resolver in Hub?**
- Centralizes DNS forwarding logic
- Spoke VNets use Inbound Endpoint as DNS server
- Outbound Endpoint forwards domain queries to DC
- Enables on-premises to query Azure DNS via Inbound Endpoint
- Realistic hybrid DNS architecture

### Single Disk Design

✅ **Simpler** - No disk initialization or formatting needed
✅ **Faster** - One less disk to provision and configure
✅ **Cheaper** - Saves ~$20/month for data disk
✅ **Sufficient** - 128GB OS disk has plenty of space for lab AD

**Lab vs Production:**
| Aspect | Lab (This) | Production |
|--------|-----------|------------|
| AD Database | C:\Windows\NTDS | Separate data disk (F:\NTDS) |
| Disk Size | 128GB OS | 127GB OS + 32GB+ data |
| Reason | Simplicity | Performance & backup isolation |

### No DSC Configuration

Removed complex DSC configuration in favor of simple Custom Script Extension:

**Old Approach (DSC):**
- Required external zip file from GitHub
- Complex configuration compilation
- Module downloads
- Harder to debug
- External dependency risk

**New Approach (Custom Script Extension):**
- Single inline PowerShell command
- No external dependencies
- Faster execution
- Easier troubleshooting
- More reliable

### Restricted RDP Access

**Default**: RDP only from 47.199.28.203

**Why?**
- ✅ Security best practice
- ✅ Reduces attack surface
- ✅ Still convenient for authorized users

**How to Change:**
Update [main.bicep](main.bicep#L73) line 73:
```bicep
sourceAddressPrefix: 'YOUR.IP.ADDRESS'
```

Or update via CLI after deployment:
```bash
az network nsg rule update \
  --resource-group rg-dnstest \
  --nsg-name dnstest-dc-nsg \
  --name AllowRDP \
  --source-address-prefixes YOUR.IP.ADDRESS
```

### VNet DNS Pre-Configured

**Configured in Bicep:**
```bicep
dhcpOptions: {
  dnsServers: [
    '10.0.1.4' // Domain Controller IP
  ]
}
```

**Why?**
- ✅ Resources can resolve via DC immediately
- ✅ No manual DNS configuration needed
- ✅ Private DNS works from deployment
- ✅ Deployment script still verifies it as safety check

## Deployment Timeline

| Phase | Duration | What's Happening |
|-------|----------|------------------|
| **Infrastructure** | 3-5 min | VNet, NSG, VM, Storage, Private Endpoint |
| **VM Boot** | 2-3 min | Windows Server startup |
| **Extension Start** | 1-2 min | Custom Script Extension initialization |
| **AD Installation** | 3-5 min | Install AD DS role and tools |
| **DC Promotion** | 4-6 min | Promote to domain controller, create forest |
| **Reboot** | 2-3 min | Automatic restart after promotion |
| **DNS Config** | 1 min | VNet DNS verification |
| **Total** | **15-25 min** | End-to-end deployment |

## Cost Breakdown (East US)

| Resource | Daily Cost | Monthly Cost | Notes |
|----------|-----------|--------------|-------|
| **DC VM (D2s_v3)** | ~$2.30 | ~$70 | 2 vCPUs, 8 GB RAM (Hub) |
| **Client VM (B2s)** | ~$1.00 | ~$30 | 2 vCPUs, 4 GB RAM (Spoke) |
| **DC OS Disk (128GB Premium)** | ~$0.65 | ~$20 | Premium SSD (Hub) |
| **Client OS Disk (128GB Standard SSD)** | ~$0.33 | ~$10 | Standard SSD (Spoke) |
| **Bastion (Standard)** | ~$4.60 | ~$140 | Secure access to both VNets |
| **DNS Private Resolver** | ~$0.31 | ~$10 | Inbound + Outbound endpoints |
| **Storage Account** | ~$0.05 | ~$1.50 | Standard LRS (Spoke) |
| **Private Endpoint** | ~$0.03 | ~$1 | Private Link (Spoke) |
| **VNet Peering** | Minimal | ~$1 | Data transfer charges |
| **VNet/NSG** | Free | Free | No charge |
| **Private DNS Zone** | Free | Free | No charge |
| **Total** | **~$9.30/day** | **~$283/month** | If left running |

💰 **Remember to delete after testing!** Bastion is the largest cost component.

## Post-Deployment Validation

**Automatic Checks:**
1. ✅ Bicep deployment succeeds
2. ✅ Custom Script Extension succeeds
3. ✅ VNet DNS configured to 10.0.1.4

**Manual Validation:**

RDP to DC and verify:

```powershell
# AD DS and DNS services running
Get-Service ADWS,DNS

# Domain exists
Get-ADDomain

# DC operational
dcdiag /v

# DNS zones present
Get-DnsServerZone

# VNet DNS correct
ipconfig /all  # Should show 10.0.1.4 as DNS

# Test private DNS resolution
$storage = "<storage-account-name>"
Resolve-DnsName "$storage.blob.core.windows.net"
# Should return private IP (10.0.2.x)
```

## Troubleshooting Quick Reference

### Extension Failed

**Check logs:**
```
C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\
```

**View status:**
```bash
az vm get-instance-view \
  --resource-group rg-dnstest \
  --name dnstest-dc \
  --query instanceView.extensions
```

### DNS Not Working

**Verify VNet DNS:**
```bash
az network vnet show \
  --resource-group rg-dnstest \
  --name dnstest-vnet \
  --query dhcpOptions.dnsServers
```

**Check DC DNS:**
```powershell
# On DC
Get-DnsServerZone
Get-DnsServerForwarder
nslookup test.com  # Should work
```

### Can't RDP

**Issue**: IP not allowed

**Fix**: Update NSG rule with your IP
```bash
az network nsg rule update \
  --resource-group rg-dnstest \
  --nsg-name dnstest-dc-nsg \
  --name AllowRDP \
  --source-address-prefixes $(curl -s https://api.ipify.org)
```

### Password Rejected

**Issue**: Provided password doesn't meet requirements

**Fix**: Let script generate one automatically (don't provide -AdminPassword)

## Testing Scenarios

### Scenario 1: Hub-Spoke DNS Resolution
```powershell
# On Client VM (Spoke VNet) - Test domain resolution
Resolve-DnsName "dc01.contoso.local"
# Should return: 10.0.1.4 (via DNS Resolver -> DC)

# Verify DNS configuration
ipconfig /all
# Should show DNS Resolver Inbound Endpoint IP

# Test connectivity to DC
Test-NetConnection 10.0.1.4 -Port 53
# Should succeed (DNS port across peering)
```

### Scenario 2: Private DNS Resolution from Spoke
```powershell
# On Client VM - Get storage account name from deployment
$storage = "<from-connection-info.txt>"

# Test resolution of private endpoint
Resolve-DnsName "$storage.blob.core.windows.net"
# Should return:
# - Name: storage.blob.core.windows.net
# - Type: A
# - IP: 10.1.2.x (private endpoint IP in spoke VNet)

# Compare with public DNS
Resolve-DnsName "$storage.blob.core.windows.net" -Server 8.8.8.8
# Would return public IP (but connection would fail due to firewall)
```

### Scenario 3: Conditional Forwarder (on DC)
```powershell
# On DC - Create forwarder to Azure DNS
.\New-DNSConditionalForwarder.ps1 -DomainName "privatelink.blob.core.windows.net"

# Verify it exists
Get-DnsServerZone | Where-Object ZoneType -eq "Forwarder"

# Test resolution from DC
nslookup "$storage.blob.core.windows.net"
```

### Scenario 4: Zone Export/Import (on DC)
```powershell
# On DC - Export domain zone
.\Export-DNSZone.ps1 -ZoneName "contoso.local" -ExportPath "C:\Backup"

# Create test zone with records
Add-DnsServerPrimaryZone -Name "test.local" -ReplicationScope Domain
Add-DnsServerResourceRecordA -ZoneName "test.local" -Name "web" -IPv4Address "10.1.1.100"

# Export test zone
.\Export-DNSZone.ps1 -ZoneName "test.local" -ExportPath "C:\Backup"

# Delete and restore
Remove-DnsServerZone -Name "test.local" -Force
.\Import-DNSZone.ps1 -ImportFilePath "C:\Backup\test.local_<timestamp>.json"

# Verify from Client VM
Resolve-DnsName "web.test.local"
# Should return: 10.1.1.100 (proves DNS works across hub-spoke)
```

### Scenario 5: VNet Peering Validation
```powershell
# On Client VM - Test connectivity to hub resources
Test-NetConnection 10.0.1.4 -Port 389  # AD LDAP
Test-NetConnection 10.0.1.4 -Port 53   # DNS

# Ping DC
ping 10.0.1.4

# Verify peering status via Azure CLI
az network vnet peering list --resource-group rg-dnstest --vnet-name dnstest-spoke-vnet
```

## Files Created

| File | When | Purpose |
|------|------|---------|
| `main.bicep` | Pre-deployment | Infrastructure template |
| `main.parameters.json` | Pre-deployment | Sample parameters |
| `Deploy-TestEnvironment.ps1` | Pre-deployment | Orchestration script |
| `README.md` | Pre-deployment | User documentation |
| `DEPLOYMENT-NOTES.md` | Pre-deployment | This file - technical details |
| `connection-info.txt` | Post-deployment | RDP details, IPs, passwords |

## What Was Removed/Changed

Compared to initial single-VNet design:

**Removed:**
- ❌ DSC configuration file (ConfigureADDC.ps1)
- ❌ External DSC zip dependency
- ❌ Data disk (F:) for AD database
- ❌ Az PowerShell module requirement
- ❌ Manual password entry/validation prompts
- ❌ Single VNet design

**Added:**
- ✅ Hub-spoke network topology
- ✅ Windows 11 Client VM in spoke VNet
- ✅ VNet peering (bidirectional)
- ✅ Azure DNS Private Resolver with inbound/outbound endpoints
- ✅ DNS forwarding ruleset to DC
- ✅ Custom Script Extension (inline)
- ✅ Auto password generation
- ✅ Azure CLI support
- ✅ Pre-configured VNet DNS
- ✅ Restricted NSG rules (parameterized)
- ✅ Enhanced deployment monitoring
- ✅ Azure Bastion (moved from simple public IP)

**Changed:**
- 🔄 Network: Single VNet → Hub-spoke with peering
- 🔄 Storage location: Hub VNet → Spoke VNet
- 🔄 DNS architecture: VNet → DC → Hub VNet DNS + Spoke via DNS Resolver
- 🔄 Windows Server: 2022 → 2016
- 🔄 OS disk size: 127GB → 128GB
- 🔄 DNS location: Data disk → OS disk (defaults)
- 🔄 Extension type: DSC → Custom Script
- 🔄 Deployment tool: Az PowerShell → Azure CLI
- 🔄 Password: Manual → Auto-generated
- 🔄 RDP: Open → IP-restricted (parameterized)
- 🔄 Remote access: Public IP → Azure Bastion

## Production Recommendations

If adapting this for production:

1. **Separate Data Disk** for AD database
2. **Azure Bastion** instead of public IP + RDP
3. **Multiple DCs** for high availability
4. **Site-to-Site VPN** or ExpressRoute
5. **Azure Backup** for VMs and AD
6. **Azure Monitor** for alerting
7. **Zone-redundant** storage
8. **Network Watcher** for diagnostics
9. **Update Management** for patching
10. **Key Vault** for secrets management

## Summary

This deployment prioritizes:
- ✅ **Hub-Spoke Architecture** - Realistic production pattern
- ✅ **DNS Testing** - Complete hybrid DNS scenario with DNS Resolver
- ✅ **Network Isolation** - Shared services in hub, workloads in spoke
- ✅ **Reliability** - No external dependencies
- ✅ **Speed** - Fast deployment (15-25 min)
- ✅ **Security** - Bastion access, restricted NSG, private endpoints
- ✅ **Hybrid DNS** - Tests on-premises integration scenarios
- ✅ **Scalability** - Easy to add more spoke VNets

Lab characteristics:
- 💡 **Cost**: ~$9/day (~$283/month) - higher than single VNet due to Bastion and DNS Resolver
- 💡 **Complexity**: Hub-spoke topology with VNet peering
- 💡 **VMs**: Domain Controller (hub) + Windows 11 Client (spoke)
- 💡 **DNS Flow**: Spoke → DNS Resolver Inbound → DNS Resolver Outbound → DC

Not intended for:
- ❌ Production workloads without hardening
- ❌ High availability requirements
- ❌ Long-term operation (cost)
- ❌ Compliance-sensitive environments
- ❌ Large-scale multi-spoke deployments

**Perfect for**:
- Testing DNS scripts with Azure Private Link integration
- Understanding hub-spoke network patterns
- Testing DNS Resolver in hybrid scenarios
- Validating AD-integrated DNS with Azure Private DNS
- Learning VNet peering and network segmentation

---

**Next**: See [README.md](README.md) for deployment instructions and usage examples.
