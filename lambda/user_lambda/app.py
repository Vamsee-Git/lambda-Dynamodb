import json
import os
import uuid
import boto3

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['USERS_TABLE']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    http_method = event['httpMethod']
    
    if http_method == 'POST':
        return create_user(event)
    elif http_method == 'GET':
        return get_users()
    else:
        return {
            'statusCode': 405,
            'body': json.dumps({'error': 'Method Not Allowed'})
        }

def create_user(event):
    try:
        user_data = json.loads(event['body'])
    except:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid request body'})
        }

    user_id = str(uuid.uuid4())

    item = {
        'id': user_id,  # Changed from 'user_id' to 'id'
        'name': user_data['name'],
        'email': user_data['email']
    }
    
    try:
        table.put_item(Item=item)
        return {
            'statusCode': 200,
            'body': json.dumps({'user_id': user_id})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_users():
    try:
        response = table.scan()
        return {
            'statusCode': 200,
            'body': json.dumps(response['Items'])
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }