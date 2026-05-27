data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "existing" {
  count  = 1 - local.create_bucket
  bucket = var.s3_bucket_name
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  s3_origin_id = "s3-website"

  # If var.s3_bucket_name is not set, a new bucket will be created.
  create_bucket = var.s3_bucket_name == "" ? 1 : 0
  bucket_name   = local.create_bucket == 1 ? "${var.name}-${local.account_id}" : var.s3_bucket_name

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
  count  = local.create_bucket
  bucket = local.bucket_name

  tags = {
    Environment = var.environment
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "website" {
  count  = local.create_bucket
  bucket = aws_s3_bucket.website[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket ACL
resource "aws_s3_bucket_acl" "website" {
  count      = local.create_bucket
  bucket     = aws_s3_bucket.website[0].id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.website]
}

# S3 Bucket Ownership Controls
resource "aws_s3_bucket_ownership_controls" "website" {
  count  = local.create_bucket
  bucket = aws_s3_bucket.website[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 Bucket Policy
resource "aws_s3_bucket_policy" "website" {
  count  = local.create_bucket
  bucket = aws_s3_bucket.website[0].id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

# S3 Bucket Policy allowing access from CloudFront and AWS account root
data "aws_iam_policy_document" "s3_bucket_policy" {
  # Allow CloudFront OAI to read objects
  statement {
    sid = "AllowCloudFrontAccess"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${local.bucket_name}/*",
    ]
    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn,
      ]
    }
  }

  # Allow AWS account root full access for administration
  statement {
    sid = "AllowRootAccountAccess"
    actions = [
      "s3:*",
    ]
    resources = [
      "arn:aws:s3:::${local.bucket_name}",
      "arn:aws:s3:::${local.bucket_name}/*",
    ]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${local.account_id}:root",
      ]
    }
  }

  # Deny all public access (explicit deny for security)
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
      variable = "aws:PrincipalServiceName"
      values   = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringNotLike"
      variable = "aws:PrincipalArn"
      values = [
        "arn:aws:iam::${local.account_id}:*",
        aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn
      ]
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "website" {
  count  = local.create_bucket
  bucket = aws_s3_bucket.website[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Add initial static web files to s3 for validation of infrastructure
resource "aws_s3_object" "root" {
  for_each = fileset("${path.module}/files/", "**")

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

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
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

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  price_class = "PriceClass_All"

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
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = "/error.html"
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = "/error.html"
  }

  wait_for_deployment = false

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-${local.bucket_name}.s3.amazonaws.com"
}
