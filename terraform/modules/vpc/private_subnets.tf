resource "aws_subnet" "private_subnet_1" {
  vpc_id = aws_vpc.default.id

  cidr_block = local.private_subnets[0]

  availability_zone = "${var.aws_region}a"

  tags = merge(local.tags, {
    Name = "private-subnet-1-${var.environment}"
    Type = "private"
  })
}

resource "aws_route_table" "private_subnet_1" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public_subnet_1.id
  }

  tags = merge(local.tags, {
    Name = "private-subnet-1-route-table-${var.environment}"
  })
}

resource "aws_route_table_association" "private_subnet_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_subnet_1.id
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id = aws_vpc.default.id

  cidr_block = local.private_subnets[1]

  availability_zone = "${var.aws_region}b"

  tags = merge(local.tags, {
    Name = "private-subnet-2-${var.environment}"
    Type = "private"
  })
}

resource "aws_route_table" "private_subnet_2" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public_subnet_2.id
  }

  tags = merge(local.tags, {
    Name = "private-subnet-2-route-table-${var.environment}"
  })
}

resource "aws_route_table_association" "private_subnet_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_subnet_2.id
}
