param
(
    [Parameter(Mandatory=$true)][string]$RepositoryRoot,
    [Parameter(Mandatory=$true)][string]$DotnetExePath,
    [Parameter(Mandatory=$true)][string]$ToolsLocalPath,
    [Parameter(Mandatory=$false)][string]$PackagesDirectory = $ToolsLocalPath,
    [switch]$Force = $false
)

$buildToolsPackageDirectory = $PSScriptRoot

# load dependency script
$projHelper = "projhelper.ps1"
$projHelperPath = Join-Path $ToolsLocalPath $projHelper

if (-Not (Test-Path $projHelperPath))
{
    Write-Host "ERROR: Unable to find dependency [$projHelperPath]. Ensure that it exists."
    exit 1
}

. $projHelperPath

# Ensure we can find the function we're calling
if (-Not (Get-Command "Get-ProjectTypeInfo"))
{
    Write-Host "ERROR: Unable to load function '$writeProjectFunc' from script [$projHelperPath]."
    exit 1
}

# TODO: should these be hard coded or read in from somewhere else?
$microBuildVersion = "0.2.0"
$portableTargetsVersion = "0.1.1-dev"
$roslynCompilersVersion = "2.0.0-rc"

<# these are also defined in bootstrap.ps1
$buildToolsSource = "https://dotnet.myget.org/F/dotnet-buildtools/api/v3/index.json"
$dotnetCoreSource = "https://dotnet.myget.org/F/dotnet-core/api/v3/index.json"
$nugetOrgSource = "https://api.nuget.org/v3/index.json"
#>

$initToolsRestoreArgs = "--source $BuildToolsSource --source $NugetOrgSource"
$toolRuntimeRestoreArgs = "--source $DotnetCoreSource $initToolsRestoreArgs"

if (-Not (Test-Path $RepositoryRoot))
{
    Write-Host "ERROR: Cannot find project root path at [$RepositoryRoot]. Please pass in the source directory as the 1st parameter."
    exit 1
}

if (-Not (Test-Path $DotnetExePath))
{
    Write-Host "ERROR: Cannot find dotnet cli at [$DotnetExePath]. Please pass in the path to dotnet.exe as the 2nd parameter."
    exit 1
}

# TODO: Why is this here? We do this same copy in bootstrap.ps1
& robocopy (Join-Path $buildToolsPackageDirectory ".") $ToolsLocalPath /E

# Determine if the CLI supports MSBuild projects. This controls whether csproj files are used for initialization and package restore
$projectTypeInfo = Get-ProjectTypeInfo -DotnetExePath $DotnetExePath

# TODO: this is currently pulling from the checked in source directory and needs to be updated
#$toolRuntimeProject = (Join-Path $RepositoryRoot "src\Microsoft.DotNet.Build.Tasks\PackageFiles\tool-runtime\project.$projectExtension")
$toolRuntimeProject = (Join-Path $buildToolsPackageDirectory "tool-runtime\project.$($projectTypeInfo.Extension)")

Invoke-DotnetCommand -DotnetExePath $DotnetExePath -CommandArgs "restore $toolRuntimeProject $toolRuntimeRestoreArgs"
Invoke-DotnetCommand -DotnetExePath $DotnetExePath -CommandArgs "publish $toolRuntimeProject -f $($projectTypeInfo.PublishTfm) -o $ToolsLocalPath"
Invoke-DotnetCommand -DotnetExePath $DotnetExePath -CommandArgs "publish $toolRuntimeProject -f net45 -o $(Join-Path $ToolsLocalPath "net45")"

# Copy some roslyn files which are published into runtimes\any\native to the root
& robocopy (Join-Path $ToolsLocalPath "runtimes\any\native") $ToolsLocalPath

# Microsoft.Build.Runtime dependency is causing the MSBuild.runtimeconfig.json buildtools copy to be overwritten - re-copy the buildtools version.
& robocopy (Join-Path $buildToolsPackageDirectory ".") $ToolsLocalPath "MSBuild.runtimeconfig.json"

# Copy Portable Targets Over to ToolRuntime
$generatedPackagesDirectory = (Join-Path $PackagesDirectory "generated")
if (-Not (Test-Path $generatedPackagesDirectory))
{
    New-Item $generatedPackagesDirectory -ItemType Directory
}

$portableTargetsProject = (Join-Path $generatedPackagesDirectory "project.$($projectTypeInfo.Extension)")

$frameworks = "netcoreapp1.0", "net46";
$packages = @{
    'MicroBuild.Core' = $microBuildVersion;
    'Microsoft.Portable.Targets' = $portableTargetsVersion;
    'Microsoft.Net.Compilers' = $roslynCompilersVersion;
}

# Write out project file used to restore
& $projectTypeInfo.WriteFunc -ProjectFilePath $portableTargetsProject -TargetFrameworkVersions $frameworks -Packages $packages

# Now restore that project
Invoke-DotnetCommand -DotnetExePath $DotnetExePath -CommandArgs "restore $portableTargetsProject $initToolsRestoreArgs --packages $PackagesDirectory"

& robocopy (Join-Path $PackagesDirectory "Microsoft.Portable.Targets" | Join-Path -ChildPath $portableTargetsVersion | Join-Path -ChildPath "contentfiles\any\any\Extensions.") $ToolsLocalPath /E
& robocopy (Join-Path $PackagesDirectory "MicroBuild.Core" | Join-Path -ChildPath $microBuildVersion | Join-Path -ChildPath "build\.") $ToolsLocalPath /E

# Copy Roslyn Compilers Over to ToolRuntime
& robocopy (Join-Path $PackagesDirectory "Microsoft.Net.Compilers" | Join-Path -ChildPath $roslynCompilersVersion | Join-Path -ChildPath ".") (Join-Path $ToolsLocalPath "net46\roslyn\.") /E

# Override versions in runtimeconfig.json files with highest available runtime version.
$mncaFolder = (Join-Path (Get-Item $DotnetExePath).Directory.FullName "shared\Microsoft.NETCore.App")
$highestVersion = Get-ChildItem $mncaFolder -Name -Attributes !ReparsePoint | Sort-Object BaseName | Select-Object -First 1

foreach ($file in Get-ChildItem $ToolsLocalPath *.runtimeconfig.json)
{
    Write-Host "Correcting runtime version of" $file.FullName
    $text = (Get-Content $file.FullName) -replace "1.1.0","$highestVersion"
    Set-Content $file.FullName $text
}

# Make a directory in the root of the tools folder that matches the buildtools version, this is done so
# the init-tools.cmd (that is checked into each repository that uses buildtools) can write the semaphore
# marker into this file once tool initialization is complete.
New-Item -Force -Type Directory (Join-Path $ToolsLocalPath (Split-Path -Leaf (Split-Path $buildToolsPackageDirectory)))

exit 0