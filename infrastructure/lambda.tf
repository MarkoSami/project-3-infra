###############################################################
# SES — Email Identity Verification
###############################################################

resource "aws_ses_email_identity" "contact" {
  email = var.contact_email
}

###############################################################
# IAM — Lambda Execution Role
###############################################################

resource "aws_iam_role" "lambda_contact" {
  name = "${var.project_name}-contact-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${var.project_name}-contact-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_contact.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ses" {
  name = "ses-send-email"
  role = aws_iam_role.lambda_contact.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "arn:aws:ses:${var.aws_region}:*:identity/${var.contact_email}"
    }]
  })
}

###############################################################
# Lambda — Contact Form Handler
###############################################################

data "archive_file" "contact_lambda" {
  type        = "zip"
  output_path = "${path.module}/contact_lambda.zip"

  source {
    content  = <<-PYTHON
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ses = boto3.client('ses')

CORS_HEADERS = {
    'Access-Control-Allow-Origin': os.environ.get('ALLOWED_ORIGIN', '*'),
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json'
}

def handler(event, context):
    if event.get('httpMethod') == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': ''}

    try:
        body = json.loads(event.get('body') or '{}')
        name    = body.get('name', '').strip()
        email   = body.get('email', '').strip()
        message = body.get('message', '').strip()

        if not all([name, email, message]):
            return {'statusCode': 400, 'headers': CORS_HEADERS,
                    'body': json.dumps({'error': 'name, email and message are required'})}

        contact_email = os.environ['CONTACT_EMAIL']
        ses.send_email(
            Source=contact_email,
            Destination={'ToAddresses': [contact_email]},
            Message={
                'Subject': {'Data': f'[Contact Form] New message from {name}'},
                'Body': {
                    'Text': {
                        'Data': f'Name: {name}\nEmail: {email}\n\nMessage:\n{message}'
                    }
                }
            },
            ReplyToAddresses=[email]
        )
        logger.info(f'Contact email sent from {email}')
        return {'statusCode': 200, 'headers': CORS_HEADERS,
                'body': json.dumps({'message': 'Your message has been sent!'})}

    except Exception as e:
        logger.error(f'Error sending email: {e}')
        return {'statusCode': 500, 'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Failed to send message. Please try again later.'})}
PYTHON
    filename = "handler.py"
  }
}

resource "aws_lambda_function" "contact" {
  function_name    = "${var.project_name}-${var.environment}-contact"
  filename         = data.archive_file.contact_lambda.output_path
  source_code_hash = data.archive_file.contact_lambda.output_base64sha256
  role             = aws_iam_role.lambda_contact.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      CONTACT_EMAIL  = var.contact_email
      ALLOWED_ORIGIN = "https://${var.domain_name}"
    }
  }

  tags = {
    Name = "${var.project_name}-contact-handler"
  }
}

resource "aws_cloudwatch_log_group" "contact_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.contact.function_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-contact-logs"
  }
}

###############################################################
# API Gateway — REST API for Contact Form
###############################################################

resource "aws_api_gateway_rest_api" "contact" {
  name        = "${var.project_name}-${var.environment}-api"
  description = "Contact form API for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

resource "aws_api_gateway_resource" "contact" {
  rest_api_id = aws_api_gateway_rest_api.contact.id
  parent_id   = aws_api_gateway_rest_api.contact.root_resource_id
  path_part   = "contact"
}

# POST method
resource "aws_api_gateway_method" "contact_post" {
  rest_api_id   = aws_api_gateway_rest_api.contact.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "contact_post" {
  rest_api_id             = aws_api_gateway_rest_api.contact.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.contact.invoke_arn
}

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "contact_options" {
  rest_api_id   = aws_api_gateway_rest_api.contact.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "contact_options" {
  rest_api_id             = aws_api_gateway_rest_api.contact.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.contact.invoke_arn
}

resource "aws_api_gateway_deployment" "contact" {
  rest_api_id = aws_api_gateway_rest_api.contact.id

  depends_on = [
    aws_api_gateway_integration.contact_post,
    aws_api_gateway_integration.contact_options
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "contact" {
  deployment_id = aws_api_gateway_deployment.contact.id
  rest_api_id   = aws_api_gateway_rest_api.contact.id
  stage_name    = var.environment

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.contact.execution_arn}/*/*"
}
