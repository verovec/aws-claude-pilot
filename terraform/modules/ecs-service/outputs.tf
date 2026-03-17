output "service_name" {
  value = aws_ecs_service.main.name
}

output "service_arn" {
  value = aws_ecs_service.main.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.main.arn
}

output "target_group_arn" {
  value = local.has_alb ? aws_lb_target_group.main[0].arn : null
}
