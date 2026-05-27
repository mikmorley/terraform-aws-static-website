data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_s3_bucket" "existing" {
  count  = local.create_bucket ? 0 : 1
  bucket = var.s3_bucket_name
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  s3_origin_id = "s3-website"

  # If var.s3_bucket_name is not set, a new bucket will be created.
  create_bucket = var.s3_bucket_name == ""
  bucket_name   = local.create_bucket ? "${var.name}-${local.account_id}" : var.s3_bucket_name

  tags = merge(var.tags, {
    Name        = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  bucket_domain_name = one(concat(
    aws_s3_bucket.website[*].bucket_regional_domain_name,
    data.aws_s3_bucket.existing[*].bucket_regional_domain_name,
  ))

  mime_types = {
    html  = "text/html"
    css   = "text/css"
    eot   = "application/vnd.ms-fontobject"
    svg   = "image/svg+xml"
    ttf   = "application/octet-stream"
    woff  = "font/woff"
    woff2 = "font/woff2"
    otf   = "font/otf"
    jpg   = "image/jpeg"
    png   = "image/png"
    js    = "text/javascript"
  }
}

# Create S3 Bucket
resource "aws_s3_bucket" "website" {
  count  = local.create_bucket ? 1 : 0
  bucket = local.bucket_name

  tags = local.tags
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "website" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.website[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Ownership Controls
resource "aws_s3_bucket_ownership_controls" "website" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.website[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 Bucket Policy
resource "aws_s3_bucket_policy" "website" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.website[0].id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

# S3 Bucket Policy: allow this CloudFront distribution via OAC; deny everything else
data "aws_iam_policy_document" "s3_bucket_policy" {
  # Allow CloudFront OAC to read objects, scoped to this distribution
  statement {
    sid = "AllowCloudFrontAccess"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${local.bucket_name}/*",
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }

  # Deny all access except from this distribution or account IAM principals
  statement {
    sid    = "DenyPublicAccess"
    effect = "Deny"
    actions = [
      "s3:*",
    ]
    resources = [
      "arn:aws:s3:::${local.bucket_name}",
      "arn:aws:s3:::${local.bucket_name}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${local.account_id}:*"]
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "website" {
  count  = local.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.website[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "root" {
  for_each = var.upload_sample_files ? fileset("${path.module}/files/", "**") : toset([])

  bucket = local.bucket_name
  key    = each.value
  source = "${path.module}/files/${each.value}"
  etag   = filemd5("${path.module}/files/${each.value}")

  content_type = lookup(local.mime_types, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = local.bucket_domain_name
    origin_id   = local.s3_origin_id

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  default_root_object = "index.html"
  aliases             = var.cloudfront_aliases

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
    ]

    cached_methods = [
      "GET",
      "HEAD",
    ]

    target_origin_id = local.s3_origin_id

    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.cloudfront_certificate_arn != null ? [1] : []
    content {
      cloudfront_default_certificate = false
      acm_certificate_arn            = var.cloudfront_certificate_arn
      ssl_support_method             = "sni-only"
      minimum_protocol_version       = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.cloudfront_certificate_arn == null ? [1] : []
    content {
      cloudfront_default_certificate = true
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = var.spa_mode ? 200 : 403
    error_caching_min_ttl = 10
    response_page_path    = var.spa_mode ? "/index.html" : "/error.html"
  }

  custom_error_response {
    error_code            = 404
    response_code         = var.spa_mode ? 200 : 404
    error_caching_min_ttl = 10
    response_page_path    = var.spa_mode ? "/index.html" : "/error.html"
  }

  dynamic "logging_config" {
    for_each = var.logging_bucket != null ? [1] : []
    content {
      include_cookies = false
      bucket          = var.logging_bucket
      prefix          = var.logging_prefix
    }
  }

  wait_for_deployment = false

  tags = local.tags
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = local.bucket_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
