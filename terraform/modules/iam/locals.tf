locals {
  service = "iam"

  tags = merge(var.common_tags, {
    Service = local.service
  })

  github_oidc_url      = "https://token.actions.githubusercontent.com"
  github_oidc_provider = "token.actions.githubusercontent.com"

  cicd_enabled = var.github_org != "" && length(var.github_repositories) > 0
  repositories = local.cicd_enabled ? toset(var.github_repositories) : toset([])
}
