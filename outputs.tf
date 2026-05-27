output "cloudfront_url" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "cloudfront_distribution_id" {
  description = "The identifier for the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_distribution.id
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket used for hosting the static website"
  value       = local.create_bucket == 1 ? aws_s3_bucket.website[0].id : var.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = local.create_bucket == 1 ? aws_s3_bucket.website[0].arn : "arn:aws:s3:::${var.s3_bucket_name}"
}

output "s3_bucket_domain_name" {
  description = "The bucket domain name of the S3 bucket"
  value       = local.create_bucket == 1 ? aws_s3_bucket.website[0].bucket_domain_name : "${var.s3_bucket_name}.s3.amazonaws.com"
}

output "origin_access_control_id" {
  description = "The CloudFront origin access control ID"
  value       = aws_cloudfront_origin_access_control.oac.id
}

output "cloudfront_hosted_zone_id" {
  description = "The hosted zone ID of the CloudFront distribution, required for Route 53 alias records."
  value       = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
}