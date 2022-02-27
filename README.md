<img src=".images/azurelogo-1.png" width="100" height="50" />

# Private Availability Tests - Azure App Insights

The code within this repository will execute private availability tests and publish the logs to Azure App Insights in the `Availability` panel. This is effectively synthetic checks for internal and external addresses.

## Usage

To use this repository, provision the code into an Azure function. To test private addresses or on-premise resources, you will need to ensure the network the Azure function is provisioned to has connectivity to those resources. As well as using a Premium App Service plan. As the other SKU's don't support provisioning a function into an internal vNet.

> *Note:* A premium function app does require a dedicated subnet. So plan accordingly.

## Availability Test Results

The results from this test are available in the `Availability` panel for the Application Insights attached to the function app executing this script.

![example-availability-test-results](.images/availabilitytest.png)

The data can also be queried through the Log Analytics workspace.

![log-analytics-query](.images/loganalytics-availability-query.png)

## Json Tests File

The tests are added into the `monitoring.json` file. The script reads this file then loops through each test.

*HTTP(s) Tests*:
```json
{
    "testType": "http",
    "tests": [
        {
            "name": "http-test-1",
            "address": "https://bing.com"
        },
        {
            "name": "http-test-2",
            "address": "https://bing.com",
            "proxyAddress": "https://proxyaddress:port"
        }
    ]
},
```

*Ldap Tests*:
```json
{
    "testType": "ldap",
    "tests": [
        {
            "name": "ldap-test-1",
            "address": "ldap://ldap.example.com:port"
        }
    ]
},
```

*DNS Tests*:
```json
{
    "testType": "dns",
    "tests": [
        {
            "name": "dns-test-1",
            "address": "www.bing.com"
        }
    ]
},
```

If you don't need a certain test type, leave the array empty.

## Limitations

- The frequency will be controlled via the function apps timer trigger, not within the individual tests.
- The requests execute once without a retry.
- All the test types must be present in the JSON file, even if they're unused.
- The script doesn't run on a local device.
- LDAP test type needs a connection timeout

## Documentation

- [Availability Azure Functions](https://docs.microsoft.com/en-us/azure/azure-monitor/app/availability-azure-functions)
