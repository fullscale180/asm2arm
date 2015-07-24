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

    $parameterDefinition = @{'type' = $Type; 'metadata' = @{'description' = $Description}}

    if ($AllowedValues)
    {
        $parameterDefinition.Add('allowedValues', $AllowedValues)
    }

    if ($DefaultValue)
    {
        $parameterDefinition.Add('defaultValue', $DefaultValue)
    }

    return $parameterDefinition
  
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
        $Resources
    )

    $template = @{
        "name" = $Name;
        "type"=  $Type;
        "apiVersion" = $ApiVersion;
        "location" = $Location;
        "tags" = @{"deploymentReason" = $Global:deploymentTag;};
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

    return $template
}

function New-ArmTemplate 
{
    Param
    (
        $Version,
        $Parameters,
        $Variables,
        $Resources,
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

    return ConvertTo-Json $template -Depth 15
}

function New-ArmTemplateParameterFile 
{
    Param
    (
        [Hashtable]
        $ParametersList
    )

    $parameters = @{}
    foreach ($key in $parametersList.Keys)
    {
        $parameters.Add($key, @{'value' = $ParametersList[$key]})
    }

    return ConvertTo-Json $parameters -Depth 15
}

