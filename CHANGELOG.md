# Changelog

All notable changes to this module are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This module uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-05-28

### Breaking Changes

- **`var.region` removed.** The module no longer declares a provider block, which is a Terraform Registry requirement. Consumers must declare the `provider "aws"` block in their own root module. See the [basic example](examples/basic/main.tf).
- **`origin_access_identity_id` output renamed to `origin_access_control_id`.** Reflects the migration from OAI to OAC.
- **OAI replaced by OAC.** Existing deployments will have the `aws_cloudfront_origin_access_identity` resource destroyed and replaced by `aws_cloudfront_origin_access_control`. The bucket policy is updated automatically, but a `terraform apply` is required. There is no change to how content is served.
- **Default `price_class` changed from `PriceClass_All` to `PriceClass_100`.** Existing deployments will have their price class updated on the next apply unless `cloudfront_price_class = "PriceClass_All"` is explicitly set.

### Added

- `var.cloudfront_price_class` — expose CloudFront price class with validation. Default `PriceClass_100`.
- `var.tags` — consumer-supplied tags merged with module defaults (`Name`, `Environment`, `ManagedBy = "terraform"`).
- `var.upload_sample_files` — gates sample file uploads. Default `false`. Previously the module unconditionally uploaded `index.html`, `error.html`, and a PNG to the bucket on every apply.
- `output.cloudfront_hosted_zone_id` — hosted zone ID required for Route 53 alias records.
- `data.aws_s3_bucket.existing` — data source lookup for the existing-bucket path, fixing an index error when `s3_bucket_name` is set.
- `examples/basic/versions.tf` — makes the basic example self-contained with explicit provider version constraints.

### Changed

- **OAI to OAC.** Replaced `aws_cloudfront_origin_access_identity` with `aws_cloudfront_origin_access_control` (sigv4 signing). The bucket policy `AllowCloudFrontAccess` statement now uses the `cloudfront.amazonaws.com` service principal with an `aws:SourceArn` condition scoped to this specific distribution, preventing any other CloudFront distribution from accessing the bucket.
- **Bucket policy tightened.** The `DenyPublicAccess` statement now uses `aws:SourceArn` instead of the broad `aws:PrincipalServiceName` condition. The redundant `AllowRootAccountAccess` statement has been removed — account IAM principals are permitted by the deny condition logic.
- **Viewer certificate is now conditional.** When no `cloudfront_certificate_arn` is provided the module uses `cloudfront_default_certificate = true`, so the module works with the default CloudFront domain without requiring an ACM certificate.
- **Cache policy updated.** Replaced the deprecated `forwarded_values` block with the AWS managed `CachingOptimized` policy, resolved dynamically by name via a data source.
- **ACLs removed.** Replaced `aws_s3_bucket_acl` (BucketOwnerPreferred) with `BucketOwnerEnforced` ownership controls. ACLs are irrelevant on a fully private bucket and can fail in accounts with SCPs that block ACL operations.
- **`local.create_bucket` is now a bool.** All `count` expressions use `local.create_bucket ? 1 : 0` instead of int comparisons.
- CI Terraform version updated from `1.5.0` to `latest`.

---

## [0.9.0] - Previous release

Initial public release.
