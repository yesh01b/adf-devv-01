param
(
    [parameter (Mandatory = $false)] [String] $rootFolder,
    [parameter (Mandatory = $false)] [String] $armTemplate,
    [parameter (Mandatory = $false)] [String] $ResourceGroupName,
    [parameter (Mandatory = $false)] [String] $DataFactoryName,
    [parameter(Mandatory = $false)] [Bool] $predeployment=$true,
    [parameter (Mandatory = $false)] [Bool] $deleteDeployment=$false
)

$templateJson = Get-Content $armTempLate | ConvertFrom-Json
$resources = $templateJson.resources

Install-Module -Name Az.DataFactory - Requiredversion 1.0.0 -Allowclobber -Force

#Triggers
Write-Host "Getting triggers"
$triggersADF = Get-AzDataFactoryV2Trigger -DataFactoryName $DataFactoryName - ResourceGroupName $ResourceGroupName
$triggersTemplate = $resources | where-object { $_.type -eq "Microsoft.DataFactory/factories/triggers" }
$triggerNames = $triggersTemplate | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}
$activeTriggernames = $triggersTemplate | where-object { $_.properties.runtimeState -eq "started" -and ($_.properties.pipelines.Count -gt 0 -or $_.properties.pipeline.pipelineReference -ne $null)} | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}
$deletedtriggers = $triggersADF | where-object { $triggerNames -notcontains $_.name }
$triggerstostop = $triggerNames | where { (triggersADF | Select-object name).name -contains $_ }

if ($predeployment -eq $true) {
    #Stop all triggers
    Write-Host "Stopping deployed triggers"
    $triggerstostop | ForEach-Object {
        Write-Host "Disabling trigger " $_
        Stop-AzDataFactoryV2Trigger -ResourceGroupname $ResourceGroupName -DataFactoryName $DataFactoryName -Name $_ -Force
    }
}
else {
    #Deleted resources
    #pipelines
    Write-Host "Getting pipelines"
    $pipelinesADF = Get-AzDataFactoryV2Trigger -DataFactoryName $DatafactoryName -ResourceGroupName $ResourceGroupName
    $pipelinesTemplate = $resources | where-object { $_.type -eq "Microsoft.DataFactory/Factories/pipelines" }
    $pipelineNames = $pipelinesTemplate | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}
    $deletedpipelines = $pipelinesADF | where-object { $pipelinesNames -notcontains $_.name }
    #datasets
    Write-Host "Getting datasets"
    $datasetsADF = Get-AzDataFactoryV2Dataset -DataFactoryName $DataFactoryName -ResourceGroupName $ResourceGroupName
    $datasetsTemplate = $resources | where-object { $_.type -eq "Microsoft.DataFactory/factories/datasets" }
    $datasetsNames = $datasetsTemplate | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}
    $deleteddataset = $datasetsADF | where-object { $datasetsNames -notcontains $_.name }
    #linkedservices
    Write-Host "Getting linked services"
    $linkedservicesADF = Get-AzDataFactoryV2linkedservice -DataFactoryName $DataFactoryName -ResourceGroupName $ResourceGroupName
    $linkedservicesTemplate = $resources | where-object { $_.type -eq "Microsoft.DataFactory/factories/linkedservices" }
    $linkedservicesNames = $linkedservicesTemplate | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}
    $deletedlinkedservices = $linkedservicesADF | where-object { $linkedservicesNames -notcontains $_.name }
    #IntegrationRuntimes
    Write-Host "Getting integration runtimes"
    $integrationruntimesADF = Get-AzDataFactoryV2integrationruntime -DataFactoryName $DataFactoryName -ResourceGroupName $ResourceGroupName
    $integrationruntimesTemplate = $resources | where-object { $_.type -eq "Microsoft.DataFactory/factories/integrationruntimes" }
    $integrationruntimesNames = $integrationruntimesTemplate | ForEach-Object {$_.name.Substring(37, $_.name.Length-40)}
    $deletedintegrationruntimes = $integrationruntimesADF | where-object { $integrationruntimesNames -notcontains $_.name }

    #Delete resources
    Write-Host "Deleting triggers"
    $deletedtriggers | ForEach-Object {
        Write-Host "Deleting trigger " $_.name
        $trig = Get-AzDataFactoryV2Trigger -name $_.name -ResourceGroupName $ResourceGroupName -DataFactoryname $DataFactoryName
        if ($trig.RuntimeState -eq "Started") {
            Stop-AzDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $_.name -Force
        }
        Remove-AzDataFactoryV2Trigger -Name $_.name -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Force
    }
    Write-Host "Deleting pipelines"
    $deletedpipelines | ForEach-Object {
        Write-Host "Deleting pipeline " $_.name
        Remove-AzDataFactoryV2pipeline -Name $_.name -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Force
    }
    Write-Host "Deleting datasets"
    $deleteddataset | ForEach-Object {
        Write-Host "Deleting dataset " $_.name
        Remove-AzDataFactoryV2dataset -Name $_.name -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Force
    }
    Write-Host "Deleting linked services"
    $deletedlinkedservices | ForEach-Object {
        Write-Host "Deleting Linked Service " $_.name
        Remove-AzDataFactoryV2linkedService -Name $_.name -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Force
    }
    Write-Host "Deleting integration runtimes"
    $deletedintegrationruntimes | ForEach-Object {
        Write-Host "Deleting integration runtime " $_.name
        Remove-AzDataFactoryV2IntegrationRuntime -Name $_.name -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Force
    }

    if ($deleteDeployment -eq $true) {
        Write-Host "Deleting ARM deployment ... under resoure group: " $ResourceGroupName
        $deployments = GetAzResourceGroupDeployment -ResourceGroupName $ResourceGroupName
        $deploymentsToConsider = $deployments | Where { $_.DeploymentName -like "ARMRemplate_master*" -or $_.DeploymentName -like "ARMTemplateForFactory*" } | Sort-object -Property Timestamp -Descending
        $deploymentName = $deploymentsToConsider[0].DeploymentName

        Write-Host "Deployment to be deleted: " $deploymentName
        $deploymentOperations = Get-AzResourceGroupDeploymentOperation -DeploymentName $deploymentName -ResourceGroupName $ResourceGroupName
        $deploymentsToDelete = $deploymentOperations | Where { $_.properties.targetResource.id -like "*Microsoft.Resource/deployments*" }

        $deploymentsToDelete | ForEach-Object {
            Write-Host "Deleting inner deployment: " $_.properties.targetResource.id
            Remove-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName
        }
        Write-Host "Deleting deployment: " $deploymentName
        Remove-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName
    }

    #Start Active Triggers - After cleanup efforts
    Write-Host "Starting active triggers"
    $activeTriggernames | ForEach-Object {
        Write-Host "Enabling trigger " $_
        Start-AzDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName $_ -Force
    }
}
