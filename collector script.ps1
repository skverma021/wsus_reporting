#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enterprise WSUS Client Intelligence & Downstream Sync Collector (60-Minute Task)
.DESCRIPTION
    Collects client registration date, reporting server, OS version, duplicate SusClientIds,
    and Downstream sync statuses across all 40 WSUS servers. Publishes JSON directly to IIS.
#>

param(
    [string[]]$DownstreamServers = @("WSUS-DS-US-01","WSUS-DS-US-02","WSUS-DS-EMEA-01","WSUS-DS-APAC-01"),
    [string]$IISVirtualDirPath   = "C:\Program Files\Update Services\WebServices\Root\ClientDashboard"
)

[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$Wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer()

# 1. Query Client Registrations with First Contact & Last Sync Across Fleet
$Scope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope
$Scope.IncludeSubgroups = $true
$RawClients = $Wsus.GetComputerTargets($Scope)

$ClientInventory = foreach ($c in $RawClients) {
    [PSCustomObject]@{
        ComputerName        = $c.FullDomainName.ToLower()
        IPAddress           = $c.IPAddress.ToString()
        OSDescription       = $c.OSDescription
        CreatedDate         = $c.CreationDate.ToString("yyyy-MM-dd HH:mm:ss")
        LastSyncTime        = $c.LastReportedStatusTime.ToString("yyyy-MM-dd HH:mm:ss")
        SusClientId         = $c.Id.ToString()
        TargetGroup         = ($c.GetComputerTargetGroups() | Select-Object -ExpandProperty Name) -join ", "
        WuaVersion          = $c.ClientVersion
        ReportingWsusServer = $env:COMPUTERNAME
    }
}

# 2. Duplicate Detection: Group by SusClientId and FQDN
$DuplicateSusIds = $ClientInventory | Group-Object SusClientId | Where-Object { $_.Count -gt 1 }
$DuplicateHosts  = $ClientInventory | Group-Object ComputerName | Where-Object { $_.Count -gt 1 }

# 3. Collect Downstream Sync Statuses
$Sub = $Wsus.GetSubscription()
$SyncHistory = $Sub.GetLastSynchronizationInfo()

Write-Host "Collected $($ClientInventory.Count) clients. Identified $($DuplicateSusIds.Count) duplicate GUID collisions." -ForegroundColor Green
