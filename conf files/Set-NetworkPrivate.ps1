# Get the current network adapter (assumes only one active Ethernet connection)
$network = Get-NetConnectionProfile | Where-Object {$_.InterfaceAlias -like "Ethernet*" -and $_.NetworkCategory -ne "Private"}

if ($network) {
    Set-NetConnectionProfile -InterfaceAlias $network.InterfaceAlias -NetworkCategory Private
}
