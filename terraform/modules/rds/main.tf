locals {
  service  = "rds"
  db_name  = coalesce(var.db_name, var.name)
  username = local.db_name

  tags = merge(var.common_tags, {
    Service = local.service
  })
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project}-${var.environment}-${var.name}"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-${var.name}-subnet-group"
  })
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "postgres" {
  name                    = "${var.project}/${var.environment}/rds/${var.name}-credentials"
  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    username = local.username
    password = random_password.postgres.result
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = aws_db_instance.postgres.db_name
    engine   = "postgres"
  })
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project}-${var.environment}-${var.name}"
  db_name    = local.db_name

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class

  allocated_storage     = var.postgres_allocated_storage
  max_allocated_storage = var.postgres_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  username = local.username
  password = random_password.postgres.result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [var.postgres_security_group_id]
  publicly_accessible    = false

  multi_az                     = var.postgres_multi_az
  performance_insights_enabled = true

  backup_retention_period = var.postgres_backup_retention_period
  backup_window           = var.postgres_backup_window
  maintenance_window      = var.postgres_maintenance_window

  deletion_protection       = true
  delete_automated_backups  = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-${var.environment}-${var.name}-final-snapshot"
  copy_tags_to_snapshot     = true

  allow_major_version_upgrade = true
  apply_immediately           = true

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-${var.name}"
  })
}
