resource "aws_vpc" "default" {
  cidr_block = local.vpc_cidr

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "vpc-${var.environment}"
  })
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id

  tags = merge(local.tags, {
    Name = "igw-${var.environment}"
  })
}

resource "aws_eip" "nat_subnet_1" {
  tags = merge(local.tags, {
    Name = "eip-nat-subnet-1-${var.environment}"
  })
}

resource "aws_eip" "nat_subnet_2" {
  tags = merge(local.tags, {
    Name = "eip-nat-subnet-2-${var.environment}"
  })
}

resource "aws_nat_gateway" "public_subnet_1" {
  allocation_id = aws_eip.nat_subnet_1.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = merge(local.tags, {
    Name = "nat-gw-1-${var.environment}"
  })
}

resource "aws_nat_gateway" "public_subnet_2" {
  allocation_id = aws_eip.nat_subnet_2.id
  subnet_id     = aws_subnet.public_subnet_2.id

  tags = merge(local.tags, {
    Name = "nat-gw-2-${var.environment}"
  })
}

resource "aws_security_group" "postgres" {
  name        = "${var.environment}-postgres"
  description = "Allow PostgreSQL inbound traffic from VPC"
  vpc_id      = aws_vpc.default.id

  tags = merge(local.tags, {
    Name = "${var.environment}-postgres-sg"
  })
}

resource "aws_security_group_rule" "postgres_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = aws_security_group.postgres.id
}

resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.environment}-alb-sg"
  })
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.environment}-ecs-tasks"
  description = "Allow inbound traffic from ALB to ECS tasks"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.environment}-ecs-tasks-sg"
  })
}
