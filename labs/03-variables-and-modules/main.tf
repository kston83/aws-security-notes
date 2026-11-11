locals {
  name_prefix = format("lab03-%s", var.environment)

  common_tags = merge(
    {
      Lab         = "03-variables-and-modules"
      Environment = var.environment
      Owner       = var.owner
    },
    var.extra_tags,
  )

  # How long each classification must be kept, looked up with a fallback.
  retention_days = {
    restricted = 365
    internal   = 90
  }
}

module "bucket" {
  source   = "./modules/secure-bucket"
  for_each = var.buckets

  name           = "${local.name_prefix}-${each.key}"
  classification = each.value.classification
  versioning     = each.value.versioning
  enforce_tls    = each.value.enforce_tls
  encryption     = each.value.encryption

  tags = merge(local.common_tags, {
    RetentionDays = tostring(lookup(local.retention_days, each.value.classification, 30))
  })
}
