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

variable "bucket_name" {
  type        = string
  description = "Exact name for the bucket this module creates. Ignored when s3_bucket_name is set. If empty, the bucket is named '{name}-{account_id}'. Use this to adopt a bucket with a fixed name (import it into the module's aws_s3_bucket.website[0])."
  default     = ""

  validation {
    condition     = var.bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "comment" {
  type        = string
  description = "Comment on the CloudFront distribution. Defaults to the value of name."
  default     = null
}

variable "versioning_enabled" {
  type        = bool
  description = "When true (default), the module enables S3 versioning on the bucket it creates. When false, the module does not manage versioning at all (it does not suspend it), which suits buckets that have never had versioning enabled."
  default     = true
}

variable "cache_policy_id" {
  type        = string
  description = "CloudFront cache policy ID for the default behaviour. Defaults to the AWS managed Managed-CachingOptimized policy. For example, use 4135ea2d-6df8-44a3-9df3-4b5a84be39ad for Managed-CachingDisabled."
  default     = null
}

variable "ordered_cache_behaviors" {
  type = list(object({
    path_pattern    = string
    cache_policy_id = optional(string)
  }))
  description = "Extra path-based cache behaviours, evaluated in order. cache_policy_id defaults to the module's default cache policy."
  default     = []
}

variable "custom_error_responses" {
  type = list(object({
    error_code            = number
    response_code         = number
    response_page_path    = string
    error_caching_min_ttl = optional(number, 10)
  }))
  description = "Custom error responses. When null (default), 403 and 404 are handled as before, controlled by spa_mode. When set, replaces that default entirely."
  default     = null
}

variable "directory_index_rewrite" {
  type        = bool
  description = "Attach a CloudFront Function that serves index.html for URLs ending in / (for example /docs/ becomes /docs/index.html). CloudFront only does this for the site root by default, so without it subdirectory URLs return the error page."
  default     = false
}

variable "directory_index_redirect" {
  type        = bool
  description = "Only used when directory_index_rewrite is true. Also 301-redirect extension-less paths such as /docs to /docs/. Disable if the bucket holds real objects without a file extension."
  default     = true
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
  description = "List of CNAMEs (alternate domain names) for the CloudFront distribution, including wildcards such as *.example.com. Leave empty to use the default *.cloudfront.net domain."
  default     = []

  validation {
    condition = alltrue([
      for alias in var.cloudfront_aliases : can(regex("^(\\*\\.)?[a-z0-9.-]+\\.[a-z]{2,}$", alias))
    ])
    error_message = "CloudFront aliases must be valid domain names. A single leading wildcard label (*.example.com) is allowed."
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
