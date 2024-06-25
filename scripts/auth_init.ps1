#$tenantId = (Get-AzContext).Tenant.Id

# Login to your Azure account
#Connect-AzAccount -Tenant $tenantId

# hard coded localhost URL comes from startup properties of the web app
$localhostWebsiteRedirectUri = "https://localhost:7227/signin-oidc"
$azureWebsiteRedirectUri = "https://localhost:7227/signin-oidc"
$azureWebsiteLogoutUri = "https://localhost:7227/signout-oidc"

$frontendAppRegistrationName="FrontendApp-aoai-authn"
$apiAppRegistrationName="ApiApp-aoai-authn"
$API_SCOPE_NAME = "aoai.api"


    function Get-FrontendAppRegistration {
        param(
            [Parameter(Mandatory = $true)]
            [string]$AppRegistrationName,
            [Parameter(Mandatory = $true)]
            [string]$AzureWebsiteRedirectUri,
            [Parameter(Mandatory = $true)]
            [string]$AzureWebsiteLogoutUri,
            [Parameter(Mandatory = $true)]
            [string]$LocalhostWebsiteRedirectUri
        )
        
        # get an existing Front-end App Registration
        $frontendAppRegistration = Get-AzADApplication -DisplayName $AppRegistrationName -ErrorAction SilentlyContinue
    
        # if it doesn't exist, then return a new one we created
        if (!$frontendAppRegistration) {
              
    
            return New-FrontendAppRegistration `
                -AzureWebsiteRedirectUri $AzureWebsiteRedirectUri `
                -AzureWebsiteLogoutUri $AzureWebsiteLogoutUri `
                -LocalhostWebsiteRedirectUri $LocalhostWebsiteRedirectUri `
                -AppRegistrationName $AppRegistrationName
        }
    
       
        return $frontendAppRegistration
    }


    function New-FrontendAppRegistration {
        param(
            [Parameter(Mandatory = $true)]
            [string]$AppRegistrationName,
            [Parameter(Mandatory = $true)]
            [string]$AzureWebsiteRedirectUri,
            [Parameter(Mandatory = $true)]
            [string]$AzureWebsiteLogoutUri,
            [Parameter(Mandatory = $true)]
            [string]$LocalhostWebsiteRedirectUri
        )
        #TODO - to check the websiteApp object
        $websiteApp = @{
            "LogoutUrl" = $AzureWebsiteLogoutUri
            "RedirectUris" = @($AzureWebsiteRedirectUri, $LocalhostWebsiteRedirectUri)
            "ImplicitGrantSetting" = @{
                "EnableAccessTokenIssuance" = $false
                "EnableIdTokenIssuance" = $true
            }
        }
    
        write-host "`tCreating the front-end app registration'$AppRegistrationName' and '$websiteApp' "
        # create a Microsoft Entra ID App Registration for the front-end web app
        $frontendAppRegistration = New-AzADApplication `
            -DisplayName $AppRegistrationName `
            -SignInAudience "AzureADMyOrg" `
            -ErrorAction Stop
    
            
        return $frontendAppRegistration
    }


    # Get or Create the front-end app registration
$frontendAppRegistration = Get-FrontendAppRegistration `
-AzureWebsiteRedirectUri $azureWebsiteRedirectUri `
-AzureWebsiteLogoutUri $azureWebsiteLogoutUri `
-LocalhostWebsiteRedirectUri $localhostWebsiteRedirectUri `
-AppRegistrationName $frontendAppRegistrationName


 

function Get-ApiAppRegistration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppRegistrationName,
        [Parameter(Mandatory = $true)]
        [string]$ExistingAppRegistrationId
    )
    
    # get an existing Front-end App Registration
    $apiAppRegistration = Get-AzADApplication -DisplayName $AppRegistrationName -ErrorAction SilentlyContinue

    # if it doesn't exist, then return a new one we created
    if (!$apiAppRegistration) {
        
        return New-ApiAppRegistration `
            -AppRegistrationName $AppRegistrationName -ExistingAppRegistrationId $ExistingAppRegistrationId
    }

       return $apiAppRegistration
}

function New-ApiAppRegistration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppRegistrationName,
        [Parameter(Mandatory = $true)]
        [string]$ExistingAppRegistrationId
    )

    $delegatedPermissionId = (New-Guid).ToString()

    # Define the OAuth2 permissions (scopes) for the API
    # https://learn.microsoft.com/en-us/dotnet/api/microsoft.azure.powershell.cmdlets.resources.msgraph.models.apiv10.imicrosoftgraphapiapplication?view=az-ps-latest
    # typing is case sensitive on the following objects and properites
    $apiPermissions = [Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.IMicrosoftGraphApiApplication]@{
        Oauth2PermissionScope = [Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.IMicrosoftGraphPermissionScope[]]@(
            [Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.IMicrosoftGraphPermissionScope ]@{
                Id = $delegatedPermissionId
                Type = "User"
                AdminConsentDescription = "Allow the app to access the web API as a user"
                AdminConsentDisplayName = "Access the web API"
                IsEnabled = $true
                Value = $API_SCOPE_NAME
                UserConsentDescription = "Allow the app to access the web API on your behalf"
                UserConsentDisplayName = "Access the web API"
            })
        PreAuthorizedApplication = [Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.IMicrosoftGraphPreAuthorizedApplication[]]@(
            [Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.IMicrosoftGraphPreAuthorizedApplication]@{
                AppId = $ExistingAppRegistrationId
                DelegatedPermissionId = @($delegatedPermissionId)
            }
        )
    }
    
    # log the API permissions to console for debugging
    #Write-Host "`t`tAPI Permissions:"
    #Write-Host "`t`t`t$($apiPermissions | ConvertTo-Json -Depth 100)"

    # create a Microsoft Entra ID App Registration for the front-end web app
    $apiAppRegistration = New-AzADApplication `
        -DisplayName $AppRegistrationName `
        -SignInAudience "AzureADMyOrg" `
        -Api $apiPermissions `
        -ErrorAction Stop

    # set the identifier URI to the app ID (this is the default behavior)
    $apiAppRegistration.IdentifierUri = @("api://$($apiAppRegistration.AppId)")

    # save the change
    Update-AzADApplication -ObjectId $apiAppRegistration.Id -IdentifierUris $apiAppRegistration.IdentifierUri


    return $apiAppRegistration
}

   # Get or Create the api app registration
   $apiAppRegistration = Get-ApiAppRegistration `
   -AppRegistrationName $apiAppRegistrationName `
   -ExistingAppRegistrationId $frontendAppRegistration.AppId
   

$scopeDetails = $apiAppRegistration.Api.Oauth2PermissionScope | Where-Object { $_.Value -eq $API_SCOPE_NAME }
if (!$scopeDetails) {
    Write-Error "Unable to find the scope '$API_SCOPE_NAME' in the API app registration. Please check the API app registration in Microsoft Entra ID."
    exit 16
}

# Check permission for front-end app registration to verify it has access to the API app registration
$apiPermission = Get-AzADAppPermission -ObjectId $frontendAppRegistration.Id -ErrorAction SilentlyContinue | Where-Object { $_.ApiId -eq $apiAppRegistration.AppId -and $_.Type -eq 'Scope' }
if (!$apiPermission) {
    Write-Host "`tCreating the permission for the front-end app registration to access the API app registration"
    $apiPermission = Add-AzADAppPermission -ObjectId $frontendAppRegistration.Id -ApiId $apiAppRegistration.AppId -PermissionId $scopeDetails.Id -ErrorAction Stop
}
