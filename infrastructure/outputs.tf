output "website_bucket_name" {
  description = "S3 bucket name — deploy your static files here"
  value       = aws_s3_bucket.website.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — use for cache invalidation after deployments"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "website_url" {
  description = "Public website URL"
  value       = "https://${var.domain_name}"
}

output "contact_api_url" {
  description = "Contact form API endpoint — use this in your frontend form"
  value       = "${aws_api_gateway_stage.contact.invoke_url}/contact"
}

output "route53_nameservers" {
  description = "Route 53 nameservers — update your domain registrar with these values"
  value       = aws_route53_zone.primary.name_servers
}

output "ses_identity_arn" {
  description = "SES email identity ARN — check your inbox to verify the email address"
  value       = aws_ses_email_identity.contact.arn
}
