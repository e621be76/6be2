terraform {
  required_version = ">= 1.6" # import blocks with variable ids

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }
}

# token comes from CLOUDFLARE_API_TOKEN, never from code or tfvars in git
provider "cloudflare" {}
