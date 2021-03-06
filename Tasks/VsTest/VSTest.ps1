param(
    [string]$vsTestVersion, 
    [string]$testAssembly,
    [string]$testFiltercriteria,
    [string]$runSettingsFile,
    [string]$codeCoverageEnabled,
    [string]$pathtoCustomTestAdapters,
    [string]$overrideTestrunParameters,
    [string]$otherConsoleOptions,
    [string]$testRunTitle,
    [string]$platform,
    [string]$configuration,
    [string]$publishRunAttachments
)

    
Function CmdletHasMember($memberName) {
    $publishParameters = (gcm Publish-TestResults).Parameters.Keys.Contains($memberName) 
    return $publishParameters
}

Write-Verbose "Entering script VSTestConsole.ps1"

# Import the Task.Common and Task.Internal dll that has all the cmdlets we need for Build
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"
# Import the Task.TestResults dll that has the cmdlet we need for publishing results
import-module "Microsoft.TeamFoundation.DistributedTask.Task.TestResults"

if (!$testAssembly)
{
    Write-Host "##vso[task.logissue type=error;code=002001;]" 
    throw (Get-LocalizedString -Key "Test assembly parameter not set on script")
}

$sourcesDirectory = Get-TaskVariable -Context $distributedTaskContext -Name "Build.SourcesDirectory"
if(!$sourcesDirectory)
{
    # For RM, look for the test assemblies under the release directory.
    $sourcesDirectory = Get-TaskVariable -Context $distributedTaskContext -Name "Agent.ReleaseDirectory"
}

if(!$sourcesDirectory)
{
    # If there is still no sources directory, error out immediately.
    Write-Host "##vso[task.logissue type=error;code=002002;]"
    throw "No source directory found."
}

# check for solution pattern
if ($testAssembly.Contains("*") -or $testAssembly.Contains("?"))
{
    Write-Verbose "Pattern found in solution parameter. Calling Find-Files."
    Write-Verbose "Calling Find-Files with pattern: $testAssembly"    
    $testAssemblyFiles = Find-Files -SearchPattern $testAssembly -RootFolder $sourcesDirectory
    Write-Verbose "Found files: $testAssemblyFiles"
}
else
{
    Write-Verbose "No Pattern found in solution parameter."
    $testAssemblyFiles = ,$testAssembly
}

$codeCoverage = Convert-String $codeCoverageEnabled Boolean

if($testAssemblyFiles)
{
    Write-Verbose -Verbose "Calling Invoke-VSTest for all test assemblies"

    if($vsTestVersion -eq "latest")
    {
        # null out vsTestVersion before passing to cmdlet so it will default to the latest on the machine.
        $vsTestVersion = $null
    }

    $artifactsDirectory = Get-TaskVariable -Context $distributedTaskContext -Name "System.ArtifactsDirectory" -Global $FALSE

    $workingDirectory = $artifactsDirectory
    $testResultsDirectory = $workingDirectory + "\" + "TestResults"
    
    Invoke-VSTest -TestAssemblies $testAssemblyFiles -VSTestVersion $vsTestVersion -TestFiltercriteria $testFiltercriteria -RunSettingsFile $runSettingsFile -PathtoCustomTestAdapters $pathtoCustomTestAdapters -CodeCoverageEnabled $codeCoverage -OverrideTestrunParameters $overrideTestrunParameters -OtherConsoleOptions $otherConsoleOptions -WorkingFolder $workingDirectory -TestResultsFolder $testResultsDirectory -SourcesDirectory $sourcesDirectory

    $resultFiles = Find-Files -SearchPattern "*.trx" -RootFolder $testResultsDirectory 

    $publishResultsOption = Convert-String $publishRunAttachments Boolean

    if($resultFiles)
    {
        # Remove the below hack once the min agent version is updated to S91 or above
    
        $runTitleMemberExists = CmdletHasMember "RunTitle"
        $publishRunLevelAttachmentsExists = CmdletHasMember "PublishRunLevelAttachments"
        if($runTitleMemberExists)
        {
            if($publishRunLevelAttachmentsExists)
            {
                Publish-TestResults -Context $distributedTaskContext -TestResultsFiles $resultFiles -TestRunner "VSTest" -Platform $platform -Configuration $configuration -RunTitle $testRunTitle -PublishRunLevelAttachments $publishResultsOption
            }
            else
            {
                if(!$publishResultsOption)
                {
                    Write-Warning "Update the build agent to be able to opt out of test run attachment upload."
                }
                Publish-TestResults -Context $distributedTaskContext -TestResultsFiles $resultFiles -TestRunner "VSTest" -Platform $platform -Configuration $configuration -RunTitle $testRunTitle
            }
        }
        else
        {
	    if($testRunTitle)
	    {
		Write-Warning "Update the build agent to be able to use the custom run title feature."
	    }
            if($publishRunLevelAttachmentsExists)		
            {
                Publish-TestResults -Context $distributedTaskContext -TestResultsFiles $resultFiles -TestRunner "VSTest" -Platform $platform -Configuration $configuration -PublishRunLevelAttachments $publishResultsOption
            }
            else
            {
                if(!$publishResultsOption)
                {
                    Write-Warning "Update the build agent to be able to opt out of test run attachment upload."
                }
                Publish-TestResults -Context $distributedTaskContext -TestResultsFiles $resultFiles -TestRunner "VSTest" -Platform $platform -Configuration $configuration
            }		
        }
    }
    else
    {
        Write-Host "##vso[task.logissue type=warning;code=002003;]"
        Write-Warning "No results found to publish."
    }
    
}
else
{
    Write-Host "##vso[task.logissue type=warning;code=002004;]"
    Write-Warning "No test assemblies found matching the pattern: $testAssembly"
}

Write-Verbose "Leaving script VSTestConsole.ps1"