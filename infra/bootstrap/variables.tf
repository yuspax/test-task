variable "aws_account_id" {
  description = "AWS account that is allowed to host this project."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide your 12-digit AWS account ID."
  }
}

variable "project_name" {
  description = "Short, unique project prefix used in resource names."
  type        = string
  default     = "hello-world"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "Use 3–20 lowercase letters, numbers or hyphens, starting with a letter."
  }
}
