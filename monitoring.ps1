# Input bindings are passed in via param block.
param($Timer)

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
function Invoke-HttpTest { 
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
        [Int]$Timeout = 10
    )


    try {
        ## If the test requires a proxy add the proxy address to the WebRequest
        if ($ProxyAddress) {
            $Response = Invoke-WebRequest -Uri $Address -Proxy $ProxyAddress -TimeoutSec $Timeout;
            $ProxyMessage = ",with proxy: [$ProxyAddress]"
        }
        else {
            $Response = Invoke-WebRequest -Uri $Address -TimeoutSec $Timeout;
        }

        $TestResult = $Response.StatusCode -eq $ResponseCode;
        ## Customise the TestResponse as the default message is `Microsoft Connect Test`.
        $script:TestResponse = "Web Request from the source [$($env:WEBSITE_PRIVATE_IP)] to the target: [${Address}] $ProxyMessage returned a status code: $($Response.StatusCode) with the description: $($Response.statusDescription)."

        return $TestResult
    }
    catch {

        ## If the function errors during execution, capture the exception
        $script:TestExecutionError = $($Error[0] -creplace '(?m)^\s*\r?\n', '')
        $script:TestResponse = "Web Request from the source [$($env:WEBSITE_PRIVATE_IP)] to the target: [${Address}] failed without a status code. Review the TestExecutionErrors."
        $TestResult = $False
        return $TestResult
    } 
}

function Invoke-TCPProbeTest { 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$TestName,

        [Parameter(Mandatory = $True)]
        [String]$Address,

        [Parameter(Mandatory = $True)]
        [String]$Port,

        [Parameter(Mandatory = $False)]
        [Int]$Timeout = 5
    )

    ## Set Defaults on Variables between executions
    $TestResult = $False

    
    try {
        $TestResult = Test-Connection -TargetName $Address -TcpPort $Port -TimeoutSeconds $Timeout

        ## Customise the TestResponse as the default message is `Microsoft Connect Test`.
        if($TestResult){
            $script:TestResponse = "TCP Probe from the source [$($env:WEBSITE_PRIVATE_IP)] to the target: [${Address}] on port: [${Port}] was successful."
        } else {
            $script:TestResponse = "TCP Probe from the source [$($env:WEBSITE_PRIVATE_IP)] to the target: [${Address}] on port: [${Port}] failed."
        }
        

        ## Return the result (True or False) back to the caller (Invoke-AppInsightsAvailabilityTest)
        return $TestResult

    }
    catch {
        
        ## If the function errors during execution, capture the exception
        $script:TestExecutionError = $($Error[0] -creplace '(?m)^\s*\r?\n', '')
        $script:TestResponse = "TCP Probe from the source [$($env:WEBSITE_PRIVATE_IP)] to the target: [${Address}] failed with execution errors. Review the TestExecutionErrors."

        ## Return the result (Truee or False) back to the caller (Invoke-AppInsightsAvailabilityTest)
        return $TestResult
    } 
}

function Invoke-DnsTest { 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$TestName,

        [Parameter(Mandatory = $True)]
        [String]$Address,

        [Parameter(Mandatory = $True)]
        [String]$DnsRecord,

        [Parameter(Mandatory = $False)]
        [String]$Timeout = 5

    )
    $TestResult = $False

    
    try {
        ## Third party DNS tool as PowerShell core doesn't have native DNS modules 
        $Test = Resolve-Dns $DnsRecord a -ns $Address -Timeout (New-Timespan -Sec $Timeout)
        
        if($Test.HasError){
            $script:TestResponse = "DNS lookup query from the source [$($env:WEBSITE_PRIVATE_IP)] sent to the DNS server [${Address}] to resolve the record: [${DnsRecord}] returned the error [$($Test.ErrorMessage)] ."
        } else {
            ## Customise the TestResponse payload
            $TestResult = $True
            $ResolvedAddress = $Test | Select-Object -Expand Answers | Select-Object -Expand Address
            $script:TestResponse = "DNS lookup query from the source [$($env:WEBSITE_PRIVATE_IP)] sent to the DNS server [${Address}] to resolve the record: [${DnsRecord}] returned the follow IPs: [$($ResolvedAddress.IPAddressToString)]."
        }

        ## Return the result (Truee or False) back to the caller (Invoke-AppInsightsAvailabilityTest)
        return $TestResult

    }
    catch {
        
        ## If the function errors during execution, capture the exception
        $script:TestExecutionError = $($Error[0] -creplace '(?m)^\s*\r?\n', '')
        $script:TestResponse = "DNS lookup query from the source [$($env:WEBSITE_PRIVATE_IP)] sent to the DNS server [${Address}] to resolve the record: [${DnsRecord}] failed. Review the TestExecutionErrors."

        ## Return the result (Truee or False) back to the caller (Invoke-AppInsightsAvailabilityTest)
        return $TestResult
    } 
}
function Invoke-AppInsightsAvailabilityTest {
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
        [String]$TestLocation = "PrivateFunction",

        [Parameter(Mandatory = $False)]
        [Int]$port,

        [Parameter(Mandatory = $False)]
        [String]$Description,

        [Parameter(Mandatory = $False)]
        [Object]$DnsRecord,

        [Parameter(Mandatory = $False)]
        [String]$Location


    )
   
    ## Define the Availability Test config
    $OperationId = (New-Guid).ToString("N");
    $Timeout = 5
    $OriginalErrorActionPreference = $ErrorActionPreference;
    $LogMessage = @{}
    $TestName = "${Location}-${TestName}"

    ## Create the Payload to send to App Insights
    $Availability = [Microsoft.ApplicationInsights.DataContracts.AvailabilityTelemetry]::new();
    $Availability.Id = $OperationId;
    $Availability.Name = $TestName;
    $Availability.RunLocation = $TestLocation;
    $Availability.Success = $False;
    
    ## Set Metdata on test objects
    $Availability.Properties.TestType = $TestType;
    $Availability.Properties.TestDescription = $Description;
    $Availability.Properties.Region = $env:REGION_NAME;
    $Availability.Properties.FunctionApp = $env:WEBSITE_Site_NAME;
    $Availability.Properties.FunctionName = $(Split-Path -Path $PSScriptRoot -Leaf);
    $Availability.Properties.SourceIP = $env:WEBSITE_PRIVATE_IP;
    $Availability.Properties.ResourceGroupName = $env:WEBSITE_RESOURCE_GROUP;
    $Availability.Properties.TestTarget = $Address;

    ## Start the Stopwatch to capture test duration
    $Stopwatch = [System.Diagnostics.Stopwatch]::New()
    $Stopwatch.Start();

    ## Reset Variables
    $script:TestExecutionError = ""
    $script:TestResponse = ""

    Try {
        $ErrorActionPreference = "Stop";
        $Result = $False

        switch ($TestType) {
            "http" { 
                $Result = Invoke-HttpTest -TestName $TestName -Address $Address -ProxyAddress $ProxyAddress -Timeout $Timeout
            }
            "tcpProbe" { 
                $Result = Invoke-TCPProbeTest -TestName $TestName -Address $Address -Port $Port -Timeout $Timeout
            }
            "dns" { 
                $Result = Invoke-DnsTest -TestName $TestName -Address $Address -DnsRecord $DnsRecord
            }
        }
        ## Hastable with the rest results
        $LogMessage += @{
            "TestName" = $TestName;
            "TestType" = $TestType;
            "Address"  = $Address;
            "Result"   = $Result;
        }

        if ($Result) {
            ## Based on the test results, update the success value
            $Availability.Success = $True;
        }

        $LogMessage += @{
            "TestResponse"       = $script:TestResponse;
            "TestExecutionError" = $script:TestExecutionError;
        }
        
        ## Write Log Message To Console
        Write-Output $( $LogMessage | ConvertTo-Json )

    }
    Catch {
        ## Capture Exception details
        $Availability.Message = $_.Exception.Message;
        $ExceptionTelemetry = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new($_.Exception);
        $ExceptionTelemetry.Context.Operation.Id = $OperationId;
        $ExceptionTelemetry.Properties["TestName"] = $TestName;
        $ExceptionTelemetry.Properties["TestLocation"] = $TestLocation;
        $ExceptionTelemetry.Properties["ExecutionError"] = $script:TestExecutionError;
        $TelemetryClient.TrackException($ExceptionTelemetry);
    }
    Finally {
        $Stopwatch.Stop();
        $Availability.Duration = $Stopwatch.Elapsed;
        $Availability.Timestamp = [DateTimeOffset]::UtcNow;
        $Availability.Properties.TestResponse = $script:TestResponse;
        $Availability.Properties.TestExecutionError = $script:TestExecutionError;
        
        # Capture Availability test results 
        $TelemetryClient.TrackAvailability($Availability);

        ## Publish stored telemetry to Application Insights
        # $TelemetryClient.Flush();
        $ErrorActionPreference = $OriginalErrorActionPreference;
    }
}

## Synopsis: The Script Starts Here
$TestFile = Get-Content "${PSScriptRoot}/monitoring.json" | ConvertFrom-Json
# $TestFile = Get-Content "monitoring.json" | ConvertFrom-Json

# Write-Output $TestFile
foreach ($TestTypesList in $TestFile.tests) {
    foreach ($Tests in $TestTypesList) {
        foreach ($Test in $Tests.tests) {
            Invoke-AppInsightsAvailabilityTest `
                -TestType $Tests.testType `
                -TestName $Test.name `
                -Address $Test.address `
                -ProxyAddress $Test.proxyAddress `
                -Port $Test.port `
                -Description $Test.description `
                -DnsRecord $Test.dnsRecord `
                -Location $TestFile.metadata.location
        }
    }
}


