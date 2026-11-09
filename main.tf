data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  count = var.cache_policy_id == null ? 1 : 0
  name  = "Managed-CachingOptimized"
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
  bucket_name = (
    !local.create_bucket ? var.s3_bucket_name :
    var.bucket_name != "" ? var.bucket_name :
    "${var.name}-${local.account_id}"
  )

  cache_policy_id = coalesce(var.cache_policy_id, one(data.aws_cloudfront_cache_policy.caching_optimized[*].id))

  error_responses = var.custom_error_responses != null ? var.custom_error_responses : [
    for code in [403, 404] : {
      error_code            = code
      response_code         = var.spa_mode ? 200 : code
      response_page_path    = var.spa_mode ? "/index.html" : "/error.html"
      error_caching_min_ttl = 10
    }
  ]

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
  count  = local.create_bucket && var.versioning_enabled ? 1 : 0
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

# CloudFront Function: serve index.html for directory-style URLs.
# CloudFront's default_root_object only applies to "/", and the S3 REST origin has no index document.
locals {
  directory_index_redirect_js = <<-EOT
    if (uri.indexOf('.', uri.lastIndexOf('/')) === -1) {
      var qs = Object.keys(request.querystring).map(function (k) {
        var q = request.querystring[k];
        return q.multiValue ? q.multiValue.map(function (m) { return k + '=' + m.value; }).join('&') : k + '=' + q.value;
      }).join('&');
      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: { location: { value: uri + '/' + (qs ? '?' + qs : '') } }
      };
    }
  EOT
}

resource "aws_cloudfront_function" "directory_index" {
  count   = var.directory_index_rewrite ? 1 : 0
  name    = "${var.name}-directory-index"
  runtime = "cloudfront-js-2.0"
  comment = "Serve index.html for directory-style URLs"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
        return request;
      }
      ${var.directory_index_redirect ? local.directory_index_redirect_js : ""}
      return request;
    }
  EOT
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
  comment             = var.comment != null ? var.comment : var.name
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

    cache_policy_id        = local.cache_policy_id
    viewer_protocol_policy = "redirect-to-https"

    dynamic "function_association" {
      for_each = aws_cloudfront_function.directory_index
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value.arn
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors

    content {
      path_pattern     = ordered_cache_behavior.value.path_pattern
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = local.s3_origin_id

      cache_policy_id        = coalesce(ordered_cache_behavior.value.cache_policy_id, local.cache_policy_id)
      viewer_protocol_policy = "redirect-to-https"

      dynamic "function_association" {
        for_each = aws_cloudfront_function.directory_index
        content {
          event_type   = "viewer-request"
          function_arn = function_association.value.arn
        }
      }
    }
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

  dynamic "custom_error_response" {
    for_each = local.error_responses

    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
      response_page_path    = custom_error_response.value.response_page_path
    }
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
