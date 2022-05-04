## Setup App Insights SDK functionality
$Channel = [Microsoft.ApplicationInsights.Channel.InMemoryChannel]::new();
$EndpointAddress = "https://dc.services.visualstudio.com/v2/track";
$Channel.EndpointAddress = $EndpointAddress;
$TelemetryConfiguration = [Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration]::new(
    $Env:APPINSIGHTS_INSTRUMENTATIONKEY,  
    $Channel
);
$TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new($TelemetryConfiguration);

## Defining Reusable code as function
function HttpTest { 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$TestName,

        [Parameter(Mandatory = $True)]
        [String]$Address,

        [Parameter(Mandatory = $False)]
        [String]$ProxyAddress,

        [Parameter(Mandatory = $False)]
        [Int]$ResponseCode = 200,

        [Parameter(Mandatory = $False)]
        [Int]$Timeout = 30
    )

    ## Setting the Results to False by default
    $TestResult = $False
    try {
        # Write-Output "inside http requ func"
        ## If the test requires a proxy add the proxy address to the WebRequest
        if($ProxyAddress){
            $Response = Invoke-WebRequest -Uri $Address -Proxy $ProxyAddress -TimeoutSec $Timeout;
            write-output $Response
            $TestResult = $Response.StatusCode -eq $ResponseCode;
        } else {
            $Response = Invoke-WebRequest -Uri $Address -TimeoutSec $Timeout;
            write-output $Response
            $TestResult = $Response.StatusCode -eq $ResponseCode;
        }

        return $TestResult
    } catch {
        return $TestResult
    } 
    
    
    
}
function AppInsightsAvailabilityTest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$TestName,

        [Parameter(Mandatory = $True)]
        [String]$Address,

        [Parameter(Mandatory = $True)]
        [String]$TestType,

        [Parameter(Mandatory = $False)]
        [String]$ProxyAddress,

        [Parameter(Mandatory = $False)]
        [String]$ResponseCode = 200,

        [Parameter(Mandatory = $False)]
        [String]$TestLocation = "PrivateFunction"
    )
   
    ## Define the Availability Test config
    $OperationId = (New-Guid).ToString("N");
    $Timeout = 10
    $OriginalErrorActionPreference = $ErrorActionPreference;

    ## Create the Payload to send to App Insights
    $Availability = [Microsoft.ApplicationInsights.DataContracts.AvailabilityTelemetry]::new();
    $Availability.Id = $OperationId;
    $Availability.Name = $TestName;
    $Availability.RunLocation = $TestLocation;
    $Availability.Success = $False;
    
    ## Start the Stopwatch to capture test duration
    $Stopwatch = [System.Diagnostics.Stopwatch]::New()
    $Stopwatch.Start();

    Try {
        $ErrorActionPreference = "Stop";
        $Result = $False

        switch ($TestType) {
            "http" { 
                Write-Output "http selected" 
                $Result = HttpTest -TestName $TestName -Address $Address -ProxyAddress $ProxyAddress -Timeout $Timeout
            }
            "ldap" { 
                Write-Output "ldap selected" 
            }
            "dns" { 
                Write-Output "dns selected"
            }
        }

        if($Result){
            Write-Output $TestName
            Write-Output "true"
        } else {
            Write-Output $TestName
            Write-Output "false"
        }
        
        ## Based on the test results, update the success value
        $Availability.Success = $Success;
    } Catch {
        ## Submit Exception details to Application Insights
        $Availability.Message = $_.Exception.Message;
        $ExceptionTelemetry = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new($_.Exception);
        $ExceptionTelemetry.Context.Operation.Id = $OperationId;
        $ExceptionTelemetry.Properties["TestName"] = $TestName;
        $ExceptionTelemetry.Properties["TestLocation"] = $TestLocation;
        $TelemetryClient.TrackException($ExceptionTelemetry);
    } Finally {
        $Stopwatch.Stop();
        $Availability.Duration = $Stopwatch.Elapsed;
        $Availability.Timestamp = [DateTimeOffset]::UtcNow;
        
        # Submit Availability details to Application Insights
        $TelemetryClient.TrackAvailability($Availability);
        # Flush to ensure telemetry is sent
        # $TelemetryClient.Flush();
        $ErrorActionPreference = $OriginalErrorActionPreference;
    }
}




## Synopsis: The Script Starts Here
$testsFile = Get-Content "${PSScriptRoot}/monitoring.json" | ConvertFrom-Json
# $testsFile = Get-Content "monitoring.json" | ConvertFrom-Json


$funcDef = $function:AppInsightsAvailabilityTest.ToString()
$httpFunction = $function:HttpTest.ToString()
$appInsightsFunction = $function:TelemetryClient.ToString()

foreach ($testTypesList in $testsFile.tests) {
    foreach ($tests in $testTypesList) {
        $tests.tests | ForEach-Object -Parallel {

            ## Define the function inside this thread.
            $function:AppInsightsAvailabilityTest = $using:funcDef
            $function:HttpTest = $using:httpFunction
            $function:TelemetryClient = $using:appInsightsFunction
           
            AppInsightsAvailabilityTest -TestType $($using:tests.testType) `
                -TestName $_.name `
                -Address $_.address `
                -ProxyAddress $_.proxyAddress
        }

        ## Flush the results after each test type
        $TelemetryClient.Flush();
    }
}

 

# test
