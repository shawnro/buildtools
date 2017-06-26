param
(
    [Parameter(Mandatory=$false)][string]$RepositoryRoot = $PSScriptRoot,
    [Parameter(Mandatory=$false)][string]$ToolsLocalPath = (Join-Path $RepositoryRoot "Tools"),
    [Parameter(Mandatory=$false)][string]$CliLocalPath = (Join-Path $ToolsLocalPath "dotnetcli"),
    [Parameter(Mandatory=$false)][string]$SharedFrameworkSymlinkPath = (Join-Path $ToolsLocalPath "dotnetcli\shared\Microsoft.NETCore.App\version"),
    [Parameter(Mandatory=$false)][string]$SharedFrameworkVersion = "<auto>",
    [Parameter(Mandatory=$false)][string]$Architecture = "<auto>",
    [Parameter(Mandatory=$false)][string]$DotNetInstallBranch = "rel/1.0.0",
    [switch]$Force = $false
)

$projHelper = "projhelper.ps1"
$projHelperPath = Join-Path $ToolsLocalPath $projHelper

# download CLI boot-strapper script
# Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/buildtools/master/projmod.psm1" -OutFile $dotnetInstallPath
Copy-Item  (Join-Path $RepositoryRoot $projHelper) $projHelperPath

. $projHelperPath

$rootToolVersions = Join-Path $RepositoryRoot ".toolversions"
$bootstrapComplete = Join-Path $ToolsLocalPath "bootstrap.complete"

# if the force switch is specified delete the semaphore file if it exists
if ($Force -and (Test-Path $bootstrapComplete))
{
    Remove-Item $bootstrapComplete
}

# if the semaphore file exists and is identical to the specified version then exit
if ((Test-Path $bootstrapComplete) -and !(Compare-Object (Get-Content $rootToolVersions) (Get-Content $bootstrapComplete)))
{
    exit 0
}

$initCliScript = "dotnet-install.ps1"
$dotnetInstallPath = Join-Path $ToolsLocalPath $initCliScript

# blow away the tools directory so we can start from a known state
if (Test-Path $ToolsLocalPath)
{
    # if the bootstrap.ps1 script was downloaded to the tools directory don't delete it
    Remove-Item (Join-Path $ToolsLocalPath "*") -Recurse -Force -Exclude "bootstrap.ps1", $projHelper
}
else
{
    mkdir $ToolsLocalPath | Out-Null
}

# download CLI boot-strapper script
Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/cli/$DotNetInstallBranch/scripts/obtain/dotnet-install.ps1" -OutFile $dotnetInstallPath

# load the version of the CLI
$rootCliVersion = Join-Path $RepositoryRoot ".cliversion"
$dotNetCliVersion = Get-Content $rootCliVersion

if (-Not (Test-Path $CliLocalPath))
{
    mkdir $CliLocalPath | Out-Null
}

# now execute the script
Write-Host "$dotnetInstallPath -Version $dotNetCliVersion -InstallDir $CliLocalPath -Architecture ""$Architecture"""
Invoke-Expression "$dotnetInstallPath -Version $dotNetCliVersion -InstallDir $CliLocalPath -Architecture ""$Architecture"""
if ($LastExitCode -ne 0)
{
    Write-Output "The .NET CLI installation failed with exit code $LastExitCode"
    exit $LastExitCode
}

# create a junction to the shared FX version directory. this is
# so we have a stable path to dotnet.exe regardless of version.
$runtimesPath = Join-Path $CliLocalPath "shared\Microsoft.NETCore.App"
if ($SharedFrameworkVersion -eq "<auto>")
{
    $SharedFrameworkVersion = Get-ChildItem $runtimesPath -Directory | Sort-Object -Descending | Select-Object -First 1
}
$junctionTarget = Join-Path $runtimesPath $SharedFrameworkVersion
$junctionParent = Split-Path $SharedFrameworkSymlinkPath -Parent
if (-Not (Test-Path $junctionParent))
{
    mkdir $junctionParent | Out-Null
}
if (-Not (Test-Path $SharedFrameworkSymlinkPath))
{
    cmd.exe /c mklink /j $SharedFrameworkSymlinkPath $junctionTarget | Out-Null
}

$toolPackages = @{}
$tools = Get-Content $rootToolVersions
foreach ($tool in $tools)
{
    $name, $version = $tool.split("=")
    $toolPackages.Add($name, $version)
}

$dotnetExe = Join-Path $cliLocalPath "dotnet.exe"
$projectTypeInfo = Get-ProjectTypeInfo -DotnetExePath $dotnetExe
$projectFilePath = Join-Path $ToolsLocalPath "project.$($projectTypeInfo.Extension)"

# write project file
& $projectTypeInfo.WriteFunc -ProjectFilePath $projectFilePath -TargetFrameworkVersions "netcoreapp1.0" -Packages $toolPackages

# now restore the packages
if ($env:buildtools_source -ne $null)
{
    $BuildToolsSource = $env:buildtools_source
}
$packagesPath = Join-Path $RepositoryRoot "packages"
$restoreArgs = "restore $projectFilePath --packages $packagesPath --source $BuildToolsSource --source $NugetOrgSource"  
Invoke-DotnetCommand -DotnetExePath $dotnetExe -CommandArgs $restoreArgs

# now stage the contents to tools directory and run any init scripts
foreach ($tool in $tools)
{
    $name, $version = $tool.split("=")

    # verify that the version we expect is what was restored
    $pkgVerPath = Join-Path $packagesPath "$name\$version"
    if ((Test-Path $pkgVerPath) -eq 0)
    {
        Write-Output "Directory '$pkgVerPath' doesn't exist, ensure that the version restored matches the version specified."
        exit 1
    }

    # at present we have the following conventions when staging package content:
    #   1.  if a package contains a "tools" directory then recursively copy its contents
    #       to a directory named the package ID that's under $ToolsLocalPath.
    #   2.  if a package contains a "libs" directory then recursively copy its contents
    #       under the $ToolsLocalPath directory.
    #   3.  if a package contains a file "lib\init-tools.cmd" execute it.

    if (Test-Path (Join-Path $pkgVerPath "tools"))
    {
        $destination = Join-Path $ToolsLocalPath $name
        mkdir $destination | Out-Null
        & robocopy (Join-Path $pkgVerPath "tools") $destination /E
    }
    elseif (Test-Path (Join-Path $pkgVerPath "lib"))
    {
        & robocopy (Join-Path $pkgVerPath "lib") $ToolsLocalPath /E
    }

    if (Test-Path (Join-Path $pkgVerPath "lib\init-tools.cmd"))
    {
        # TODO: this is currently pulling from the checked in source directory and needs to be updated
        & robocopy (Join-Path $RepositoryRoot "src\Microsoft.DotNet.Build.Tasks\PackageFiles") (Join-Path $pkgVerPath "lib") "init-tools.*"

        cmd.exe /c (Join-Path $pkgVerPath "lib\init-tools.cmd") $RepositoryRoot $dotNetExe $ToolsLocalPath | Out-File (Join-Path $RepositoryRoot "Init-$name.log")
    }
}

# write semaphore file
Copy-Item $rootToolVersions $bootstrapComplete

exit 0

