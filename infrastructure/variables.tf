variable "aws_region" {
  description = "Primary AWS region for Lambda, API Gateway, and S3"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used in resource naming"
  type        = string
  default     = "marketing-site"
}

variable "environment" {
  description = "Deployment environment (e.g. production, staging)"
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Root domain name (e.g. example.com). www.domain will also be configured."
  type        = string
}

variable "contact_email" {
  description = "Verified SES email address to receive contact form submissions"
  type        = string
}

variable "contact_form_origin" {
  description = "Allowed CORS origin for the contact form API (e.g. https://example.com)"
  type        = string
  default     = "*"
}
