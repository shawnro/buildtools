<<<<<<< HEAD
 param (
    [Parameter(Mandatory=$true)][string]$ToolRuntimePath,
    [Parameter(Mandatory=$true)][string]$DotnetCmd
 )

# Override versions in runtimeconfig.json files with highest available runtime version.
$mncaFolder = (Get-Item $DotnetCmd).Directory.FullName + "\shared\Microsoft.NETCore.App"
$highestVersion = Get-ChildItem $mncaFolder -Name | Sort-Object BaseName | Select-Object -First 1

foreach ($file in Get-ChildItem $ToolRuntimePath *.runtimeconfig.json)
{
    Write-Host "Correcting runtime version of" $file.FullName
    $text = (Get-Content $file.FullName) -replace "1.1.0","$highestVersion"
    Set-Content $file.FullName $text
}
=======
param
(
    [Parameter(Mandatory=$true)][string]$RepositoryRoot,
    [Parameter(Mandatory=$true)][string]$DotNetExe,
    [Parameter(Mandatory=$true)][string]$ToolsLocalPath,
    [Parameter(Mandatory=$false)][string]$PackagesDirectory = $ToolsLocalPath,
    [switch]$Force = $false
)

$buildToolsTargetRuntime = $env:BUILDTOOLS_TARGET_RUNTIME
$buildToolsNet46TargetRuntime = $env:BUILDTOOLS_NET46_TARGET_RUNTIME

if ($buildToolsTargetRuntime -eq $null)
{
    $buildToolsTargetRuntime = "win7-x64"
}

if ($buildToolsNet46TargetRuntime -eq $null)
{
    $buildToolsNet46TargetRuntime = "win7-x86"
}

$buildToolsPackageDirectory = $PSScriptRoot

# TODO: these shouldn't be hard coded
$microBuildVersion = "0.2.0"
$portableTargetsVersion = "0.1.1-dev"
$roslynCompilersVersion = "2.0.0-rc"
$buildToolsSource = "https://dotnet.myget.org/F/dotnet-buildtools/api/v3/index.json"
$dotnetCoreSource = "https://dotnet.myget.org/F/dotnet-core/api/v3/index.json"
$nugetOrgSource = "https://api.nuget.org/v3/index.json"

$initToolsRestoreArgs = "--source $buildToolsSource --source $nugetOrgSource"
$toolRuntimeRestoreArgs = "--source $dotnetCoreSource $initToolsRestoreArgs"

if (-Not (Test-Path $RepositoryRoot))
{
    Write-Host "ERROR: Cannot find project root path at [$RepositoryRoot]."
    exit 1
}

if (-Not (Test-Path $DotNetExe))
{
    Write-Host "ERROR: Cannot find dotnet cli at [$DotNetExe]."
    exit 1
}

# TODO: Why is this here? We do this same copy in bootstrap.ps1
$exclude = Get-ChildItem -Recurse $ToolsLocalPath
Copy-Item (Join-Path $PackagesDirectory "*") $ToolsLocalPath -Recurse -Exclude $exclude

# TODO: this is currently pulling from the checked in source directory and needs to be updated
$projectFile = (Join-Path $RepositoryRoot "src\Microsoft.DotNet.Build.Tasks\PackageFiles\tool-runtime\tool-runtime.csproj")
$restoreArgs = "restore $projectFile $toolRuntimeRestoreArgs"
$process = Start-Process -Wait -NoNewWindow -FilePath $DotNetExe -ArgumentList $restoreArgs -PassThru
if ($process.ExitCode -ne 0)
{
    exit $process.ExitCode
}

$publishArgs = "publish $projectFile -f netcoreapp1.0 -r $buildToolsTargetRuntime -o $ToolsLocalPath"
$process = Start-Process -Wait -NoNewWindow -FilePath $DotNetExe -ArgumentList $publishArgs -PassThru
if ($process.ExitCode -ne 0)
{
    exit $process.ExitCode
}

$publishArgs = "publish $projectFile -f net46 -r $buildToolsNet46TargetRuntime -o $(Join-Path $ToolsLocalPath "net46")"
$process = Start-Process -Wait -NoNewWindow -FilePath $DotNetExe -ArgumentList $publishArgs -PassThru
if ($process.ExitCode -ne 0)
{
    exit $process.ExitCode
}

# Microsoft.Build.Runtime dependency is causing the MSBuild.runtimeconfig.json buildtools copy to be overwritten - re-copy the buildtools version.
# Robocopy "%BUILDTOOLS_PACKAGE_DIR%\." "%TOOLRUNTIME_DIR%\." "MSBuild.runtimeconfig.json"

# Copy Portable Targets Over to ToolRuntime
$generatedPackagesDirectory = (Join-Path $PackagesDirectory "generated")
if (-Not (Test-Path $generatedPackagesDirectory))
{
    New-Item $generatedPackagesDirectory -ItemType Directory
}

$portableTargetsProjectFile = (Join-Path $generatedPackagesDirectory "portableTargets.csproj")

$frameworks = "netcoreapp1.0", "net46";

$packages = @{
    'MicroBuild.Core' = $microBuildVersion;
    'Microsoft.Portable.Targets' = $portableTargetsVersion;
    'Microsoft.Net.Compilers' = $roslynCompilersVersion;
}

# if Write-Csproj exists as a function, call it directly; otherwise invoke it through external script
if (Get-Command "Write-Csproj")
{
    Write-Csproj -ProjectFilePath $portableTargetsProjectFile -TargetFrameworkVersions $frameworks -Packages $packages
}
else 
{
    # TODO: this is currently pulling from the checked in source directory and needs to be updated
    $script_genProjFile = (Join-Path $RepositoryRoot "src\Microsoft.DotNet.Build.Tasks\PackageFiles\generate-proj-file.ps1")
    Invoke-Expression "$script_genProjFile -FileFormat csproj -ProjectFilePath $portableTargetsProjectFile -TargetFrameworkVersions `$frameworks -Packages `$packages"
}

$restoreArgs = "restore $portableTargetsProjectFile $initToolsRestoreArgs --packages $PackagesDirectory"
$process = Start-Process -Wait -NoNewWindow -FilePath $DotNetExe -ArgumentList $restoreArgs -PassThru
if ($process.ExitCode -ne 0)
{
    exit $process.ExitCode
}

Copy-Item (Join-Path $PackagesDirectory "Microsoft.Portable.Targets" | Join-Path -ChildPath $portableTargetsVersion | Join-Path -ChildPath "contentfiles\any\any\Extensions\*") $ToolsLocalPath -Recurse -Exclude $exclude
Copy-Item (Join-Path $PackagesDirectory "MicroBuild.Core" | Join-Path -ChildPath $microBuildVersion | Join-Path -ChildPath "build\*") $ToolsLocalPath -Recurse -Exclude $exclude

# Copy Roslyn Compilers Over to ToolRuntime
$compilersDirectory = (Join-Path $ToolsLocalPath "net46\roslyn")
if (-Not (Test-Path $compilersDirectory))
{
    New-Item $compilersDirectory -ItemType Directory
}
Copy-Item (Join-Path $PackagesDirectory "Microsoft.Net.Compilers" | Join-Path -ChildPath $roslynCompilersVersion | Join-Path -ChildPath "*") $compilersDirectory -Recurse

exit 0
>>>>>>> a421df01a4747b4b3ecb382c17f343460d2ac2ef
