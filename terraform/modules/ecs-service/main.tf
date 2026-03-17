locals {
  service = "ecs-service"
  family  = "${var.project}-${var.environment}-${var.name}"

  has_alb = var.enable_alb

  tags = merge(var.common_tags, {
    Service   = local.service
    Component = var.name
  })

  container_environment = [
    for k, v in var.environment_variables : {
      name  = k
      value = v
    }
  ]

  container_secrets = [
    for k, v in var.secrets : {
      name      = k
      valueFrom = v
    }
  ]

  health_check = var.health_check_path != null ? {
    command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
    interval    = var.health_check_interval
    timeout     = 5
    retries     = 3
    startPeriod = var.health_check_start_period
  } : null

  container_definition = {
    name      = var.name
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    command = var.command

    environment = local.container_environment
    secrets     = length(local.container_secrets) > 0 ? local.container_secrets : null

    healthCheck = local.health_check

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = var.name
      }
    }
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = local.family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory

  execution_role_arn = var.task_execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([local.container_definition])

  tags = local.tags
}

resource "aws_ecs_service" "main" {
  name                   = var.name
  cluster                = var.ecs_cluster_arn
  task_definition        = aws_ecs_task_definition.main.arn
  desired_count          = var.desired_count
  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
    base              = 1
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = var.security_group_ids
  }

  dynamic "load_balancer" {
    for_each = local.has_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.main[0].arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = local.tags
}

resource "aws_lb_target_group" "main" {
  count = local.has_alb ? 1 : 0

  name        = substr("tg-${var.environment}-${var.name}", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = var.health_check_interval
    matcher             = "200"
  }

  deregistration_delay = 30

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_lb_listener_rule" "main" {
  count = local.has_alb ? 1 : 0

  listener_arn = var.alb_listener_arn
  priority     = var.alb_listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }

  dynamic "condition" {
    for_each = var.alb_path_pattern != null ? [] : (var.alb_host != null ? [var.alb_host] : [])
    content {
      host_header {
        values = [condition.value]
      }
    }
  }

  dynamic "condition" {
    for_each = var.alb_path_pattern != null ? [var.alb_path_pattern] : []
    content {
      path_pattern {
        values = [condition.value]
      }
    }
  }

  tags = local.tags
}
