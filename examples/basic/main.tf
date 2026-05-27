provider "aws" {
  region = "us-east-1"
}

module "static_website" {
  source = "../../"

  name        = "my-static-website"
  environment = "Production"

  # Optional: Use custom domain
  # cloudfront_aliases          = ["www.example.com", "example.com"]
  # cloudfront_certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-a123-456a-a12b-a123b4cd56ef"
}
