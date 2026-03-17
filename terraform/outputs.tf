output "kms_key_arn" {
  value = module.kms.key_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  value = module.ecs.cluster_arn
}

output "ecs_log_group_name" {
  value = module.ecs.log_group_name
}

output "ecs_task_execution_role_arn" {
  value = module.iam.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  value = module.iam.ecs_task_role_arn
}

output "postgres_endpoints" {
  value = { for k, v in module.rds : k => v.endpoint }
}

output "postgres_credentials_secret_arns" {
  value = { for k, v in module.rds : k => v.credentials_secret_arn }
}

output "s3_buckets" {
  value = { for k, v in module.s3 : k => v.bucket_id }
}

output "acm_certificate_arn" {
  value = length(module.acm) > 0 ? module.acm[0].certificate_arn : null
}

output "alb_dns_name" {
  value = length(module.alb) > 0 ? module.alb[0].dns_name : null
}

output "alb_https_listener_arn" {
  value = length(module.alb) > 0 ? module.alb[0].https_listener_arn : null
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}

output "app_secret_arn" {
  value = module.app_secret.secret_arn
}

output "ecr_repository_urls" {
  value = module.iam.ecr_repository_urls
}
