resource "aws_subnet" "public_subnet_1" {
  vpc_id = aws_vpc.default.id

  cidr_block = local.public_subnets[0]

  availability_zone = "${var.aws_region}a"

  tags = merge(local.tags, {
    Name = "public-subnet-1-${var.environment}"
    Type = "public"
  })
}

resource "aws_route_table" "public_subnet_1" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = merge(local.tags, {
    Name = "public-subnet-1-route-table-${var.environment}"
  })
}

resource "aws_route_table_association" "public_subnet_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_subnet_1.id
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id = aws_vpc.default.id

  cidr_block = local.public_subnets[1]

  availability_zone = "${var.aws_region}b"

  tags = merge(local.tags, {
    Name = "public-subnet-2-${var.environment}"
    Type = "public"
  })
}

resource "aws_route_table" "public_subnet_2" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = merge(local.tags, {
    Name = "public-subnet-2-route-table-${var.environment}"
  })
}

resource "aws_route_table_association" "public_subnet_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_subnet_2.id
}
