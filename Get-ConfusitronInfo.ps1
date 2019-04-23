<#
.SYNOPSIS
	Use Get-ConfusitronInfo.ps1 to data for Netapp to predict Snapmirror/Sanpvault growth.
.DESCRIPTION
	This advanced PowerShell script uses native PowerShell functionality, DataOntap toolkit, and Active Directory tools to create a zip file for Netapp.
.EXAMPLE
	Example 1:
    C:\PS>Get-Confusitron.ps1 -Controller mymgmtnode
    This example will collect data from each node of mymgmtnode's cluster and email netapp and the user of the script the results.

    Example 2:
    C:\PS>Get-Confusitron.ps1 -Controller mymgmtnode1,mymgmtnode2 -EmailMyself $false
    This example will collect data from each node of mymgmtnode1 and mymgmtnode2 clusters and email netapp and not the user of the script the results.
.INPUTS
.OUTPUTS
.PARAMETER Controller
    This is a required parameter.
.PARAMETER Credentials
    This is a required parameter.
.PARAMETER NetappEmail
    This is not a required parameter.
.PARAMETER EmailMyself
    This is not a required parameter.
.NOTES
	To see the examples, type: "Get-Help Get-Confusitron.ps1 -Examples"
	To see more information, type: "Get-Help Get-Confusitron.ps1 -Detail"
	To see technical information, type: "Get-Help Get-Confusitron.ps1 -Full"
.LINK
	No link
#Requires -Version 5.0
#Requires DataOntap toolkit 3.1
#Requires ActiveDirectory module
#Version 2017.08.31
#>
[CmdletBinding()]
Param(
	[Parameter(Position=0,
	Mandatory=$true,
	HelpMessage="Please specify the Management name or IP to gather data from (for multiple entrys seperate by a ,",
	ValueFromPipeline=$true,
	ValueFromPipelineByPropertyName=$true)]
	[alias("Controller")]
	[System.Array]$mgmtnodes= "",

	[Parameter(Position=1,
	Mandatory=$false,
	HelpMessage="Please specify the Netapp email address to send the results to",
	ValueFromPipeline=$true,
	ValueFromPipelineByPropertyName=$true)]
	[alias("NetappEmail")]
	[System.Net.Mail.MailAddress]$email = "someone@somewhere.com",

	[Parameter(Position=2,
	Mandatory=$false,
	HelpMessage="Please specify whether to include an email to yourself",
	ValueFromPipeline=$true,
	ValueFromPipelineByPropertyName=$true)]
	[alias("EmailMyself")]
	[System.Boolean]$emailme = $true
)

$filepath = $env:TEMP
$files = @()
$oldzips = dir "$filepath\confusitron_*.zip"
$zipfile = "$filepath\confusitron_$(Get-Date -format "MMM-dd-yyyy-HHmm").zip"

if (!($creds)){
    Write-Output "Enter Credentials for connecting to the Filers"
    $creds = Get-Credential -ErrorAction Stop
}

Write-Progress -Id 1 -Activity "Running Confusitron" -PercentComplete (1) -Status "Running data collection:"
foreach ($controller in $mgmtnodes){
    $controllerprogress=0
    Write-Progress -Id 2 -Activity "Running data collection on $controller, and all member nodes." -PercentComplete (1) -Status "Starting" -ParentId 1
    Connect-NcController $controller -Credential $creds -ErrorAction Stop
    $nodes = (Get-NcNode -ErrorAction Stop).Node    
    Write-Progress -Id 2 -Activity "Running data collection on $controller" -PercentComplete (1) -Status "Querying nodes $nodes" -ParentId 1
    foreach ($node in $nodes) {
        $sysnode = "system node run -node $node"
        $confcmds = "hostname", "date", "version", "df -A", "df -k -g", "df -S", "snap delta"
        $cluscmds = "snapmirror show"
        $currentprogress=0
        $nodeprogress=0
        Write-Progress -Id 3 -Activity "Running data collection on $node" -PercentComplete ((1/$(($cluscmds.Count) + ($confcmds.Count))*100)) -Status "Starting"  -ParentId 2
        foreach ($confcmd in $confcmds) {
            $result += (Invoke-NcSsh -ControllerName $controller -Command "$sysnode $confcmd" -Credential $creds).Value
            $currentprogress++
            Write-Progress -Id 3 -Activity "Running data collection on $node" -PercentComplete (($currentprogress/$(($cluscmds.Count) + ($confcmds.Count))*100)) -Status "Running $confcmd" -ParentId 2
        }
        foreach ($cluscmd in $cluscmds) {
            $result += (Invoke-NcSsh -ControllerName $controller -Command "$cluscmd" -Credential $creds).Value
            $currentprogress++
            Write-Progress -Id 3 -Activity "Running data collection on $node" -PercentComplete (($currentprogress/$(($cluscmds.Count) + ($confcmds.Count))*100)) -Status "Running $clucmd" -ParentId 2
        }
        $result | Out-File -FilePath "$filepath\$node.txt" -Encoding ascii
        $files += (dir $filepath\$node.txt).FullName
        $nodeprogress++
        Write-Progress -Id 3 -Activity "Running data collection on $node" -PercentComplete (($nodeprogress/$($nodes.Count))*100) -Status "Finishing $node" -ParentId 2
    }
        
    $controllerprogress++
    Write-Progress -Id 2 -Activity "Running Confusitron" -PercentComplete (($controllerprogress/$($mgmtnodes.Count)*100)) -Status "Running data collection:" -ParentId 1
}

Write-Progress -Id 1 -Activity "Running Confusitron" -PercentComplete (90) -Status "Running data collection:"

#region ### Create Zip and remove temporary files
if ($files){
    Compress-Archive -Path $files -DestinationPath $zipfile
    rm $files
}
#endregion

Write-Progress -Id 1 -Activity "Running Confusitron" -PercentComplete (95) -Status "Running data collection:"

#region ### Send E-mail to Netapp from the user running this script
$body = "Here is the data you requested"

if ($email){
    $currentuser = [System.Environment]::UserName
    $myemail = (Get-ADUser $currentuser  -Properties mail).mail
    Send-MailMessage -To $email -From $myemail -SmtpServer mailer.am.ds.rd.honda.com -Subject "Confusitron" -Body "$body" -BodyAsHtml -Attachments $zipfile
}

if ($emailme){
    Send-MailMessage -To $myemail -From $myemail -SmtpServer mailer.am.ds.rd.honda.com -Subject "Confusitron" -Body "Emailed $zipfile to $email" -BodyAsHtml
}
#endregion

Write-Progress -Id 1 -Activity "Running Confusitron" -PercentComplete (99) -Status "Running data collection:"

#region ### Clean up files
if ($oldzips){
    rm $oldzips
}
#endregion

Write-Progress -Id 1 -Activity "Running Confusitron" -PercentComplete (100) -Status "Running data collection:"