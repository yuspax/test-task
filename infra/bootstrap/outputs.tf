output "state_bucket" {
  description = "Private S3 bucket for the infrastructure state."
  value       = aws_s3_bucket.state.bucket
}

output "backend_config" {
  description = "Non-secret backend configuration for infra/main."
  value       = <<-CONFIG
    bucket              = "${aws_s3_bucket.state.bucket}"
    key                 = "test/terraform.tfstate"
    region              = "eu-central-1"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["${var.aws_account_id}"]
  CONFIG
}
