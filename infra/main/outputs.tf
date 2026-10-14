output "aws_region" {
  value = "eu-central-1"
}

output "instance_id" {
  value = aws_instance.node.id
}

output "public_ip" {
  description = "May change after EC2 stop/start or replacement."
  value       = aws_instance.node.public_ip
}

output "website_url" {
  description = "The application becomes available after the Kubernetes deployment stage."
  value       = "http://${aws_instance.node.public_ip}"
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.images : name => repository.repository_url }
}

output "ssm_shell_command" {
  value = "aws ssm start-session --target ${aws_instance.node.id} --region eu-central-1 --profile terraform"
}

output "github_actions_variables" {
  description = "GitHub repository variables; none of these values are secrets."
  value = {
    AWS_ROLE_ARN          = aws_iam_role.github_actions.arn
    INSTANCE_ID           = aws_instance.node.id
    SERVER_URL            = "http://${aws_instance.node.public_ip}"
    ECR_REPOSITORY_PREFIX = var.project_name
  }
}
