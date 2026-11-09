# Terraform AWS Static Website

[![Terraform Validation](https://github.com/mikmorley/terraform-aws-static-website/actions/workflows/terraform-validation.yml/badge.svg)](https://github.com/mikmorley/terraform-aws-static-website/actions/workflows/terraform-validation.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A5%201.0-blue.svg)](https://terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-%E2%89%A5%205.0-orange.svg)](https://registry.terraform.io/providers/hashicorp/aws/latest)

Hosting a static website on AWS the right way involves more than dropping files in an S3 bucket. You need a CloudFront distribution in front of it, an origin access policy that prevents direct bucket access, a bucket policy with the right conditions, public access blocks, versioning, error page handling, and certificate configuration. Done manually, that is a dozen resources and several security decisions that are easy to get wrong.

This module packages all of that into a single, well-tested block. Two required variables and you have a production-grade static website on AWS global infrastructure.

```hcl
module "website" {
  source = "mikmorley/static-website/aws"

  name        = "my-website"
  environment = "Production"
}
```

![Architecture Diagram](files/s3-website-cloudfront.png)

## Why use this module

**Secure by default.** The S3 bucket is never publicly accessible. Access is restricted to a specific CloudFront distribution using Origin Access Control (OAC) and `aws:SourceArn` scoping in the bucket policy, so other distributions cannot access your bucket even if misconfigured.

**Up to date.** The module uses OAC rather than the deprecated Origin Access Identity (OAI), the AWS managed `CachingOptimized` cache policy rather than the legacy `forwarded_values` block, and `BucketOwnerEnforced` ownership controls rather than ACLs.

**Registry compliant.** No provider block is declared inside the module. You configure the provider in your root module, which means the module works correctly across multi-region and multi-account setups and supports provider aliasing.

**Flexible.** Bring your own bucket by setting `s3_bucket_name`, use a custom domain with an ACM certificate, inject your own tags, choose a CloudFront price class to control cost, or wire up Route 53 alias records using the `cloudfront_hosted_zone_id` output.

## Features

- Private S3 bucket with all public access blocked
- CloudFront Origin Access Control (OAC) scoped to this distribution
- Bucket policy denies all access except from the specific distribution and account IAM principals
- HTTPS enforced with minimum TLS 1.2
- Custom 403/404 error pages
- S3 versioning enabled
- Works with an existing bucket or creates a new one
- Custom domain and ACM certificate support (optional)

## Quick Start

```hcl
provider "aws" {
  region = "us-east-1"
}

module "website" {
  source = "mikmorley/static-website/aws"

  name        = "my-website"
  environment = "Production"
}
```

No certificate is required for the default CloudFront domain. Supply `cloudfront_certificate_arn` only when using custom aliases.

## Usage Examples

### Custom Domain with SSL Certificate

```hcl
provider "aws" {
  region = "us-east-1"
}

module "website" {
  source = "mikmorley/static-website/aws"

  name        = "company-website"
  environment = "Production"

  cloudfront_aliases         = ["www.example.com", "example.com"]
  cloudfront_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-a123-456a-a12b-a123b4cd56ef"
}
```

### Route 53 Alias Record

The module outputs `cloudfront_hosted_zone_id` for use with Route 53 alias records:

```hcl
resource "aws_route53_record" "www" {
  zone_id = var.hosted_zone_id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = module.website.cloudfront_url
    zone_id                = module.website.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}
```

### Naming the Bucket

By default the module creates `{name}-{account_id}`. To choose the name, for example when adopting a bucket that already exists, set `bucket_name` and import the bucket into the module (`aws_s3_bucket.website[0]`):

```hcl
module "website" {
  source = "mikmorley/static-website/aws"

  name        = "company-website"
  bucket_name = "company-website-prod"
}
```

### Tuning Caching and Error Pages

```hcl
module "website" {
  source = "mikmorley/static-website/aws"

  name            = "company-website"
  cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled

  ordered_cache_behaviors = [
    { path_pattern = "/assets/*", cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" }, # Managed-CachingOptimized
  ]

  custom_error_responses = [
    { error_code = 403, response_code = 200, response_page_path = "/error.html", error_caching_min_ttl = 0 },
    { error_code = 404, response_code = 200, response_page_path = "/error.html", error_caching_min_ttl = 0 },
  ]
}
```

### Subdirectory Index Pages

CloudFront serves `index.html` for `/` only. For a site with folders (`/docs/index.html`), set `directory_index_rewrite = true`. A viewer-request CloudFront Function then maps `/docs/` to `/docs/index.html` and, unless `directory_index_redirect = false`, redirects `/docs` to `/docs/`.

```hcl
module "website" {
  source = "mikmorley/static-website/aws"

  name                    = "company-website"
  directory_index_rewrite = true
}
```

### Using an Existing S3 Bucket

With `s3_bucket_name` set, the module only reads the bucket. It does **not** create or change the bucket's policy, public access block or versioning, so you must add a bucket policy that allows this distribution (`aws:SourceArn`) to read objects. To have the module manage the bucket, use `bucket_name` instead.

```hcl
module "website" {
  source = "mikmorley/static-website/aws"

  name           = "company-website"
  s3_bucket_name = "my-existing-bucket"
  environment    = "Production"
}
```

## Architecture

This module creates the following AWS resources:

- **S3 Bucket**: Private bucket for static content (created unless `s3_bucket_name` is provided)
- **S3 Bucket Policy**: Allows access only from the CloudFront distribution and account IAM principals
- **S3 Bucket Versioning**: Object versioning for content history
- **S3 Public Access Block**: Prevents any public access configuration
- **CloudFront Distribution**: Global CDN with OAC-based S3 origin
- **CloudFront Origin Access Control**: Sigv4-signed requests scoped to this distribution

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the stack/project. Used for resource naming and tagging. | `string` | `"static-website"` | no |
| environment | Environment for tagging. Must be `Development`, `Staging`, or `Production`. | `string` | `"Production"` | no |
| s3_bucket_name | Existing S3 bucket to read from. The module does not manage that bucket or its policy. If empty, a new bucket is created. | `string` | `""` | no |
| bucket_name | Exact name for the bucket the module creates (ignored when `s3_bucket_name` is set). If empty, the bucket is named `{name}-{account_id}`. | `string` | `""` | no |
| comment | Comment on the CloudFront distribution. Defaults to `name`. | `string` | `null` | no |
| versioning_enabled | Enable S3 versioning on the bucket the module creates. When false, versioning is left unmanaged (not suspended). | `bool` | `true` | no |
| cache_policy_id | Cache policy ID for the default behaviour. Defaults to `Managed-CachingOptimized`. | `string` | `null` | no |
| ordered_cache_behaviors | Extra path-based cache behaviours: `path_pattern` and optional `cache_policy_id`. | `list(object)` | `[]` | no |
| custom_error_responses | Replaces the default 403/404 handling (which `spa_mode` controls) when set. | `list(object)` | `null` | no |
| directory_index_rewrite | Attach a CloudFront Function that serves `index.html` for URLs ending in `/` (CloudFront only does this for the site root). | `bool` | `false` | no |
| directory_index_redirect | With `directory_index_rewrite`, also 301-redirect extension-less paths (`/docs`) to `/docs/`. | `bool` | `true` | no |
| cloudfront_aliases | Alternate domain names for the CloudFront distribution. | `list(string)` | `[]` | no |
| cloudfront_certificate_arn | ACM certificate ARN for CloudFront HTTPS. Must be in us-east-1. Required when `cloudfront_aliases` is set. | `string` | `null` | no |
| cloudfront_price_class | CloudFront price class. `PriceClass_100` covers US/EU (cheapest), `PriceClass_200` adds more regions, `PriceClass_All` uses all edge locations. | `string` | `"PriceClass_100"` | no |
| logging_bucket | Domain name of the S3 bucket to receive CloudFront access logs (e.g. `my-logs.s3.amazonaws.com`). If null, logging is disabled. | `string` | `null` | no |
| logging_prefix | Key prefix for CloudFront access log files in the logging bucket. | `string` | `""` | no |
| spa_mode | When true, CloudFront returns HTTP 200 for 403/404 errors and serves `index.html`, enabling client-side routing for single-page applications. | `bool` | `false` | no |
| tags | Additional tags to merge with module-managed tags (`Name`, `Environment`, `ManagedBy`). | `map(string)` | `{}` | no |
| upload_sample_files | When true, uploads sample `index.html` and `error.html` files to the bucket. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| cloudfront_url | Domain name of the CloudFront distribution |
| cloudfront_distribution_id | Identifier for the CloudFront distribution |
| cloudfront_hosted_zone_id | Hosted zone ID of the CloudFront distribution, required for Route 53 alias records |
| s3_bucket_name | Name of the S3 bucket |
| s3_bucket_arn | ARN of the S3 bucket |
| s3_bucket_domain_name | Bucket domain name of the S3 bucket |
| origin_access_control_id | ID of the CloudFront origin access control |

## Security

**Access control**: The bucket policy has two statements. The first allows `s3:GetObject` from the CloudFront service principal, conditioned on `aws:SourceArn` matching this specific distribution. The second denies all other access unless the request comes from an IAM principal in the same AWS account.

**HTTPS**: CloudFront redirects all HTTP to HTTPS and enforces TLS 1.2 minimum.

**Custom certificates**: ACM certificates must be issued in `us-east-1` (CloudFront requirement).

**Error pages**: 403 and 404 responses are mapped to `error.html` to avoid leaking bucket structure.

## Custom Domain Setup

1. Request an ACM certificate in `us-east-1`:
   ```bash
   aws acm request-certificate \
     --domain-name example.com \
     --subject-alternative-names www.example.com \
     --region us-east-1
   ```

2. Set `cloudfront_aliases` and `cloudfront_certificate_arn` in the module block.

3. Create DNS records pointing to the CloudFront distribution. Use Route 53 alias records (with `cloudfront_hosted_zone_id`) for the apex domain, or CNAME records for subdomains.

## Contributing

Contributions are welcome. Please submit pull requests to the `main` branch.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Michael Morley**
- Email: [michael@morley.cloud](mailto:michael@morley.cloud)
- Website: [https://michael.morley.cloud](https://michael.morley.cloud)
- GitHub: [@mikmorley](https://github.com/mikmorley)

## Support

- [Report Issues](https://github.com/mikmorley/terraform-aws-static-website/issues)
- [View Documentation](https://github.com/mikmorley/terraform-aws-static-website)
- [Request Features](https://github.com/mikmorley/terraform-aws-static-website/issues)
