Configuration InstallAzAgent
{
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node localhost
    {
        Script InstallAgent {
            GetScript  = {
                get-service -Name "vstsagent*"
            }
            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $service = get-service -Name "vstsagent*"

                if ( $service.Status -eq "Running" ) {
                    Write-Verbose -Message ('Service {0} is Running - Display Name: {1}' -f $service.Name, $service.DisplayName)
                    return $true
                }
                Write-Verbose -Message ('Az DevOps Agent is NOT Running')
                return $false
            }
            SetScript  = {
                            
                $configurationFileName = ".\appSettings.json"

                if (-not(Test-Path $configurationFileName)) {
                    throw "Configuration file '$configurationFileName' not found"
                }


                $configuration = (Get-Content -Raw -Path $configurationFileName | ConvertFrom-Json)

                $ErrorActionPreference = "Stop"; 


                If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole( [Security.Principal.WindowsBuiltInRole] "Administrator")) { throw "Run command in an administrator PowerShell prompt" }; 

                If ($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0"))) { throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell." }; 

                If (-NOT (Test-Path $env:SystemDrive\'azagent')) {
                    mkdir $env:SystemDrive\'azagent'
                }; 

                cd $env:SystemDrive\'azagent'; 

                for ($i = 1; $i -lt 100; $i++) {
                    $destFolder = "A" + $i.ToString();

                    if (-NOT (Test-Path ($destFolder))) {
                        mkdir $destFolder; cd $destFolder; break;
                    }
                }; 

                $agentZip = "$PWD\agent.zip";

                $DefaultProxy = [System.Net.WebRequest]::DefaultWebProxy;
                $securityProtocol = @();

                $securityProtocol += [Net.ServicePointManager]::SecurityProtocol;

                $securityProtocol += [Net.SecurityProtocolType]::Tls12;

                [Net.ServicePointManager]::SecurityProtocol = $securityProtocol;
                $WebClient = New-Object Net.WebClient; 

                $Uri = $configuration.AzDevOps.AgentDownloadURL

                if ($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri))) {
                    $WebClient.Proxy = New-Object Net.WebProxy($DefaultProxy.GetProxy($Uri).OriginalString, $True);
                };

                $WebClient.DownloadFile($Uri, $agentZip);

                Add-Type -AssemblyName System.IO.Compression.FileSystem;
                [System.IO.Compression.ZipFile]::ExtractToDirectory( $agentZip, "$PWD");

                .\config.cmd `
                    --unattended `
                    --deploymentgroup `
                    --deploymentgroupname $configuration.AzDevOps.DeploymentGroupName `
                    --agent $env:COMPUTERNAME `
                    --runasservice `
                    --work '_work' `
                    --url $configuration.AzDevOps.URLRegistration `
                    --projectname $configuration.AzDevOps.ProjectName `
                    --auth PAT `
                    --token $configuration.AzDevOps.Token `
                    --addDeploymentGroupTags `
                    --deploymentGroupTags $configuration.AzDevOps.Tag `
                    --windowsLogonAccount $configuration.Logon.windowsLogonAccount `
                    --windowsLogonPassword $configuration.Logon.windowsLogonPassword

                Remove-Item $agentZip;
            }
        }
    }
}

InstallAzAgent