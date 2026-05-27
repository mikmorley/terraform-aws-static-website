# Basic Example

This example demonstrates the basic usage of the `terraform-aws-static-website` module.

## Usage

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

## Running this example

1. Clone the repository
2. Navigate to this example directory
3. Run `terraform init`
4. Run `terraform plan`
5. Run `terraform apply`

The module will create:

- A private S3 bucket with versioning enabled
- A CloudFront distribution with Origin Access Control (OAC)
- A bucket policy scoped to this specific distribution via `aws:SourceArn`

After applying, upload your website files to the S3 bucket and access them via the CloudFront URL output.

## Custom Domain (Optional)

To use a custom domain, add `cloudfront_aliases` and `cloudfront_certificate_arn` to the module block:

```hcl
cloudfront_aliases         = ["www.example.com", "example.com"]
cloudfront_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-a123-456a-a12b-a123b4cd56ef"
```

The ACM certificate must be issued in `us-east-1` regardless of the region your bucket and distribution are deployed to — that is a CloudFront requirement.
