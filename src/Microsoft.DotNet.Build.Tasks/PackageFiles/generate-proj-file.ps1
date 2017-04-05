param
(
    [Parameter(Mandatory=$true)][string]$ProjectFilePath,
    [Parameter(Mandatory=$true)][array]$TargetFrameworkVersions,
    [Parameter(Mandatory=$true)][hashtable]$Packages,
    [Parameter(Mandatory=$false)][string]$FileFormat = "csproj",
    [switch]$Force = $false
)

function Write-Csproj([string] $TargetPath, [array] $TargetFrameworkVersions, [hashtable] $ToolPackages)
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
        $csprojWriter = New-Object System.Xml.XmlTextWriter($TargetPath, $null)
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
                foreach ($toolPackage in $ToolPackages.GetEnumerator())
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

function Write-ProjectJson ([string] $TargetPath, [array] $TargetFrameworkVersions, [hashtable] $ToolPackages)
{
    $targetFrameworks = ""
    foreach ($targetFrameworkVersion in $TargetFrameworkVersions)
    {
        $targetFrameworks = "`"$targetFrameworkVersion`": { }, "
    }
    $targetFrameworks = $targetFrameworks.TrimEnd(',', ' ')

    # create a project.json for the packages to restore
    $pjContent = "{ `"dependencies`": {"

    foreach ($toolPackage in $ToolPackages.GetEnumerator())
    {
        $pjContent = "$($pjContent)`"$($toolPackage.Key)`": `"$($toolPackage.Value)`","
    }
    $pjContent = $pjContent + "}, `"frameworks`": { $($targetFrameworks) } }"
    $pjContent | Out-File $TargetPath
}

Write-Host "Generating $ProjectFilePath"

switch ($FileFormat.ToLower())
{
    { ($_ -eq "csproj") } { Write-Csproj -TargetPath $ProjectFilePath -TargetFrameworkVersions $TargetFrameworkVersions -ToolPackages $Packages }
    { ($_ -eq "projectjson") } { Write-Csproj -TargetPath $ProjectFilePath -TargetFrameworkVersions $TargetFrameworkVersions -ToolPackages $Packages }
    default { throw "``$FileFormat`` is an unknown project file type." }
}

exit 0