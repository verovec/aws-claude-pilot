resource "aws_iam_role" "cicd" {
  for_each = local.repositories

  name = "${var.project}-${var.environment}-cicd-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.github_oidc_provider}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.github_oidc_provider}:sub" = "repo:${var.github_org}/${each.key}:*"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cicd_ecr" {
  for_each = local.repositories

  role       = aws_iam_role.cicd[each.key].name
  policy_arn = aws_iam_policy.cicd_ecr_rw[0].arn
}

resource "aws_iam_role_policy_attachment" "cicd_ecs_deploy" {
  for_each = local.repositories

  role       = aws_iam_role.cicd[each.key].name
  policy_arn = aws_iam_policy.cicd_ecs_deploy[0].arn
}

resource "aws_iam_policy" "cicd_ecs_deploy" {
  count = local.cicd_enabled ? 1 : 0

  name = "${var.project}-${var.environment}-cicd-ecs-deploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSDeployServices"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks"
        ]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:service/${var.project}-${var.environment}/*",
          "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:cluster/${var.project}-${var.environment}",
          "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:task/${var.project}-${var.environment}/*"
        ]
      },
      {
        Sid      = "ECSDescribeTaskDefinitions"
        Effect   = "Allow"
        Action   = "ecs:DescribeTaskDefinition"
        Resource = "*"
      },
      {
        Sid    = "PassRoleForECSDeploy"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}
