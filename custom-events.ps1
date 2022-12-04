## Setup App Insights SDK functionality
$Channel = [Microsoft.ApplicationInsights.Channel.InMemoryChannel]::new();
$EndpointAddress = "https://dc.services.visualstudio.com/v2/track";
$Channel.EndpointAddress = $EndpointAddress;
$TelemetryConfiguration = [Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration]::new(
    $Env:APPINSIGHTS_INSTRUMENTATIONKEY,  
    $Channel
);
$TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new($TelemetryConfiguration);

$json = @"
"event": "example",
"test": "yes"
"@

$TelemetryClient.TrackEvent($json)
$TelemetryClient.Flush()