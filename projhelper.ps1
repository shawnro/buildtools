# global variables
$BuildToolsSource = "https://dotnet.myget.org/F/dotnet-buildtools/api/v3/index.json"
$DotnetCoreSource = "https://dotnet.myget.org/F/dotnet-core/api/v3/index.json"
$NugetOrgSource   = "https://api.nuget.org/v3/index.json"

function Get-ProjectTypeInfo(
    [Parameter(Mandatory=$true)][string]$DotnetExePath
)
{
    $projectTypeInfo = [PSCustomObject]@{
        Extension = ""
        PublishTfm = ""
        WriteFunc = ""
    }

    $cliVersion = & $DotnetExePath "--version"
    if ( ($cliVersion.Split(".")[0] -as [int]) -ge 2 )
    {
        Write-Host "Detected [$DotnetExePath] is a 2.0-capable CLI."

        $projectTypeInfo.Extension = "csproj"
        $projectTypeInfo.PublishTfm = "netcoreapp2.0"
        $projectTypeInfo.WriteFunc = "Write-CsProj"
    }
    else 
    {
        $projectTypeInfo.Extension = "json"
        $projectTypeInfo.PublishTfm = "netcoreapp1.0"
        $projectTypeInfo.WriteFunc = "Write-ProjectJson"
    }

    return $projectTypeInfo
}

# function used for invoking dotnet.exe commands
function Invoke-DotnetCommand(
    [Parameter(Mandatory=$true)][string]$DotnetExePath,
    [Parameter(Mandatory=$true)][string]$CommandArgs
    )
{
    $process = Start-Process -Wait -NoNewWindow -FilePath $DotnetExePath -ArgumentList $CommandArgs -PassThru
    if ($process.ExitCode -ne 0)
    {
        Write-Host "ERROR: An error occured when running: '""$DotnetExePath"" $CommandArgs'. Please check above for more details."
        exit $process.ExitCode
    }
}

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
