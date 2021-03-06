function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SSA",
            "SPSite",
            "SPWeb")]
        [System.String]
        $ScopeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ScopeUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SearchServiceAppName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Query,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ProviderType,

        [Parameter()]
        [System.String]
        $ConnectionUrl,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Getting search result source '$Name'"

    $result = Invoke-SPDscCommand -Credential $InstallAccount `
        -Arguments $PSBoundParameters `
        -ScriptBlock {
        $params = $args[0]
        [void] [Reflection.Assembly]::LoadWithPartialName("Microsoft.Office.Server.Search")

        $nullReturn = @{
            Name                 = $params.Name
            ScopeName            = $params.ScopeName
            SearchServiceAppName = $params.SearchServiceAppName
            Query                = $null
            ProviderType         = $null
            ConnectionUrl        = $null
            ScopeUrl             = $null
            Ensure               = "Absent"
        }
        $serviceApp = Get-SPEnterpriseSearchServiceApplication -Identity $params.SearchServiceAppName
        if ($null -eq $serviceApp)
        {
            Write-Verbose -Message ("Specified Search service application $($params.SearchServiceAppName)" + `
                    "does not exist.")
            return $nullReturn
        }

        $fedManager = New-Object Microsoft.Office.Server.Search.Administration.Query.FederationManager($serviceApp)
        $providers = $fedManager.ListProviders()
        if ($providers.Keys -notcontains $params.ProviderType)
        {
            Write-Verbose -Message ("Unknown ProviderType ($($params.ProviderType)) is used. Allowed " + `
                    "values are: '" + ($providers.Keys -join "', '") + "'")
            return $nullReturn
        }

        $searchOwner = $null
        if ("ssa" -eq $params.ScopeName.ToLower())
        {
            $searchOwner = Get-SPEnterpriseSearchOwner -Level SSA
        }
        else
        {
            $searchOwner = Get-SPEnterpriseSearchOwner -Level $params.ScopeName -SPWeb $params.ScopeUrl
        }
        $filter = New-Object Microsoft.Office.Server.Search.Administration.SearchObjectFilter($searchOwner)
        $filter.IncludeHigherLevel = $true

        $source = $fedManager.ListSources($filter, $true) | Where-Object -FilterScript {
            $_.Name -eq $params.Name
        }

        if ($null -ne $source)
        {
            $providers = $fedManager.ListProviders()
            $provider = $providers.Values | Where-Object -FilterScript {
                $_.Id -eq $source.ProviderId
            }
            return @{
                Name                 = $params.Name
                ScopeName            = $params.ScopeName
                SearchServiceAppName = $params.SearchServiceAppName
                Query                = $source.QueryTransform.QueryTemplate
                ProviderType         = $provider.DisplayName
                ConnectionUrl        = $source.ConnectionUrlTemplate
                ScopeUrl             = $params.ScopeUrl
                Ensure               = "Present"
            }
        }
        else
        {
            return $nullReturn
        }
    }
    return $result
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SSA",
            "SPSite",
            "SPWeb")]
        [System.String]
        $ScopeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ScopeUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SearchServiceAppName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Query,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ProviderType,

        [Parameter()]
        [System.String]
        $ConnectionUrl,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Setting search result source '$Name'"

    $CurrentValues = Get-TargetResource @PSBoundParameters

    if ($CurrentValues.Ensure -eq "Absent" -and $Ensure -eq "Present")
    {
        Write-Verbose -Message "Creating search result source $Name"
        Invoke-SPDscCommand -Credential $InstallAccount `
            -Arguments @($PSBoundParameters, $MyInvocation.MyCommand.Source) `
            -ScriptBlock {
            $params = $args[0]
            $eventSource = $args[1]

            [void] [Reflection.Assembly]::LoadWithPartialName("Microsoft.Office.Server.Search")

            $serviceApp = Get-SPEnterpriseSearchServiceApplication `
                -Identity $params.SearchServiceAppName
            if ($null -eq $serviceApp)
            {
                $message = ("Specified Search service application $($params.SearchServiceAppName)" + `
                        "does not exist.")
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            $fedManager = New-Object Microsoft.Office.Server.Search.Administration.Query.FederationManager($serviceApp)
            $providers = $fedManager.ListProviders()
            if ($providers.Keys -notcontains $params.ProviderType)
            {
                $message = ("Unknown ProviderType ($($params.ProviderType)) is used. Allowed " + `
                        "values are: '" + ($providers.Keys -join "', '") + "'")
                Add-SPDscEvent -Message $message `
                    -EntryType 'Error' `
                    -EventID 100 `
                    -Source $eventSource
                throw $message
            }

            $searchOwner = $null
            if ("ssa" -eq $params.ScopeName.ToLower())
            {
                $searchOwner = Get-SPEnterpriseSearchOwner -Level SSA
            }
            else
            {
                $searchOwner = Get-SPEnterpriseSearchOwner -Level $params.ScopeName -SPWeb $params.ScopeUrl
            }

            $transformType = "Microsoft.Office.Server.Search.Query.Rules.QueryTransformProperties"
            $queryProperties = New-Object -TypeName $transformType
            $resultSource = $fedManager.CreateSource($searchOwner)

            $resultSource.Name = $params.Name
            $providers = $fedManager.ListProviders()
            $provider = $providers.Values | Where-Object -FilterScript {
                $_.DisplayName -eq $params.ProviderType
            }
            $resultSource.ProviderId = $provider.Id
            $resultSource.CreateQueryTransform($queryProperties, $params.Query)
            if ($params.ContainsKey("ConnectionUrl") -eq $true)
            {
                $resultSource.ConnectionUrlTemplate = $params.ConnectionUrl
            }
            $resultSource.Commit()
        }
    }

    if ($Ensure -eq "Absent")
    {
        Write-Verbose -Message "Removing search result source $Name"
        Invoke-SPDscCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
            $params = $args[0]
            [void] [Reflection.Assembly]::LoadWithPartialName("Microsoft.Office.Server.Search")

            $serviceApp = Get-SPEnterpriseSearchServiceApplication `
                -Identity $params.SearchServiceAppName

            $fedManager = New-Object Microsoft.Office.Server.Search.Administration.Query.FederationManager($serviceApp)
            $searchOwner = $null
            if ("ssa" -eq $params.ScopeName.ToLower())
            {
                $searchOwner = Get-SPEnterpriseSearchOwner -Level SSA
            }
            else
            {
                $searchOwner = Get-SPEnterpriseSearchOwner -Level $params.ScopeName -SPWeb $params.ScopeUrl
            }

            $source = $fedManager.GetSourceByName($params.Name, $searchOwner)
            if ($null -ne $source)
            {
                $fedManager.RemoveSource($source)
            }
        }
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SSA",
            "SPSite",
            "SPWeb")]
        [System.String]
        $ScopeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ScopeUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SearchServiceAppName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Query,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ProviderType,

        [Parameter()]
        [System.String]
        $ConnectionUrl,

        [Parameter()]
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [Parameter()]
        [System.Management.Automation.PSCredential]
        $InstallAccount
    )

    Write-Verbose -Message "Testing search result source '$Name'"

    $PSBoundParameters.Ensure = $Ensure

    $CurrentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message "Current Values: $(Convert-SPDscHashtableToString -Hashtable $CurrentValues)"
    Write-Verbose -Message "Target Values: $(Convert-SPDscHashtableToString -Hashtable $PSBoundParameters)"

    $result = Test-SPDscParameterState -CurrentValues $CurrentValues `
        -Source $($MyInvocation.MyCommand.Source) `
        -DesiredValues $PSBoundParameters `
        -ValuesToCheck @("Ensure")

    Write-Verbose -Message "Test-TargetResource returned $result"

    return $result
}

Export-ModuleMember -Function *-TargetResource
