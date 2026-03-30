# -----------------------------------------------------------------------------
# Platform modules -- shared infrastructure
# -----------------------------------------------------------------------------

module "kms" {
  source = "./modules/kms"

  project        = var.project
  environment    = var.environment
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
  common_tags    = local.common_tags
}

module "vpc" {
  source = "./modules/vpc"

  environment = var.environment
  aws_region  = var.aws_region
  common_tags = local.common_tags
}

module "ecs" {
  source = "./modules/ecs"

  project     = var.project
  environment = var.environment
  kms_key_arn = module.kms.key_arn
  common_tags = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  project        = var.project
  environment    = var.environment
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

  github_org          = var.github_org
  github_repositories = var.github_repositories

  s3_bucket_arns = [for k, v in module.s3 : v.bucket_arn]

  common_tags = local.common_tags
}

module "rds" {
  source   = "./modules/rds"
  for_each = var.postgres_databases

  project     = var.project
  environment = var.environment
  name        = each.key
  db_name     = try(each.value.db_name, null)

  private_subnet_ids         = module.vpc.private_subnet_ids
  postgres_security_group_id = module.vpc.postgres_security_group_id

  postgres_instance_class        = each.value.instance_class
  postgres_allocated_storage     = each.value.allocated_storage
  postgres_max_allocated_storage = each.value.max_allocated_storage

  kms_key_arn = module.kms.key_arn

  common_tags = local.common_tags
}

module "s3" {
  source   = "./modules/s3"
  for_each = toset(var.s3_buckets)

  project     = var.project
  environment = var.environment
  bucket_name = each.key

  kms_key_arn = module.kms.key_arn

  common_tags = local.common_tags
}

module "acm" {
  source = "./modules/acm"
  count  = var.acm_domain_name != "" && var.route53_zone_id != "" ? 1 : 0

  providers = {
    aws.route53 = aws.route53
  }

  environment      = var.environment
  domain_name      = var.acm_domain_name
  subdomain_prefix = var.acm_subdomain_prefix
  route53_zone_id  = var.route53_zone_id

  common_tags = local.common_tags
}

module "alb" {
  source = "./modules/alb"
  count  = length(module.acm) > 0 ? 1 : 0

  project               = var.project
  environment           = var.environment
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.vpc.alb_security_group_id
  acm_certificate_arn   = module.acm[0].certificate_arn
  common_tags           = local.common_tags
}

# -----------------------------------------------------------------------------
# Application secrets
# -----------------------------------------------------------------------------

module "app_secret" {
  source = "./modules/app-secret"

  project     = var.project
  environment = var.environment
  name        = "app"

  placeholder_keys = [
    "SECRET_KEY",
    "DATABASE_URL",
  ]

  common_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Application environment and secrets mapping
# -----------------------------------------------------------------------------

locals {
  app_rds_secret_arn = length(var.postgres_databases) > 0 ? module.rds[keys(var.postgres_databases)[0]].credentials_secret_arn : ""
  app_secret_arn     = module.app_secret.secret_arn

  app_env = {
    APP_ENVIRONMENT = var.environment
  }

  app_secrets = merge(
    local.app_rds_secret_arn != "" ? {
      DB_HOST     = "${local.app_rds_secret_arn}:host::"
      DB_PORT     = "${local.app_rds_secret_arn}:port::"
      DB_NAME     = "${local.app_rds_secret_arn}:dbname::"
      DB_USER     = "${local.app_rds_secret_arn}:username::"
      DB_PASSWORD = "${local.app_rds_secret_arn}:password::"
    } : {},
    {
      SECRET_KEY   = "${local.app_secret_arn}:SECRET_KEY::"
      DATABASE_URL = "${local.app_secret_arn}:DATABASE_URL::"
    }
  )
}

# -----------------------------------------------------------------------------
# ECS service -- template application
# -----------------------------------------------------------------------------

module "app" {
  source = "./modules/ecs-service"

  project                 = var.project
  environment             = var.environment
  name                    = "${var.project}-app"
  ecs_cluster_arn         = module.ecs.cluster_arn
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
  private_subnet_ids      = module.vpc.private_subnet_ids
  security_group_ids      = [module.vpc.ecs_tasks_security_group_id]
  log_group_name          = module.ecs.log_group_name
  aws_region              = var.aws_region

  container_image = var.app_image
  container_port  = 8080
  cpu             = var.app_cpu
  memory          = var.app_memory
  desired_count   = var.app_desired_count

  health_check_path         = "/health"
  health_check_start_period = 120

  environment_variables = local.app_env
  secrets               = local.app_secrets

  enable_alb            = length(module.alb) > 0
  vpc_id                = module.vpc.vpc_id
  alb_listener_arn      = length(module.alb) > 0 ? module.alb[0].https_listener_arn : null
  alb_path_pattern      = "/*"
  alb_listener_priority = 100

  common_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

module "monitoring" {
  source = "./modules/monitoring"

  project          = var.project
  environment      = var.environment
  aws_region       = var.aws_region
  application_name = var.project
  ecs_cluster_name = module.ecs.cluster_name
  log_group_name   = module.ecs.log_group_name

  ecs_services = {
    "app" = {
      service_name = module.app.service_name
      category     = "api"
    }
  }

  rds_instances = { for k, v in module.rds : k => v.identifier }

  common_tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Bastion
# -----------------------------------------------------------------------------

module "bastion" {
  source = "./modules/bastion"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  subnet_id                  = module.vpc.private_subnet_ids[0]
  postgres_security_group_id = module.vpc.postgres_security_group_id

  common_tags = local.common_tags
}
