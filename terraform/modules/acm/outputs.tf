output "certificate_arn" {
  value = aws_acm_certificate.main.arn
}

output "certificate_domain" {
  value = aws_acm_certificate.main.domain_name
}
