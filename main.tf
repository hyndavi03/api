provider "aws" {
  region = var.aws_region
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/example/"
  output_path = "${path.module}/example/main.zip"
}




resource "aws_iam_role" "lambda_exec" {
  name = "serverless_example_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "example" {
  function_name = "ServerlessExample"
  filename      = data.archive_file.lambda_zip.output_path
  handler       = "main.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}


resource "aws_api_gateway_rest_api" "example" {
  name        = "ServerlessExample"
  description = "Terraform Serverless Application Example"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.example.id}"
  parent_id   = "${aws_api_gateway_rest_api.example.root_resource_id}"
  path_part   = "cognito"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.example.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_cognito_user_pool" "example" {
  name = "example-user-pool"
  # Configure other user pool attributes as needed
}

resource "aws_cognito_user_pool_client" "example" {
  name                     = "example-user-pool-client"
  user_pool_id             = aws_cognito_user_pool.example.id
  generate_secret          = true
  explicit_auth_flows       = ["ALLOW_REFRESH_TOKEN_AUTH"]
}

resource "aws_cognito_user_pool_domain" "example" {
  domain = "my-pool-domain"
  user_pool_id = aws_cognito_user_pool.example.id
}


resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "example-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.example.id
  type                   = "COGNITO_USER_POOLS"
  identity_source        = "method.request.header.Authorization"
  provider_arns          = [aws_cognito_user_pool.example.arn]
}


resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.example.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.example.invoke_arn}"

  request_templates = {
    "application/json" = <<EOF
{
  "Authorization": "$input.params('Authorization')"
}
EOF
  }
}

resource "aws_api_gateway_authorizer" "lambda" {
  name                   = "example-lambda-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.example.id
  type                   = "TOKEN"
  identity_source        = "method.request.header.Authorization"
  authorizer_uri         = aws_lambda_function.example.invoke_arn
  authorizer_credentials = aws_iam_role.lambda_exec.arn
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.example.id}"
  resource_id   = "${aws_api_gateway_rest_api.example.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.example.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.example.invoke_arn}"
}

resource "aws_api_gateway_deployment" "example" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.example.id}"
  stage_name  = "sample"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.example.function_name}"
  principal     = "cognito-idp.amazonaws.com"

  source_arn = aws_cognito_user_pool.example.arn
}

  


terraform {
  backend "s3" {
    bucket = "terraformstatefile0"  # Replace with your bucket name
    key    = "terraform.tfstate"
    region = "ap-south-1"  # Replace with your preferred region
  }
}


