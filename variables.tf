variable "name" {
  type        = string
  description = "Name of the stack/project. Used for resource naming and tagging."
  default     = "static-website"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "Name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of an existing S3 bucket to use. If empty, a new bucket will be created with the format '{name}-{account_id}'."
  default     = ""

  validation {
    condition     = var.s3_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.s3_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name for resource tagging (e.g., Development, Staging, Production)."
  default     = "Production"

  validation {
    condition     = contains(["Development", "Staging", "Production"], var.environment)
    error_message = "Environment must be one of: Development, Staging, Production."
  }
}

variable "cloudfront_aliases" {
  type        = list(string)
  description = "List of CNAMEs (alternate domain names) for the CloudFront distribution. Leave empty to use the default *.cloudfront.net domain."
  default     = []

  validation {
    condition = alltrue([
      for alias in var.cloudfront_aliases : can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", alias))
    ])
    error_message = "CloudFront aliases must be valid domain names."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all taggable resources. Merged with module-managed tags (Name, Environment, ManagedBy)."
  default     = {}
}

variable "logging_bucket" {
  type        = string
  description = "Domain name of the S3 bucket to receive CloudFront access logs (e.g. my-logs-bucket.s3.amazonaws.com). If null, logging is disabled. The bucket must have ACLs enabled and grant write access to the CloudFront logging service."
  default     = null
}

variable "logging_prefix" {
  type        = string
  description = "Optional key prefix for CloudFront access log files written to the logging bucket."
  default     = ""
}

variable "spa_mode" {
  type        = bool
  description = "When true, CloudFront returns HTTP 200 for 403/404 errors and serves index.html, enabling client-side routing for single-page applications. When false (default), correct 403/404 status codes are returned."
  default     = false
}

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront price class. PriceClass_100 covers US/EU only (cheapest), PriceClass_200 adds more regions, PriceClass_All uses all edge locations."
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "upload_sample_files" {
  type        = bool
  description = "When true, uploads sample index.html and error.html files to the bucket. Disabled by default to avoid overwriting consumer content."
  default     = false
}

variable "cloudfront_certificate_arn" {
  type        = string
  description = "ARN of the AWS Certificate Manager certificate to use for CloudFront HTTPS. Required when cloudfront_aliases is specified."
  default     = null

  validation {
    condition     = var.cloudfront_certificate_arn == null || can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[a-f0-9-]+$", var.cloudfront_certificate_arn))
    error_message = "CloudFront certificate ARN must be a valid ACM certificate ARN in us-east-1 region."
  }
}
