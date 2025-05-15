provider "aws" {
  region = "eu-north-1"
}

# OIDC Provider for GitHub
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1" # GitHub's OIDC thumbprint
  ]
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" : "repo:nirajku102/UC04-Lamda-deployment:ref:refs/heads/testing-OIDC"
          }
        }
      }
    ]
  })
}

# Attach Policies to the IAM Role
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # Adjust this to least privilege
}

# DynamoDB Table
resource "aws_dynamodb_table" "users" {
  name             = "myDB"
  hash_key         = "id"
  billing_mode     = "PROVISIONED"
  read_capacity    = 5
  write_capacity   = 5
  attribute {
    name = "id"
    type = "S"
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  vpc_cidr = var.vpc_cidr
  public_subnets_cidr = var.public_subnets_cidr
  private_subnets_cidr = var.private_subnets_cidr
  availability_zones = var.availability_zones
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec" {
  name = "user_lambda_exec_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }]
}
EOF
}

# Attach Basic Execution Role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC Access Role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach DynamoDB Access Role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# Single Lambda Function
resource "aws_lambda_function" "user_lambda" {
  function_name = "user_lambda"
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      USERS_TABLE = aws_dynamodb_table.users.name
    }
  }

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  name        = "lambda_sg"
  description = "Security group for Lambda function"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "users_api" {
  name          = "UsersAPI"
  protocol_type = "HTTP"
  description   = "User management API"
}

# POST /users Route
resource "aws_apigatewayv2_route" "create_user_route" {
  api_id    = aws_apigatewayv2_api.users_api.id
  route_key = "POST /users"
  target    = "integrations/${aws_apigatewayv2_integration.user_integration.id}"
}

# GET /users Route
resource "aws_apigatewayv2_route" "get_user_route" {
  api_id    = aws_apigatewayv2_api.users_api.id
  route_key = "GET /users"
  target    = "integrations/${aws_apigatewayv2_integration.user_integration.id}"
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.users_api.id
  name        = "$default"
  auto_deploy = true
}

# API Gateway Integration
resource "aws_apigatewayv2_integration" "user_integration" {
  api_id             = aws_apigatewayv2_api.users_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.user_lambda.invoke_arn
  integration_method = "POST"
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.user_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.users_api.execution_arn}/*/*"
}