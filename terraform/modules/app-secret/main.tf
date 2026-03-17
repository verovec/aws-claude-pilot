locals {
  service     = "app-secret"
  secret_name = "${var.project}/${var.environment}/${var.name}/${var.name}-credentials"

  placeholder = { for k in var.placeholder_keys : k => "PLACEHOLDER" }

  tags = merge(var.common_tags, {
    Service = local.service
  })
}

resource "aws_secretsmanager_secret" "main" {
  name                    = local.secret_name
  recovery_window_in_days = var.recovery_window_in_days

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "main" {
  secret_id     = aws_secretsmanager_secret.main.id
  secret_string = jsonencode(local.placeholder)

  lifecycle {
    ignore_changes = [secret_string]
  }
}
