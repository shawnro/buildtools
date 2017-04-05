param
(
    [Parameter(Mandatory=$false)][string]$RepositoryRoot = (Join-Path $PWD.Path "..\"),
    [Parameter(Mandatory=$false)][string]$ToolsLocalPath = (Join-Path $RepositoryRoot "Tools"),
    [Parameter(Mandatory=$false)][string]$CliLocalPath = (Join-Path $ToolsLocalPath "dotnetcli"),
    [Parameter(Mandatory=$false)][string]$SharedFrameworkSymlinkPath = (Join-Path $ToolsLocalPath "dotnetcli\shared\Microsoft.NETCore.App\version"),
    [Parameter(Mandatory=$false)][string]$SharedFrameworkVersion = "<auto>",
    [Parameter(Mandatory=$false)][string]$Architecture = "<auto>",
    [Parameter(Mandatory=$false)][string]$DotNetInstallBranch = "rel/1.0.0",
    [switch]$Force = $false,
    [switch]$Testing = $false
)


# function used for creating csproj files; these files are typically used for restoring packages with dotnet.exe
function Write-Csproj(
    [Parameter(Mandatory=$true)][string] $ProjectFilePath, 
    [Parameter(Mandatory=$true)][array] $TargetFrameworkVersions, 
    [Parameter(Mandatory=$true)][hashtable] $Packages
    )
{
    $targetFrameworkTag = "TargetFramework"
    if ($TargetFrameworkVersions.Length -gt 1)
    {
        $targetFrameworkTag = "$($targetFrameworkTag)s"
    }

    $targetFrameworks = ""
    foreach ($targetFrameworkVersion in $TargetFrameworkVersions)
    {
        $targetFrameworks = "$($targetFrameworkVersion);"
    }
    $targetFrameworks = $targetFrameworks.TrimEnd(';')
    
    # create a csproj for the packages to restore
    try
    {
        $csprojWriter = New-Object System.Xml.XmlTextWriter($ProjectFilePath, $null)
        $csprojWriter.Formatting = 'Indented'
        $csprojWriter.Indentation = 4

        $csprojWriter.WriteStartElement("Project")
        $csprojWriter.WriteAttributeString("Sdk", "Microsoft.NET.Sdk")

            $csprojWriter.WriteStartElement("PropertyGroup")
                $csprojWriter.WriteStartElement($targetFrameworkTag)
                $csprojWriter.WriteValue($targetFrameworks)
                $csprojWriter.WriteEndElement()
            $csprojWriter.WriteEndElement()

            $csprojWriter.WriteStartElement("ItemGroup")
                foreach ($toolPackage in $Packages.GetEnumerator())
                {
                    $csprojWriter.WriteStartElement("PackageReference")
                    $csprojWriter.WriteAttributeString("Include", $toolPackage.Key)
                    $csprojWriter.WriteAttributeString("Version", $toolPackage.Value)
                    $csprojWriter.WriteEndElement()
                }
            $csprojWriter.WriteEndElement()

        $csprojWriter.WriteEndElement()
        $csprojWriter.Flush()
    }
    finally
    {
        if ($csprojWriter -ne $null) 
        {
            $csprojWriter.Dispose()
        }
    }
}

# function used for creating project.json files; these files are typically used for restoring packages with dotnet.exe
function Write-ProjectJson (
    [Parameter(Mandatory=$true)][string] $ProjectFilePath, 
    [Parameter(Mandatory=$true)][array] $TargetFrameworkVersions, 
    [Parameter(Mandatory=$true)][hashtable] $Packages
    )
{
    $targetFrameworks = ""
    foreach ($targetFrameworkVersion in $TargetFrameworkVersions)
    {
        $targetFrameworks = "`"$targetFrameworkVersion`": { }, "
    }
    $targetFrameworks = $targetFrameworks.TrimEnd(',', ' ')

    # create a project.json for the packages to restore
    $pjContent = "{ `"dependencies`": {"

    foreach ($package in $Packages.GetEnumerator())
    {
        $pjContent = "$($pjContent)`"$($package.Key)`": `"$($package.Value)`","
    }
    $pjContent = $pjContent + "}, `"frameworks`": { $($targetFrameworks) } }"
    $pjContent | Out-File $ProjectFilePath
}


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

if (-Not $Testing)
{
    # blow away the tools directory so we can start from a known state
    if (Test-Path $ToolsLocalPath)
    {
        # if the bootstrap.ps1 script was downloaded to the tools directory don't delete it
        Remove-Item (Join-Path $ToolsLocalPath "*") -Recurse -Force -Exclude "bootstrap.ps1"
    }
    else
    {
        New-Item $ToolsLocalPath -ItemType Directory
    }

    # download CLI boot-strapper script
    Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/cli/$DotNetInstallBranch/scripts/obtain/dotnet-install.ps1" -OutFile $dotnetInstallPath
}
# load the version of the CLI
$rootCliVersion = Join-Path $RepositoryRoot ".cliversion"
$dotNetCliVersion = Get-Content $rootCliVersion

if (-Not (Test-Path $CliLocalPath))
{
    New-Item $CliLocalPath -ItemType Directory
}

if (-Not $Testing)
{
    # now execute the script
    Write-Host "$dotnetInstallPath -Version $dotNetCliVersion -InstallDir $CliLocalPath -Architecture ""$Architecture"""
    Invoke-Expression "$dotnetInstallPath -Version $dotNetCliVersion -InstallDir $CliLocalPath -Architecture ""$Architecture"""
    if ($LastExitCode -ne 0)
    {
        Write-Output "The .NET CLI installation failed with exit code $LastExitCode"
        exit $LastExitCode
    }

}

$tools = Get-Content $rootToolVersions
$packagesPath = Join-Path $RepositoryRoot "packages"
$dotNetExe = Join-Path $cliLocalPath "dotnet.exe"

if (-Not $Testing)
{
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
        New-Item $junctionParent -ItemType Directory
    }
    if (-Not (Test-Path $SharedFrameworkSymlinkPath))
    {
        New-Item -ItemType Junction -Path $SharedFrameworkSymlinkPath -Value $junctionTarget
    }


    $toolPackages = @{}
    foreach ($tool in $tools)
    {
        $name, $version = $tool.split("=")
        $toolPackages.Add($name, $version)
    }

    $projectFile = Join-Path $ToolsLocalPath "toolPackages.csproj"
    $script_genProjFile = (Join-Path $RepositoryRoot "src\Microsoft.DotNet.Build.Tasks\PackageFiles\generate-proj-file.ps1")
    Write-CsProj -ProjectFilePath $projectFile -TargetFrameworkVersions "netcoreapp1.0" -Packages $toolPackages
    # (Get-Command "Write-Csproj").Definition

    # Write-ProjectJson -TargetPath (Join-Path $ToolsLocalPath "project.json") -TargetFrameworkVersions "netcoreapp1.0" -ToolPackages $toolPackages

    # now restore the packages
    $buildToolsSource = "https://dotnet.myget.org/F/dotnet-buildtools/api/v3/index.json"
    $dotnetCoreSource = "https://dotnet.myget.org/F/dotnet-core/api/v3/index.json"
    $nugetOrgSource = "https://api.nuget.org/v3/index.json"
    if ($env:buildtools_source -ne $null)
    {
        $buildToolsSource = $env:buildtools_source
    }
    $restoreArgs = "restore $projectFile --packages $packagesPath --source $buildToolsSource --source $dotnetCoreSource --source $nugetOrgSource"
    $process = Start-Process -Wait -NoNewWindow -FilePath $dotNetExe -ArgumentList $restoreArgs -PassThru
    if ($process.ExitCode -ne 0)
    {
        exit $process.ExitCode
    }
}

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
        $destination = (Join-Path $ToolsLocalPath $name)
        if (-Not (Test-Path $destination)) 
        {
            New-Item $destination -ItemType Directory
            $exclude = $null
        }
        else 
        {
            $exclude = Get-ChildItem -Recurse $destination
        }

        Copy-Item (Join-Path $pkgVerPath "tools\*") $destination -Recurse -Exclude $exclude
    }
    elseif (Test-Path (Join-Path $pkgVerPath "lib"))
    {
        $exclude = Get-ChildItem -Recurse $ToolsLocalPath
        Copy-Item (Join-Path $pkgVerPath "lib\*") $ToolsLocalPath -Recurse -Exclude $exclude
    }
    if (Test-Path (Join-Path $pkgVerPath "lib\init-tools.cmd"))
    {
        # TODO: this is currently pulling from the checked in source directory and needs to be updated
        $script_initTools = (Join-Path $RepositoryRoot "src\Microsoft.DotNet.Build.Tasks\PackageFiles\init-tools.ps1")
        Invoke-Expression "$script_initTools -RepositoryRoot $RepositoryRoot -DotNetExe $dotNetExe -ToolsLocalPath $ToolsLocalPath -PackagesDirectory $(Join-Path $pkgVerPath "lib") | Out-File (Join-Path $RepositoryRoot ""Init-$name.log"")"
    }
}

# write semaphore file
Copy-Item $rootToolVersions $bootstrapComplete

