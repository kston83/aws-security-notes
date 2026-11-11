environment = "dev"

buckets = {
  logs = {
    classification = "internal"
  }
  reports = {
    classification = "restricted"
    encryption = {
      algorithm  = "aws:kms"
      bucket_key = true
    }
  }
  scratch = {
    classification = "public"
    versioning     = false
    enforce_tls    = false
  }
}
