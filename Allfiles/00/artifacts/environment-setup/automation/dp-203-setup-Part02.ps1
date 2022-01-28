Set-ExecutionPolicy Unrestricted
			
cd C:\dp-203\data-engineering-ilt-deployment\Allfiles\00\artifacts\environment-setup\automation\


# Import modules
Import-Module "..\solliance-synapse-automation"

# Paths
$templatesPath = "..\templates"

# Add Values from the first setup script here

# User must sign in using az login
Write-Host "Sign into Azure using your credentials.."
az login

# Now sign in again for PowerShell resource management and select subscription
Write-Host "Now sign in again to allow this script to create resources..."
Connect-AzAccount

if(-not ([string]::IsNullOrEmpty($selectedSub)))
{
    Select-AzSubscription -SubscriptionId $selectedSub
}


Write-Information "Copy Data"
Write-Host "Uploading data to Azure..."

$dataLakeAccountName = "asadatalake$($suffix)"

Ensure-ValidTokens $true

if ([System.Environment]::OSVersion.Platform -eq "Unix")
{
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-linux"

        if (!$azCopyLink)
        {
                $azCopyLink = "https://azcopyvnext.azureedge.net/release20200709/azcopy_linux_amd64_10.5.0.tar.gz"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.tar.gz"
        tar -xf "azCopy.tar.gz"
        $azCopyCommand = (Get-ChildItem -Path ".\" -Recurse azcopy).Directory.FullName
        cd $azCopyCommand
        chmod +x azcopy
        cd ..
        $azCopyCommand += "\azcopy"
}
else
{
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-windows"

        if (!$azCopyLink)
        {
                $azCopyLink = "https://azcopyvnext.azureedge.net/release20200501/azcopy_windows_amd64_10.4.3.zip"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.zip"
        Expand-Archive "azCopy.zip" -DestinationPath ".\" -Force
        $azCopyCommand = (Get-ChildItem -Path ".\" -Recurse azcopy.exe).Directory.FullName
        $azCopyCommand += "\azcopy"
}

#$jobs = $(azcopy jobs list)

$download = $true;

$dataLakeStorageUrl = "https://"+ $dataLakeAccountName + ".dfs.core.windows.net/"
$dataLakeStorageBlobUrl = "https://"+ $dataLakeAccountName + ".blob.core.windows.net/"
$dataLakeStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $dataLakeAccountName)[0].Value
$dataLakeContext = New-AzStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey

$destinationSasKey = New-AzStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl

if ($download)
{
        Write-Information "Copying wwi-02 directory to the data lake..."
        $wwi02 = Resolve-Path "../../../../wwi-02"

        $dataDirectories = @{
                salesmall = "wwi-02,/sale-small/"
                analytics = "wwi-02,/campaign-analytics/"
                security = "wwi-02,/security/"
                salespoc = "wwi-02,/sale-poc/"
                datagenerators = "wwi-02,/data-generators/"
                profiles1 = "wwi-02,/online-user-profiles-01/"
                profiles2 = "wwi-02,/online-user-profiles-02/"
                customerinfo = "wwi-02,/customer-info/"
        }

        foreach ($dataDirectory in $dataDirectories.Keys) {

                $vals = $dataDirectories[$dataDirectory].tostring().split(",");

                $source = $wwi02.Path + $vals[1];

                $path = $vals[0];

                $destination = $dataLakeStorageBlobUrl + $path + $destinationSasKey
                Write-Information "Copying directory $($source) to $($destination)"
                & $azCopyCommand copy $source $destination --recursive=true
        }
}

Refresh-Tokens

Write-Information "Create SQL scripts"
Write-Host "Creating SQL scripts..."

$sqlScripts = [ordered]@{
        "Column Level Security" = "Column Level Security"
        "Dynamic Data Masking" = "Dynamic Data Masking"
        "Row Level Security" = "Row Level Security"
        "Data Warehouse Optimization" = "Data Warehouse Optimization"
}

foreach ($sqlScriptName in $sqlScripts.Keys) {
        
        $sqlScriptFileName = "$sqlScriptName.sql"
        Write-Information "Creating SQL script $($sqlScriptName) from $($sqlScriptFileName)"
        
        $result = Create-SQLScript -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $sqlScriptName -ScriptFileName $sqlScriptFileName
        $result = Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId
        $result
}


$SetupStep3Variables = "
# Values from the Second setup script here
`$dataLakeStorageAccountKey = `"$dataLakeStorageAccountKey`"
`$dataLakeAccountName = `"$dataLakeAccountName`"
"

((Get-Content -path .\dp-203-setup-Part03.ps1 -Raw) -replace '# Add Values from the second setup script here',"$SetupStep3Variables") | Set-Content -Path .\dp-203-setup-Part03.ps1

$SetupStep3Variables
