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

variable "instance_type" {
  description = "x86 EC2 type. t3.small is eligible for the current Free plan; t3.medium needs an appropriate plan."
  type        = string
  default     = "t3.small"

  validation {
    condition     = contains(["t3.small", "t3.medium"], var.instance_type)
    error_message = "Use t3.small or t3.medium. This configuration uses x86_64 Ubuntu."
  }
}

variable "k3s_version" {
  description = "Pinned K3s release, verified against the official stable channel."
  type        = string
  default     = "v1.36.5+k3s1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "Use an exact K3s version such as v1.36.5+k3s1."
  }
}

variable "ami_id" {
  description = "Optional pinned Ubuntu 24.04 amd64 AMI. By default resolve Canonical's current AMI from SSM."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null ? true : can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "Use a valid Ubuntu 24.04 amd64 AMI ID in eu-central-1."
  }
}

variable "http_cidr" {
  description = "IPv4 CIDR allowed to access the test website."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.http_cidr))
    error_message = "Provide an IPv4 CIDR, for example 0.0.0.0/0 or your public IP with /32."
  }
}

variable "ecr_force_delete" {
  description = "Allow deleting repositories containing images. Enable only for deliberate final cleanup."
  type        = bool
  default     = false
}

variable "github_oidc_subject" {
  description = "Exact GitHub OIDC subject for this repository's main branch, including immutable IDs when enabled."
  type        = string

  validation {
    condition     = can(regex("^repo:[^:]+:ref:refs/heads/main$", var.github_oidc_subject))
    error_message = "Provide the exact repository OIDC subject ending with :ref:refs/heads/main."
  }
}
