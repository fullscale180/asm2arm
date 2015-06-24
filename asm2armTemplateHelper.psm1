
function New-ArmTemplateParameter
{
    Param
    (
        [ValidateSet("string", "securestring", "int", "bool", "array", "object")]
        $Type,
        $Description,
        [array]
        $AllowedValues,
        $DefaultValue
    )

    $parameterDefinition = @{'type' = $Type; 'metadata' = New-Object -TypeName PSCustomObject @{'description' = $Description}}

    if ($AllowedValues)
    {
        $parameterDefinition.Add('allowedValues', $AllowedValues)
    }

    if ($DefaultValue)
    {
        $parameterDefinition.Add('defaultValue', $DefaultValue)
    }

    return New-Object -TypeName PSCustomObject $parameterDefinition
  
}

function New-ResourceTemplate 
{
    Param
    (
        $Type,
        $Name,
        $ApiVersion,
        $Location,
        $Properties,
        [array]
        $DependsOn,
        [PSCustomObject]
        $Resources
    )

    $template = @{
        "name" = $Name;
        "type"=  $Type;
        "apiVersion" = $ApiVersion;
        "location" = $Location;
        "tags" = New-Object -TypeName PSCustomObject @{"deploymentReason" = "ARM";};
        "properties" = $Properties;
    }

    if ($Resources) 
    {
        $template.Add("resources", $Resources)
    }

    if ($DependsOn)
    {
        $template.Add("dependsOn", $DependsOn)
    }

    return New-Object -TypeName PSCustomObject $template
}

function New-ArmTemplate 
{
    Param
    (
        $Version,
        [PSCustomObject]
        $Parameters,
        [PSCustomObject]
        $Variables,
        [PSCustomObject[]]
        $Resources,
        [PSCustomObject[]]
        $Outputs
    )

    $template = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#';
        'parameters' = $Parameters;
        'resources' = $Resources;
    }

    if (-not $Version)
    {
        $Version = '1.0.0.0'
    }

    $template.Add('contentVersion', $Version)

    if ($Outputs) 
    {
        $template.Add("outputs", $Outputs)
    }

    if ($Variables)
    {
       $template.Add("variables", $Variables)
    }

    $templateObject = New-Object -TypeName PSCustomObject $template
    return ConvertTo-Json $templateObject -Depth 5
}

function New-ArmTemplateParameterFile 
{
    Param
    (
        [Hashtable]
        $ParametersList,
        [string]
        $Version = "1.0.0.0"
    )

    $template = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#';
        'contentVersion' = $Version
    }

    $parameters = @{}
    foreach ($key in $parametersList.Keys)
    {
        $parameters.Add($key, @{'value' = $ParametersList[$key]})
    }

    $template.Add('parameters', $parameters)

    $templateObject = New-Object -TypeName PSCustomObject $template
    return ConvertTo-Json $templateObject -Depth 5
}

