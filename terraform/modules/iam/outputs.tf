output "cicd_role_arns" {
  value = { for k, v in aws_iam_role.cicd : k => v.arn }
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.cicd : k => v.repository_url }
}

output "github_oidc_provider_arn" {
  value = length(aws_iam_openid_connect_provider.github) > 0 ? aws_iam_openid_connect_provider.github[0].arn : null
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_execution_role_name" {
  value = aws_iam_role.ecs_task_execution.name
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  value = aws_iam_role.ecs_task.name
}
