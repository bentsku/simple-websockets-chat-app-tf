variable table_name {
  description = "(Required) The name of the new DynamoDB to store connection identifiers for each connected clients. Minimum 3 characters"
  type = string
  default = "ws-users"
}

# resource "aws_s3_bucket" "snapshot" {
#   bucket = "snapshot"
# }

resource "aws_dynamodb_table" "ws_users" {
  name           = var.table_name
  hash_key = "connectionId"
  billing_mode   = "PROVISIONED"  # You can change this to "PAY_PER_REQUEST" if needed
  read_capacity  = 5              # Adjust these values based on your needs
  write_capacity = 5              # Adjust these values based on your needs

  attribute {
    name = "connectionId"
    type = "S"
  }
}

resource "aws_iam_role" "cloudwatch_apigateway_role" {
  name = "CloudWatchAPIGateway"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_apigateway_policy" {
  name        = "AmazonAPIGatewayPushToCloudWatchLogs"
  description = "Policy to allow API Gateway to push logs to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_apigateway_policy_attach" {
  policy_arn = aws_iam_policy.cloudwatch_apigateway_policy.arn
  role       = aws_iam_role.cloudwatch_apigateway_role.name
}

data "aws_iam_policy_document" "ws_api_gateway_policy" {
  statement {
    actions = [
      "lambda:InvokeFunction",
    ]
    effect    = "Allow"
    resources = [
      aws_lambda_function.ws-connect.arn,
      aws_lambda_function.ws-disconnect.arn,
      aws_lambda_function.ws-send.arn
    ]
  }
}

resource "aws_iam_policy" "ws_api_gateway_policy" {
  name   = "WsAPIGatewayPolicy"
  path   = "/"
  policy = data.aws_iam_policy_document.ws_api_gateway_policy.json
}

resource "aws_iam_role" "ws_api_gateway_role" {
  name = "WsAPIGatewayRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = [aws_iam_policy.ws_api_gateway_policy.arn]
}

resource "aws_iam_role" "lambda_execution" {
  name = "lambda_execution"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_execution_policy" {
  name        = "lambda_execution-policy"
  description = "Permissions for the Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid     = "VisualEditor0",
        Effect  = "Allow",
        Action  = [
          "execute-api:*",
          "apigateway:*",
          "dynamodb:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy_attach" {
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
  role       = aws_iam_role.lambda_execution.name
}

resource "aws_apigatewayv2_api" "gw_web_socket" {
  name = "SimpleChatWebSocket"
  protocol_type = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

output "invoke_url"{
  value = aws_apigatewayv2_stage.stage.invoke_url
}

output "ws_url" {
  value = aws_apigatewayv2_api.gw_web_socket.api_endpoint
}

resource "aws_lambda_function" "ws-connect" {
  function_name = "ws-connect"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"

  s3_bucket = "snapshot"
  s3_key    = "ws-connect/lambda-package.zip"

  runtime       = "nodejs16.x"

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }
}

resource "aws_apigatewayv2_route" "connect_route" {
  api_id = aws_apigatewayv2_api.gw_web_socket.id
  route_key = "$connect"
  authorization_type = "NONE"
  operation_name = "ConnectRoute"
  target = "integrations/${aws_apigatewayv2_integration.connect_integ.id}"
}

resource "aws_apigatewayv2_integration" "connect_integ" {
  api_id                    = aws_apigatewayv2_api.gw_web_socket.id
  description               = "Connect Integration"
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.ws-connect.invoke_arn
  credentials_arn           = aws_iam_role.ws_api_gateway_role.arn
}

resource "aws_lambda_function" "ws-disconnect" {
  function_name = "ws-disconnect"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"  

  s3_bucket = "snapshot"
  s3_key    = "ws-disconnect/lambda-package.zip"

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id = aws_apigatewayv2_api.gw_web_socket.id
  route_key = "$disconnect"
  operation_name = "DisconnectRoute"
  target = "integrations/${aws_apigatewayv2_integration.disconnect_integ.id}"
}

resource "aws_apigatewayv2_integration" "disconnect_integ" {
  api_id                    = aws_apigatewayv2_api.gw_web_socket.id
  description               = "Disconnect Integration"
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.ws-disconnect.invoke_arn
  credentials_arn           = aws_iam_role.ws_api_gateway_role.arn  
}

resource "aws_lambda_function" "ws-send" {
  function_name = "ws-send"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"  

  s3_bucket = "snapshot"
  s3_key    = "ws-send/lambda-package.zip"

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }
}

resource "aws_apigatewayv2_route" "send_route" {
  api_id = aws_apigatewayv2_api.gw_web_socket.id
  route_key = "$default"
  operation_name = "SendRoute"
  target = "integrations/${aws_apigatewayv2_integration.send_integ.id}"
  route_response_selection_expression = "$default"
}

resource "aws_apigatewayv2_integration" "send_integ" {
  api_id                    = aws_apigatewayv2_api.gw_web_socket.id
  description               = "Send Integration"
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.ws-send.invoke_arn
  credentials_arn           = aws_iam_role.ws_api_gateway_role.arn  
}

resource "aws_apigatewayv2_route_response" "send_response" {
  api_id             = aws_apigatewayv2_api.gw_web_socket.id
  route_id           = aws_apigatewayv2_route.send_route.id
  route_response_key = "$default"
}

resource "aws_apigatewayv2_deployment" "deployment" {
  api_id = aws_apigatewayv2_api.gw_web_socket.id
}

resource "aws_apigatewayv2_stage" "stage" {
  name = "production"
  description = "production stage"
  deployment_id = aws_apigatewayv2_deployment.deployment.id
  api_id = aws_apigatewayv2_api.gw_web_socket.id


  default_route_settings {
    data_trace_enabled     = true
    detailed_metrics_enabled = true
    logging_level          = "INFO" 
    throttling_burst_limit = 500
    throttling_rate_limit  = 1000    
  }
}