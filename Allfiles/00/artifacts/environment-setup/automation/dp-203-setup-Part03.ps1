Set-ExecutionPolicy Unrestricted
			
cd C:\dp-203\data-engineering-ilt-deployment\Allfiles\00\artifacts\environment-setup\automation\

# Import modules
Import-Module Az.CosmosDB
Import-Module "..\solliance-synapse-automation"

# Paths
$templatesPath = "..\templates"
$datasetsPath = "..\datasets"
$dataflowsPath = "..\dataflows"
$pipelinesPath = "..\pipelines"

# Add Values from the first setup script here

# Add Values from the second setup script here

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


$dataLakeContext = New-AzStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey

Refresh-Tokens

#
# =============== COSMOS DB IMPORT - MUST REMAIN LAST IN SCRIPT !!! ====================
#            

$cosmosDbAccountName = "asacosmosdb$($suffix)"
$cosmosDbDatabase = "CustomerProfile"
$cosmosDbContainer = "OnlineUserProfile01"

Write-Host "Loading Cosmos DB..."             

$download = $true;

#generate new one just in case...
$destinationSasKey = New-AzStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl

Write-Information "Counting Cosmos DB item in database $($cosmosDbDatabase), container $($cosmosDbContainer)"
$documentCount = Count-CosmosDbDocuments -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -CosmosDbAccountName $cosmosDbAccountName `
                -CosmosDbDatabase $cosmosDbDatabase -CosmosDbContainer $cosmosDbContainer

Write-Information "Found $documentCount in Cosmos DB container $($cosmosDbContainer)"

#Install-Module -Name Az.CosmosDB

if ($documentCount -ne 100000) 
{
        # Increase RUs in CosmosDB container
        Write-Information "Increase Cosmos DB container $($cosmosDbContainer) to 400 RUs"

        $container = Get-AzCosmosDBSqlContainer `
                -ResourceGroupName $resourceGroupName `
                -AccountName $cosmosDbAccountName -DatabaseName $cosmosDbDatabase `
                -Name $cosmosDbContainer

        Update-AzCosmosDBSqlContainer -ResourceGroupName $resourceGroupName `
                -AccountName $cosmosDbAccountName -DatabaseName $cosmosDbDatabase `
                -Name $cosmosDbContainer -Throughput 400 `
                -PartitionKeyKind $container.Resource.PartitionKey.Kind `
                -PartitionKeyPath $container.Resource.PartitionKey.Paths

        $name = "wwi02_online_user_profiles_01_adal"
        Write-Information "Create dataset $($name)"
        $result = Create-Dataset -DatasetsPath $datasetsPath -WorkspaceName $workspaceName -Name $name -LinkedServiceName $dataLakeAccountName
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        Write-Information "Create Cosmos DB linked service $($cosmosDbAccountName)"
        $cosmosDbAccountKey = List-CosmosDBKeys -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -Name $cosmosDbAccountName
        $result = Create-CosmosDBLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $cosmosDbAccountName -Database $cosmosDbDatabase -Key $cosmosDbAccountKey
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        $name = "customer_profile_cosmosdb"
        Write-Information "Create dataset $($name)"
        $result = Create-Dataset -DatasetsPath $datasetsPath -WorkspaceName $workspaceName -Name $name -LinkedServiceName $cosmosDbAccountName
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        $name = "Setup - Import User Profile Data into Cosmos DB"
        $fileName = "import_customer_profiles_into_cosmosdb"
        Write-Information "Create pipeline $($name)"
        Write-Host "Running pipeline..."
        $result = Create-Pipeline -PipelinesPath $pipelinesPath -WorkspaceName $workspaceName -Name $name -FileName $fileName
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        Write-Information "Running pipeline $($name)"
        $pipelineRunResult = Run-Pipeline -WorkspaceName $workspaceName -Name $name
        $result = Wait-ForPipelineRun -WorkspaceName $workspaceName -RunId $pipelineRunResult.runId
        $result

        #
        # =============== WAIT HERE FOR PIPELINE TO FINISH - MIGHT TAKE ~45 MINUTES ====================
        #                         
        #                    COPY 100000 records to CosmosDB ==> SELECT VALUE COUNT(1) FROM C
        #

        $name = "Setup - Import User Profile Data into Cosmos DB"
        Write-Information "Delete pipeline $($name)"
        $result = Delete-ASAObject -WorkspaceName $workspaceName -Category "pipelines" -Name $name
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        $name = "customer_profile_cosmosdb"
        Write-Information "Delete dataset $($name)"
        $result = Delete-ASAObject -WorkspaceName $workspaceName -Category "datasets" -Name $name
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        $name = "wwi02_online_user_profiles_01_adal"
        Write-Information "Delete dataset $($name)"
        $result = Delete-ASAObject -WorkspaceName $workspaceName -Category "datasets" -Name $name
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

        $name = $cosmosDbAccountName
        Write-Information "Delete linked service $($name)"
        $result = Delete-ASAObject -WorkspaceName $workspaceName -Category "linkedServices" -Name $name
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId
}

$container = Get-AzCosmosDBSqlContainer `
        -ResourceGroupName $resourceGroupName `
        -AccountName $cosmosDbAccountName -DatabaseName $cosmosDbDatabase `
        -Name $cosmosDbContainer

Update-AzCosmosDBSqlContainer -ResourceGroupName $resourceGroupName `
        -AccountName $cosmosDbAccountName -DatabaseName $cosmosDbDatabase `
        -Name $cosmosDbContainer -Throughput 400 `
        -PartitionKeyKind $container.Resource.PartitionKey.Kind `
        -PartitionKeyPath $container.Resource.PartitionKey.Paths

Write-Host "Setup complete!"
