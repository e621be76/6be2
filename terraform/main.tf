resource "cloudflare_dns_record" "quote_api" {
  zone_id = var.zone_id
  name    = "quote-api.${var.zone_name}"
  type    = "CNAME"
  content = var.origin_hostname
  proxied = true
  ttl     = 1 # 1 = automatic, required for proxied records
  comment = "managed by terraform"
}

# adopt the record someone created by hand in the dashboard; after the first apply this block can be deleted
import {
  to = cloudflare_dns_record.legacy
  id = "${var.zone_id}/${var.legacy_record_id}"
}

# every attribute mirrors the live record, so the import adopts it without changing it
resource "cloudflare_dns_record" "legacy" {
  zone_id = var.zone_id
  name    = coalesce(var.legacy_record_name, "www.${var.zone_name}")
  type    = var.legacy_record_type
  content = var.legacy_record_content
  proxied = var.legacy_record_proxied
  ttl     = 1
}

# one ruleset per zone per phase; rules are evaluated in order and later matches override earlier ones
resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      description = "static assets: cache at the edge for 30d, in browsers for 1d"
      expression  = "(http.host eq \"quote-api.${var.zone_name}\" and http.request.uri.path.extension in {\"css\" \"js\" \"mjs\" \"png\" \"jpg\" \"jpeg\" \"gif\" \"svg\" \"webp\" \"avif\" \"ico\" \"woff\" \"woff2\"})"
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 2592000
        }
        browser_ttl = {
          mode    = "override_origin"
          default = 86400
        }
      }
    },
    {
      # last so it wins over the static rule, e.g. for /api/export.js
      description = "API responses are per-request: never cache"
      expression  = "(http.host eq \"quote-api.${var.zone_name}\" and starts_with(http.request.uri.path, \"/api/\"))"
      action      = "set_cache_settings"
      enabled     = true
      action_parameters = {
        cache = false
      }
    },
  ]
}
