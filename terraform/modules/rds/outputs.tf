output "endpoint" {
  value = aws_db_instance.postgres.address
}

output "port" {
  value = aws_db_instance.postgres.port
}

output "credentials_secret_arn" {
  value = aws_secretsmanager_secret.postgres.arn
}

output "credentials_secret_name" {
  value = aws_secretsmanager_secret.postgres.name
}

output "database_name" {
  value = aws_db_instance.postgres.db_name
}

output "identifier" {
  value = aws_db_instance.postgres.identifier
}
