locals {
  service = "acm"

  full_domain     = "${var.subdomain_prefix}.${var.domain_name}"
  wildcard_domain = "*.${local.full_domain}"

  tags = merge(var.common_tags, {
    Service = local.service
  })
}

resource "aws_acm_certificate" "main" {
  domain_name               = local.full_domain
  subject_alternative_names = var.create_wildcard ? [local.wildcard_domain] : []
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, {
    Name = local.full_domain
  })
}

resource "aws_route53_record" "validation" {
  provider = aws.route53

  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
