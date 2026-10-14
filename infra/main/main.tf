terraform {
  backend "s3" {}

  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68.0"
    }
  }
}

provider "aws" {
  region              = "eu-central-1"
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }
}

# Network

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "test" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-test" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.test.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = sort(data.aws_availability_zones.available.names)[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-public" }
}

resource "aws_internet_gateway" "test" {
  vpc_id = aws_vpc.test.id
  tags   = { Name = "${var.project_name}-test" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.test.id
  tags   = { Name = "${var.project_name}-public" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.test.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "node" {
  name_prefix = "${var.project_name}-node-"
  description = "Public HTTP; administration through outbound SSM connections"
  vpc_id      = aws_vpc.test.id
  tags        = { Name = "${var.project_name}-node" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.node.id
  description       = "Test website"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.http_cidr
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.node.id
  description       = "SSM, package updates and container registries"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Container registry

resource "aws_ecr_repository" "images" {
  for_each = toset(["app", "nginx"])

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.ecr_force_delete

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "untagged" {
  for_each   = aws_ecr_repository.images
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged build artifacts after seven days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
      action = { type = "expire" }
    }]
  })
}

# Instance permissions

resource "aws_iam_role" "node" {
  name = "${var.project_name}-test-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ecr_pull" {
  name = "pull-project-images"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RegistryAuthentication"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PullProjectImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [for repository in aws_ecr_repository.images : repository.arn]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-test-node"
  role = aws_iam_role.node.name
}

# GitHub Actions: temporary credentials limited to publishing and deployment.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = var.github_oidc_subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "publish-and-deploy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages",
          "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage",
        ]
        Resource = [for repository in aws_ecr_repository.images : repository.arn]
      },
      {
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ssm:eu-central-1::document/AWS-RunShellScript",
          aws_instance.node.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation"]
        Resource = "*"
      },
    ]
  })
}

# K3s server

data "aws_ssm_parameter" "ubuntu_ami" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "node" {
  ami                         = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.ubuntu_ami[0].value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.node.name
  monitoring                  = false
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    k3s_version = var.k3s_version
    node_name   = "${var.project_name}-test"
  })

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tags = { Name = "${var.project_name}-test" }

  depends_on = [
    aws_route.internet,
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy.ecr_pull,
    aws_vpc_security_group_egress_rule.outbound,
  ]
}
