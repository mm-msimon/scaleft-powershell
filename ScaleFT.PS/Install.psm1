<# 
 .Synopsis
  Installs the ScaleFT Server Toools

 .Description
  Installs the ScaleFT Server Tools to a specific version, and if installing for the first time
  will set the configuration file with various values.

 .Parameter ToolsVersion
  Optional, version of the ScaleFT Server Tools to Install. If not supplied, the latest available
  version is installed.

 .Parameter InstanceURL
  Optional, Custom ScaleFT Platform URL

 .Parameter EnrollmentToken
  Optionally sets the ScaleFT Enrollment Token 

 .Parameter ReleaseChannel
  Installs ScaleFT Server Tools from an non-stable release channel

 .Example
   # Installs the ScaleFT Server Agent
   Install-ScaleFTServerTools -ToolsVersion 1.22.1
#>

function Get-URL-With-Authenticode(){
    param(
        [Parameter(Mandatory=$true)][string]$url,
        [Parameter(Mandatory=$true)][string]$pinnedCertId,
        [Parameter(Mandatory=$true)][string]$output
    )
    process{
        $baseDir = Split-Path -Parent -Path $output

        if (!(Test-Path "$output")) {
            echo "Downloading $url to $output"
            New-Item -force -path $baseDir -type directory
            Invoke-WebRequest -UserAgent "ScaleFT/PS1-0.2.1" -UseBasicParsing -TimeoutSec 30 -Uri $url -OutFile $output
        } else {
            echo "Existing $output found"
        }

        $sig = Get-AuthenticodeSignature $output

        if ($sig.Status -ne "Valid") {
            echo "error: signature for $($output) is invalid: $($sig.Status) from $($sig.SignerCertificate.ToString())"
            throw "error: signature for $($output) is invalid: $($sig.Status) from $($sig.SignerCertificate.ToString())"
        }

 	if ($sig.SignerCertificate.GetCertHashString() -ne $pinnedCertId) {
            echo "error: signature for $($output) is from wrong certificate: $($sig.SignerCertificate.GetCertHashString()) from $($sig.SignerCertificate.ToString())"
            throw "error: signature for $($output) is from wrong certificate: $($sig.SignerCertificate.GetCertHashString()) from $($sig.SignerCertificate.ToString())"
        }

        echo "$($output) is signed by ScaleFT"
    }
}

function Stop-ScaleFTService(){
    $installed = [bool](Get-Service | Where-Object Name -eq "scaleft-server-tools")
    if ($installed -eq $true) {
        echo "Stoping Service scaleft-server-tools"
        Stop-Service -Name "scaleft-server-tools"
        return $true
    }
    return $false
}

function Start-ScaleFTService(){
    $installed = [bool](Get-Service | Where-Object Name -eq "scaleft-server-tools")
    if ($installed -eq $true) {
        echo "Starting Service scaleft-server-tools"
        Start-Service -Name "scaleft-server-tools"
        return $true
    }
    return $false
}



function Install-ScaleFTServerTools(){
    param(
        [ValidateSet("stable","testing")] 
        [Parameter(Mandatory=$false)][string]$ReleaseChannel = "stable",
        
        [Parameter(Mandatory=$false)][string]$EnrollmentToken,
        
        [Parameter(Mandatory=$false)][string]$InstanceURL,
        
        [Parameter(Mandatory=$false)][string]$ToolsVersion
    )
    process{
        $ErrorActionPreference = "Stop";

        # ScaleFT Authenticode Signing Certificate
        $pinnedCertId = "ead228893eeb01615136725dce136ff8457e4424"
        $installerURL = ""
        if ($PSBoundParameters.ContainsKey("ToolsVersion")) {
            if ($ReleaseChannel -eq "stable") {
                $installerURL = "https://dist.scaleft.com/server-tools/windows/v$($ToolsVersion)/ScaleFT-Server-Tools-$($ToolsVersion).msi"
            } else {
                $installerURL = "https://dist-$($ReleaseChannel).scaleft.com/server-tools/windows/v$($ToolsVersion)/ScaleFT-Server-Tools-$($ToolsVersion).msi"                
            }
        } else {
            if ($ReleaseChannel -eq "stable") {
                $installerURL = "https://dist.scaleft.com/server-tools/windows/latest/ScaleFT-Server-Tools-latest.msi"
            } else {
                throw "error: When -ReleaseChannel is set to non-stable, an exact version to install must be supplied."
            }
        }

        # Select Local System User, where the ScaleFT Server Agent Runs
        $systemprofile = (Get-CIMInstance win32_userprofile  | where-object sid -eq "S-1-5-18" | select -ExpandProperty localpath)
        $stateDir = Join-Path $systemprofile -ChildPath 'AppData' | Join-Path -ChildPath "Local" | Join-Path -ChildPath "ScaleFT"
    
        if ($PSBoundParameters.ContainsKey("EnrollmentToken")) {
            $tokenPath = Join-Path $stateDir -ChildPath "enrollment.token"
            New-Item -ItemType directory -Path $stateDir -force
            $EnrollmentToken | Out-File $tokenPath -Encoding "ASCII" -Force
        }

        if ($PSBoundParameters.ContainsKey("InstanceURL")) {
            $configPath = Join-Path $stateDir -ChildPath "sftd.yaml"
            New-Item -ItemType directory -Path $stateDir -force
            "InitialURL: $($InstanceURL)"  | Out-File $configPath -Encoding "ASCII" -Force
        }

        $msiPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.msi')
        $msiLog = [System.IO.Path]::ChangeExtension($msiPath, '.log')

        Get-URL-With-Authenticode -url $installerURL -pinnedCertId $pinnedCertId -output $msiPath

        $stopped = Stop-ScaleFTService

        trap {
            if ($stopped -eq $true) {
                Start-ScaleFTService
            }
            break
        }

        echo "Starting msiexec on $($msiPath)"
        echo "MSI Log path: $($msiLog)"

        $status = Start-Process -FilePath msiexec -ArgumentList /i,$msiPath,/qn,/L*V!,$msiLog  -Wait -PassThru

        if ($status.ExitCode -ne 0 -or $status.Exitcode -ne 1603) {
	        Start-ScaleFTService
            throw "msiexec failed with exit code: $($status.ExitCode) Log: $($msiLog)"
        }

        echo "Removing $($msiPath)"
        Remove-Item -Force $msiPath

        Start-ScaleFTService
    }
}

Export-ModuleMember -function Install-ScaleFTServerTools
