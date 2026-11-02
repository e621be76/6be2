variable "zone_id" {
  description = "Cloudflare zone id of example.com"
  type        = string
}

variable "zone_name" {
  description = "Zone apex, used to build record names"
  type        = string
  default     = "example.com"
}

variable "origin_hostname" {
  description = "Origin the proxied record points at, e.g. the AWS load balancer DNS name"
  type        = string
}

variable "legacy_record_id" {
  description = "Id of the manually-created record being adopted (Cloudflare API: GET /zones/{zone_id}/dns_records?name=<name>)"
  type        = string
}

variable "legacy_record_name" {
  description = "Full name of the adopted record; defaults to www.<zone>"
  type        = string
  default     = null
}

variable "legacy_record_type" {
  description = "Type of the adopted record, as it is live"
  type        = string
  default     = "CNAME"
}

variable "legacy_record_content" {
  description = "Current content of the adopted record; must match what is live or the first plan shows a change"
  type        = string
}

variable "legacy_record_proxied" {
  description = "Proxy status of the adopted record, as it is live"
  type        = bool
  default     = true
}
