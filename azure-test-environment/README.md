# Azure DNS Test Environment

This directory contains Bicep templates and PowerShell scripts to deploy a complete Azure test environment for testing DNS configurations with Private Link.

## What Gets Deployed

### Hub-Spoke Network Architecture

This lab uses a **hub-and-spoke topology** with two VNets connected via peering:

#### Hub VNet (10.0.0.0/16) - Shared Services
- **Domain Controller subnet (10.0.1.0/24)** with:
  - Windows Server 2016 Domain Controller
  - Active Directory Domain Services auto-configured via Custom Script Extension
  - DNS Server role with AD integration
  - Static IP: 10.0.1.4
  - No public IP (access via Azure Bastion)
  - 128GB OS disk (no data disk - simplified for lab)
- **Azure Bastion subnet (10.0.3.0/26)**:
  - Secure RDP/SSH access without public IPs
  - Standard SKU with public IP
  - Provides access to VMs in both hub and spoke VNets
- **DNS Resolver Inbound subnet (10.0.4.0/28)**:
  - For on-premises DNS forwarding to Azure
  - Enables hybrid DNS resolution scenarios
- **DNS Resolver Outbound subnet (10.0.5.0/28)**:
  - Forwards domain queries to Domain Controller
  - Linked to spoke VNet via forwarding ruleset

#### Spoke VNet (10.1.0.0/16) - Workload Resources
- **Client subnet (10.1.1.0/24)** with:
  - Windows 11 Pro client machine (CLIENT01)
  - Standard_B2s VM size
  - Domain member
  - Dynamic IP assignment
- **Private Endpoint subnet (10.1.2.0/24)** with:
  - Storage account private endpoint
  - Public network access disabled on storage
  - Standard LRS (cost-optimized for testing)
- **Private DNS Zone**: `privatelink.blob.core.windows.net`
  - Linked to the spoke VNet
  - Automatically integrated with storage private endpoint

#### Network Connectivity
- **VNet Peering**: Bidirectional peering between hub and spoke
  - `allowForwardedTraffic: true` for DNS resolution
  - `allowVirtualNetworkAccess: true` for VM communication
- **Network Security Groups**:
  - DC NSG: DNS and AD ports open for VNet traffic
  - Client NSG: RDP allowed from VirtualNetwork

#### DNS Flow
1. **Spoke VNet DNS**: Points to DNS Resolver Inbound Endpoint
2. **DNS Resolver Outbound**: Forwards `contoso.local` queries to DC (10.0.1.4)
3. **Hub VNet DNS**: Points directly to DC (10.0.1.4)
4. **On-premises**: Can forward to DNS Resolver Inbound Endpoint

## Prerequisites

- **Azure CLI** (not Az PowerShell modules)
  ```bash
  # Windows
  https://aka.ms/installazurecliwindows

  # macOS
  brew install azure-cli

  # Linux
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  ```
- Azure subscription with Contributor or Owner role
- Approximately 30-40 minutes for deployment

## Deployment

### Quick Start (Auto-Generated Password)

```powershell
cd azure-test-environment
.\Deploy-TestEnvironment.ps1 -ResourceGroupName "rg-dnstest" -Location "eastus"
```

The script will:
1. **Auto-generate a secure 16-character password**
2. **Display the password prominently** (save it!)
3. **Deploy the environment** with all resources
4. **Wait for DC configuration** to complete
5. **Save connection info** to `connection-info.txt`

Example output:
```
========================================
Generated Administrator Password
========================================
Xy3@mK8pRz#5nWqE
========================================

IMPORTANT: Save this password securely!
You will need it to RDP to the domain controller.

Press Enter to continue with deployment
```

### Custom Parameters

```powershell
# Custom domain name and name prefix
.\Deploy-TestEnvironment.ps1 `
    -ResourceGroupName "rg-dnstest" `
    -Location "eastus" `
    -NamePrefix "mytest" `
    -DomainName "fabrikam.local"

# Provide your own password (must meet Azure complexity requirements)
$password = ConvertTo-SecureString "YourP@ssw0rd123!" -AsPlainText -Force
.\Deploy-TestEnvironment.ps1 `
    -ResourceGroupName "rg-dnstest" `
    -AdminPassword $password
```

### Password Requirements (if providing your own)

Azure requires passwords to:
- Be between 8-123 characters
- Meet at least 3 of:
  - Uppercase letter (A-Z)
  - Lowercase letter (a-z)
  - Digit (0-9)
  - Special character (!@#$%^&*)

**Tip**: Let the script generate one for you - it's easier!

### Manual Deployment with Azure CLI

```bash
# Create resource group
az group create --name rg-dnstest --location eastus

# Deploy bicep template
az deployment group create \
  --resource-group rg-dnstest \
  --template-file main.bicep \
  --parameters adminPassword='YourP@ssw0rd123!'
```

## Deployment Output

After deployment completes, you'll receive:
- **Hub VNet Name** - Contains DC, Bastion, DNS Resolver
- **Spoke VNet Name** - Contains client VM and storage
- **Domain Controller Private IP** - 10.0.1.4 (in hub VNet)
- **Client VM Private IP** - Dynamic IP (in spoke VNet)
- **Storage Account Name** - for testing private DNS (in spoke VNet)
- **Private DNS Zone Name** - privatelink.blob.core.windows.net
- **Azure Bastion Name** - for secure VM access to both VNets
- **DNS Resolver Name** - for hybrid DNS scenarios
- **DNS Resolver Inbound Endpoint IP** - for on-premises forwarding and spoke VNet DNS
- **Generated Password** - saved in connection-info.txt

Connection info is saved to: `connection-info.txt`

## Testing Your DNS Scripts

### 1. Connect to VMs via Azure Bastion

Azure Bastion provides secure RDP access to both VMs without exposing public IPs.

#### Connect to Domain Controller (Hub VNet)

1. Go to the Azure Portal
2. Navigate to **Resource Groups** > `rg-dnstest`
3. Select the VM: `dnstest-dc`
4. Click **Connect** > **Bastion**
5. Enter credentials:
   - Username: `azureadmin`
   - Password: (from deployment output)
6. Click **Connect**

#### Connect to Windows 11 Client (Spoke VNet)

1. Go to the Azure Portal
2. Navigate to **Resource Groups** > `rg-dnstest`
3. Select the VM: `dnstest-client`
4. Click **Connect** > **Bastion**
5. Enter credentials:
   - Username: `azureadmin`
   - Password: (from deployment output)
6. Click **Connect**

### 2. Copy DNS Scripts to DC

Copy these files to the domain controller:
- `Export-DNSZone.ps1` - Export AD-integrated DNS zones
- `Import-DNSZone.ps1` - Import DNS zones from backup
- `New-DNSConditionalForwarder.ps1` - Create conditional forwarders to Azure DNS

### 3. Test Conditional Forwarder to Azure DNS

```powershell
# On the DC, create a conditional forwarder for the Azure Private DNS zone
.\New-DNSConditionalForwarder.ps1 -DomainName "privatelink.blob.core.windows.net"

# This creates an AD-integrated conditional forwarder to Azure DNS (168.63.129.16)
```

### 4. Verify Private DNS Resolution

#### From Domain Controller (Hub VNet)

```powershell
# On the DC, test DNS resolution
$storageAccount = "<storage-account-name-from-output>"
Resolve-DnsName "$storageAccount.blob.core.windows.net"

# Should return the private endpoint IP (10.1.2.x), not a public IP
nslookup "$storageAccount.blob.core.windows.net"
```

#### From Client VM (Spoke VNet)

```powershell
# On the client VM, test DNS resolution
$storageAccount = "<storage-account-name-from-output>"
Resolve-DnsName "$storageAccount.blob.core.windows.net"

# Should return the private endpoint IP (10.1.2.x) via DNS Resolver
nslookup "$storageAccount.blob.core.windows.net"

# Verify DNS server configuration
ipconfig /all
# Should show DNS Resolver Inbound Endpoint IP

# Test domain DNS resolution
Resolve-DnsName "dc01.contoso.local"
# Should return 10.0.1.4 (DC in hub VNet)
```

### 5. Test Zone Export/Import

```powershell
# Export the AD domain zone
.\Export-DNSZone.ps1 -ZoneName "contoso.local" -ExportPath "C:\DNSBackups"

# Create a test zone with records
Add-DnsServerPrimaryZone -Name "test.local" -ReplicationScope Domain
Add-DnsServerResourceRecordA -ZoneName "test.local" -Name "server1" -IPv4Address "10.0.1.10"
Add-DnsServerResourceRecordA -ZoneName "test.local" -Name "server2" -IPv4Address "10.0.1.20"
Add-DnsServerResourceRecordCName -ZoneName "test.local" -Name "www" -HostNameAlias "server1.test.local"

# Export the test zone
.\Export-DNSZone.ps1 -ZoneName "test.local" -ExportPath "C:\DNSBackups"

# Delete the test zone
Remove-DnsServerZone -Name "test.local" -Force

# Re-import the zone from backup
.\Import-DNSZone.ps1 -ImportFilePath "C:\DNSBackups\test.local_<timestamp>.json"

# Verify records were restored
Get-DnsServerResourceRecord -ZoneName "test.local"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Hub VNet (10.0.0.0/16)                                          │
│ DNS: 10.0.1.4 (Domain Controller)                               │
│                                                                  │
│  ┌────────────────────────────────────────────┐                │
│  │ DomainControllerSubnet (10.0.1.0/24)       │                │
│  │  ┌──────────────────────┐                  │                │
│  │  │ Domain Controller    │                  │                │
│  │  │ - Windows Server 2016│                  │                │
│  │  │ - AD DS              │                  │                │
│  │  │ - DNS Server         │                  │                │
│  │  │ - IP: 10.0.1.4       │                  │                │
│  │  └──────────────────────┘                  │                │
│  └────────────────────────────────────────────┘                │
│                                                                  │
│  ┌────────────────────────────────────────────┐                │
│  │ AzureBastionSubnet (10.0.3.0/26)           │                │
│  │  ┌──────────────────────┐                  │                │
│  │  │ Azure Bastion        │                  │                │
│  │  │ - Secure RDP/SSH     │                  │                │
│  │  │ - Public IP          │                  │                │
│  │  └──────────────────────┘                  │                │
│  └────────────────────────────────────────────┘                │
│                                                                  │
│  ┌────────────────────────────────────────────┐                │
│  │ DnsResolverInboundSubnet (10.0.4.0/28)     │                │
│  │  ┌──────────────────────┐                  │                │
│  │  │ Inbound Endpoint     │◄─────────────────┼────┐           │
│  │  │ - Receives queries   │                  │    │           │
│  │  └──────────────────────┘                  │    │           │
│  └────────────────────────────────────────────┘    │           │
│                                                      │           │
│  ┌────────────────────────────────────────────┐    │           │
│  │ DnsResolverOutboundSubnet (10.0.5.0/28)    │    │           │
│  │  ┌──────────────────────┐                  │    │           │
│  │  │ Outbound Endpoint    │──┐               │    │           │
│  │  │ - Forwards to DC     │  │               │    │           │
│  │  └──────────────────────┘  │               │    │           │
│  └────────────────────────────┼───────────────┘    │           │
│                                │                    │           │
└────────────────────────────────┼────────────────────┼───────────┘
                                 │                    │
                                 │                    │ VNet Peering
                                 │                    │
                                 ▼                    │
┌─────────────────────────────────────────────────────┼───────────┐
│ Spoke VNet (10.1.0.0/16)                            │           │
│ DNS: DNS Resolver Inbound Endpoint                  │           │
│                                                      │           │
│  ┌────────────────────────────────────────────┐    │           │
│  │ ClientSubnet (10.1.1.0/24)                 │    │           │
│  │  ┌──────────────────────┐                  │    │           │
│  │  │ Windows 11 Client    │────────────────────────┘           │
│  │  │ - CLIENT01           │                  │                 │
│  │  │ - Domain member      │                  │                 │
│  │  │ - Dynamic IP         │                  │                 │
│  │  └──────────────────────┘                  │                 │
│  └────────────────────────────────────────────┘                 │
│                                                                  │
│  ┌────────────────────────────────────────────┐                │
│  │ PrivateEndpointSubnet (10.1.2.0/24)        │                │
│  │  ┌──────────────────────┐                  │                │
│  │  │ Storage PE           │                  │                │
│  │  │ - Private IP: 10.1.2.x│                 │                │
│  │  └──────────────────────┘                  │                │
│  └────────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
                         │
                         ├─────► Storage Account (Spoke)
                         │       (Public access disabled)
                         │
                         └─────► Private DNS Zone
                                 privatelink.blob.core.windows.net
```

## DNS Flow

### Hub-Spoke DNS Resolution

1. **Spoke VNet DNS**: Configured to use DNS Resolver Inbound Endpoint
2. **DNS Resolver Inbound Endpoint**: Receives DNS queries from spoke VNet
3. **DNS Resolver Outbound Endpoint**: Forwards `contoso.local` queries to DC (10.0.1.4)
4. **Domain Controller DNS**:
   - Resolves `contoso.local` (AD-integrated zone)
   - Can forward other queries to Azure DNS (168.63.129.16) via conditional forwarders
5. **Azure DNS**: Resolves private endpoint IPs for storage accounts
6. **Result**: Client VM in spoke VNet can resolve both AD domain names and Azure Private Link resources

### Query Flow Example

```
Client VM (10.1.1.x) queries dc01.contoso.local:
  → DNS Resolver Inbound Endpoint
  → DNS Resolver Outbound Endpoint (forwarding rule for contoso.local)
  → Domain Controller (10.0.1.4)
  → Returns: 10.0.1.4

Client VM (10.1.1.x) queries storage.blob.core.windows.net:
  → DNS Resolver Inbound Endpoint
  → Azure Private DNS Zone
  → Returns: 10.1.2.x (private endpoint IP)
```

## Resources Created

| Resource Type | Name Pattern | Location | Purpose |
|---------------|--------------|----------|---------|
| Virtual Network | `{prefix}-hub-vnet` | Hub | Hub network infrastructure |
| Virtual Network | `{prefix}-spoke-vnet` | Spoke | Spoke network infrastructure |
| VNet Peering | `hub-to-spoke` | Hub | Hub to spoke connectivity |
| VNet Peering | `spoke-to-hub` | Spoke | Spoke to hub connectivity |
| Network Security Group | `{prefix}-dc-nsg` | Hub | DC firewall rules |
| Network Security Group | `{prefix}-client-nsg` | Spoke | Client firewall rules |
| Network Interface | `{prefix}-dc-nic` | Hub | DC network adapter (static IP) |
| Network Interface | `{prefix}-client-nic` | Spoke | Client network adapter (dynamic IP) |
| Virtual Machine | `{prefix}-dc` | Hub | Domain Controller (D2s_v3) |
| Virtual Machine | `{prefix}-client` | Spoke | Windows 11 Client (B2s) |
| VM Extension | `ConfigureADDC` | Hub | Custom Script Extension for AD setup |
| Storage Account | `{prefix}{uniquestring}` | Spoke | Test storage with private link |
| Private Endpoint | `{prefix}-blob-pe` | Spoke | Private link to storage |
| Private DNS Zone | `privatelink.blob.core.windows.net` | Global | Azure Private DNS |
| Bastion Host | `{prefix}-bastion` | Hub | Secure access to both VNets |
| Public IP | `{prefix}-bastion-pip` | Hub | Bastion public IP |
| DNS Resolver | `{prefix}-dns-resolver` | Hub | Hybrid DNS resolution |
| DNS Inbound Endpoint | `{prefix}-inbound-endpoint` | Hub | Receives queries from spoke |
| DNS Outbound Endpoint | `{prefix}-outbound-endpoint` | Hub | Forwards queries to DC |
| DNS Forwarding Ruleset | `{prefix}-forwarding-ruleset` | Hub | Routes domain queries to DC |

## Cost Estimation

Approximate costs for running this environment (East US pricing):
- Domain Controller VM (D2s_v3): ~$0.096/hour (~$70/month)
- Windows 11 Client VM (B2s): ~$0.042/hour (~$30/month)
- DC OS Disk (128GB Premium): ~$20/month
- Client OS Disk (128GB Standard SSD): ~$10/month
- Storage Account (Standard LRS): ~$0.01/GB + transactions
- Bastion (Standard): ~$0.19/hour (~$140/month)
- VNet Peering: Minimal (~$0.01/GB transferred)
- DNS Private Resolver: ~$0.013/hour (~$10/month)
- Other resources (VNet, NSG, Private Endpoint): Minimal/Free

**Total: ~$280-300/month if left running**

**Note**: Azure Bastion is the largest cost component. For testing, you may want to:
- Deploy only when needed and delete when done
- Or use a lower-cost remote access method for short-term labs

💰 **Cost Savings Tip**: This is a lab environment. Delete it when done testing!

## Cleanup

### Delete Everything

```powershell
# Using the deployment script variable
az group delete --name rg-dnstest --yes --no-wait

# Or force delete immediately
az group delete --name rg-dnstest --yes --no-wait --force-deletion-types Microsoft.Compute/virtualMachines
```

### Verify Deletion

```powershell
az group exists --name rg-dnstest
# Should return: false
```

## Troubleshooting

### Extension Failed / DC Not Promoted

Check extension logs on the DC:
```
C:\WindowsAzure\Logs\Plugins\Microsoft.Compute.CustomScriptExtension\
```

View Windows Event Logs:
```powershell
# AD DS promotion logs
Get-WinEvent -LogName "Directory Service" -MaxEvents 50

# DNS logs
Get-WinEvent -LogName "DNS Server" -MaxEvents 50
```

Check AD status:
```powershell
Get-Service ADWS,DNS
Get-ADDomain
dcdiag /v
```

### DNS Not Resolving Private Endpoint

1. **Verify VNet DNS servers**:
   ```powershell
   az network vnet show --resource-group rg-dnstest --name dnstest-vnet --query dhcpOptions.dnsServers
   # Should show: ["10.0.1.4"]
   ```

2. **Check private DNS zone records**:
   ```powershell
   az network private-dns record-set list --resource-group rg-dnstest --zone-name privatelink.blob.core.windows.net
   ```

3. **On DC, verify DNS configuration**:
   ```powershell
   Get-DnsServerZone
   Get-DnsServerForwarder
   ipconfig /all  # Should show DNS server as 10.0.1.4
   ```

### Can't RDP to Domain Controller

**Issue**: RDP is restricted to IP 47.199.28.203

**Solution**: Update [main.bicep](main.bicep#L73) line 73 with your public IP:

```bicep
sourceAddressPrefix: 'YOUR.PUBLIC.IP.ADDRESS'
```

Find your public IP: `https://api.ipify.org`

Then redeploy or update the NSG:
```powershell
az network nsg rule update \
  --resource-group rg-dnstest \
  --nsg-name dnstest-dc-nsg \
  --name AllowRDP \
  --source-address-prefixes YOUR.PUBLIC.IP.ADDRESS
```

### Password Issues

If you get password validation errors:
1. Let the script auto-generate one (easiest)
2. Or ensure your password meets all requirements:
   - 8-123 characters
   - At least 3 of: uppercase, lowercase, digit, special character
   - No control characters

### Deployment Takes Too Long

- **Normal time**: 15-25 minutes
- **AD promotion**: 8-12 minutes of that
- **Monitor progress**: Check Azure Portal → Resource Group → Deployments

If stuck, check VM extension status:
```powershell
az vm get-instance-view --resource-group rg-dnstest --name dnstest-dc --query instanceView.extensions
```

## Key Differences from Production

This is optimized for **lab/testing**:

| Aspect | Lab Config | Production Best Practice |
|--------|------------|-------------------------|
| AD Database | OS Disk (C:) | Separate data disk |
| VM Size | D2s_v3 (cheap) | Appropriate for workload |
| Disk Type | Premium SSD | Premium SSD with backups |
| RDP Access | Single IP | Azure Bastion or VPN |
| Storage | Standard LRS | Zone-redundant or geo-redundant |
| Monitoring | None | Azure Monitor, alerts |
| Backup | None | Azure Backup for VM & DNS |

## Files

| File | Purpose |
|------|---------|
| `main.bicep` | Infrastructure as Code template |
| `main.parameters.json` | Sample parameters (optional) |
| `Deploy-TestEnvironment.ps1` | Automated deployment with Azure CLI |
| `README.md` | This file - full documentation |
| `DEPLOYMENT-NOTES.md` | Technical implementation details |
| `connection-info.txt` | Generated after deployment with connection details |

## Next Steps After Deployment

1. ✅ **Connect via Azure Bastion** to both VMs using generated password
   - Domain Controller (Hub): `dnstest-dc`
   - Windows 11 Client (Spoke): `dnstest-client`
2. ✅ **Verify AD DS** on Domain Controller: `Get-Service ADWS,DNS`
3. ✅ **Test DNS Resolution** from Client VM:
   - Test domain resolution: `Resolve-DnsName dc01.contoso.local`
   - Test storage private endpoint: `Resolve-DnsName <storage>.blob.core.windows.net`
   - Verify DNS Resolver Inbound Endpoint is configured: `ipconfig /all`
4. ✅ **Copy DNS scripts** to the DC for testing
5. ✅ **Test conditional forwarder** creation to Azure DNS
6. ✅ **Test zone export/import** functionality
7. ✅ **Verify hub-spoke connectivity**:
   - Ping DC from client VM
   - Test network communication across peering
8. ✅ **Document findings** and verify DNS flow works as expected
9. ✅ **Delete resources when done** to avoid charges (~$280-300/month)

---

**Important**: This is a test/lab environment. Do not use in production without proper security hardening, backups, and monitoring.

Need help? Check troubleshooting section above or review `DEPLOYMENT-NOTES.md` for technical details.
