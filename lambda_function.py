import urllib3
import os
import boto3
import json

def lambda_handler(event, context):
    # Short timeout for the check
    http = urllib3.PoolManager(timeout=2.0)
    cloudwatch = boto3.client('cloudwatch')

    # Retrieve URLs to check from environment variables
    check_urls = json.loads(os.environ.get('CHECK_URLS', '[]'))

    if not check_urls:
        print("ERROR: No check URLs configured")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'No check URLs configured'})
        }

    # Execute checks on all configured URLs
    check_results = []
    for url in check_urls:
        try:
            response = http.request('GET', url)
            success = response.status == 200
            check_results.append(success)
            print(f"Check {url}: {'OK' if success else 'FAILED'} (status: {response.status})")
        except Exception as e:
            check_results.append(False)
            print(f"Check {url} failed: {str(e)}")

    # Internet is reachable if at least one URL responds
    status = 1 if any(check_results) else 0
    print(f"Final connectivity status: {status} (successful checks: {sum(check_results)}/{len(check_results)})")

    # Retrieve environment variables
    SubnetId = os.environ['SubnetId']
    vpc_id = os.environ['VPC_ID']

    metric_data = {
        'Namespace': 'Lambda/InternetConnectivity',
        'MetricData': [{
            'MetricName': 'InternetConnectivityStatus',
            'Value': status,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'SubnetId', 'Value': SubnetId},
                {'Name': 'VpcId', 'Value': vpc_id}
            ]
        }]
    }

    print(f"Sending metric to CloudWatch: {json.dumps(metric_data)}")
    try:
        response = cloudwatch.put_metric_data(**metric_data)
        print(f"Metric sent successfully: {response}")
    except Exception as e:
        print(f"Error sending metric: {str(e)}")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': status,
            'successful_checks': sum(check_results),
            'total_checks': len(check_results),
            'check_urls': check_urls,
            'SubnetId': SubnetId,
            'vpc': vpc_id
        })
    }
