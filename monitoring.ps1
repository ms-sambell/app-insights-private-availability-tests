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
function appInsightsAvailabilityTest {
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
        # Check for the test type (http, ldap, dns)
        if($TestType -eq "http"){
            ## If the test requires a proxy add the proxy address to the WebRequest
            if($ProxyAddress){
                $Response = Invoke-WebRequest -Uri $Address -Proxy $ProxyAddress;
                $Success = $Response.StatusCode -eq $ResponseCode;
            } else {
                $Response = Invoke-WebRequest -Uri $Address;
                $Success = $Response.StatusCode -eq $ResponseCode;
            }
        } elseif ($TestType -eq "ldap") {
            ## Testing if the LDAP Address accepts a connection request
            $Connection = [ADSI]($Address)
            $Connection.Close()
            $Success = $True
        } elseif ($TestType -eq "dns") {
            ## Tests if the DNS server resolves
            $Response = Resolve-DnsName -Name $Address
            $Success = $True
        }
        
        ## Based on the test results, update the success value
        $Availability.Success = $Success;
    } Catch {
        # Submit Exception details to Application Insights
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
        # call flush to ensure telemetry is sent
        $TelemetryClient.Flush();
        $ErrorActionPreference = $OriginalErrorActionPreference;
    }
}

## Synopsis: The Script Starts Here
## `HttpTrigger1` is the name of my function
$testsFile = Get-Content "TimeTrigger1/monitoring.json" | ConvertFrom-Json

## Read the tests file and loop through each testType array
foreach($testTypesList in $testsFile.tests) {
    foreach($tests in $testTypesList) {
        foreach($test in $tests.tests){
            appInsightsAvailabilityTest -TestType $tests.testType `
                -TestName $test.name `
                -Address $test.address `
                -ProxyAddress $test.proxyAddress
        }
    }
}