/*==== The VPC ======*/
resource "aws_vpc" "OneCampusVPC" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "${var.environment}VPC"
    Environment = "${var.environment}"
  }
}
/*==== Subnets ======*/
/* Internet gateway for the public subnet */
resource "aws_internet_gateway" "ig" {
  vpc_id = "${aws_vpc.OneCampusVPC.id}"
  tags = {
    Name        = "${var.environment}-igw"
    Environment = "${var.environment}"
  }
}
/* Elastic IP for NAT */
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}
/* NAT */
resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${element(aws_subnet.public_subnet.*.id, 0)}"
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    Name        = "nat"
    Environment = "${var.environment}"
  }
}
/* Public subnet */
resource "aws_subnet" "public_subnet" {
  vpc_id                  = "${aws_vpc.OneCampusVPC.id}"
  count                   = "${length(var.public_subnets_cidr)}"
  cidr_block              = "${element(var.public_subnets_cidr,   count.index)}"
  availability_zone       = "${element(var.availability_zones,   count.index)}"
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-      public-subnet"
    Environment = "${var.environment}"
  }
}
/* Private subnet */
resource "aws_subnet" "private_subnet" {
  vpc_id                  = "${aws_vpc.OneCampusVPC.id}"
  count                   = "${length(var.private_subnets_cidr)}"
  cidr_block              = "${element(var.private_subnets_cidr, count.index)}"
  availability_zone       = "${element(var.availability_zones,   count.index)}"
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-private-subnet"
    Environment = "${var.environment}"
  }
}
/* Routing table for private subnet */
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.OneCampusVPC.id}"
  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}
/* Routing table for public subnet */
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.OneCampusVPC.id}"
  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}
resource "aws_route" "public_internet_gateway" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.ig.id}"
}
resource "aws_route" "private_nat_gateway" {
  route_table_id         = "${aws_route_table.private.id}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${aws_nat_gateway.nat.id}"
}
/* Route table associations */
resource "aws_route_table_association" "public" {
  count          = "${length(var.public_subnets_cidr)}"
  subnet_id      = "${element(aws_subnet.public_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}
resource "aws_route_table_association" "private" {
  count          = "${length(var.private_subnets_cidr)}"
  subnet_id      = "${element(aws_subnet.private_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.private.id}"
}
/*==== VPC's Default Security Group ======*/
resource "aws_security_group" "All_Open" {
  name        = "All_Open"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = "${aws_vpc.OneCampusVPC.id}"
  depends_on  = [aws_vpc.OneCampusVPC]
  ingress {
    from_port = "443"
    to_port   = "443"
    protocol  = "tcp"
    self      = true
    cidr_blocks = [aws_vpc.OneCampusVPC.cidr_block]
  }
  
  ingress {
    from_port = "80"
    to_port   = "80"
    protocol  = "tcp"
    self      = true
    cidr_blocks = [aws_vpc.OneCampusVPC.cidr_block]
  }
  
  ingress {
    from_port = "3000"
    to_port   = "3000"
    protocol  = "tcp"
    self      = true
    cidr_blocks = [aws_vpc.OneCampusVPC.cidr_block]
  }
  
  ingress {
    from_port = "81"
    to_port   = "81"
    protocol  = "tcp"
    self      = true
    cidr_blocks = [aws_vpc.OneCampusVPC.cidr_block]
  }
  
  ingress {
    from_port = "3306"
    to_port   = "3306"
    protocol  = "tcp"
    self      = true
    cidr_blocks = [aws_vpc.OneCampusVPC.cidr_block]
  }
  
  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Environment = "${var.environment}"
  }
}

resource "aws_db_subnet_group" "subnet_group" {
  name = "subnet_group"
  subnet_ids = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
  tags = {
    Name = "${var.environment}-subnet_group"
  }
}

resource "aws_db_instance" "OneCampusRDS" {
  engine                 = "mysql"
  identifier             = "onecampusrds"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  publicly_accessible    = false
  username               = "admin"
  password               = "Strong!password0n"
  vpc_security_group_ids = [aws_security_group.All_Open.id]
  db_subnet_group_name = aws_db_subnet_group.subnet_group.name
  skip_final_snapshot    = true
  tags = {
    Name = "${var.environment}-RDS"
  }
}

resource "aws_alb" "OneCampusALB" {
  name               = "${var.environment}ALB"
  load_balancer_type = "application"
  internal           = true
  subnets = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
  security_groups = [aws_security_group.All_Open.id]
}

resource "aws_lb_target_group" "OneCampusUI-TG" {
  name        = "${var.environment}UI-TG"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_vpc.OneCampusVPC.id}"
}

resource "aws_lb_target_group" "OneCampusAPI-TG" {
  name        = "${var.environment}API-TG"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_vpc.OneCampusVPC.id}"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/OneCampus/src/OneCampus.Api/Monitoring/HealthCheck.cs"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 6
    matcher             = "200-499"
  }
}

resource "aws_lb_listener" "OneCampusUI-listener" {
  load_balancer_arn = aws_alb.OneCampusALB.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.OneCampusUI-TG.arn
  }
}

resource "aws_lb_listener" "OneCampusAPI-listener" {
  load_balancer_arn = aws_alb.OneCampusALB.arn
  port              = "81"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.OneCampusAPI-TG.arn
  }
}

resource "aws_apigatewayv2_api" "OneCampusAPIGW-UI" {
  name          = "${var.environment}-APIGW-UI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_vpc_link" "OneCampusVPCLINK" {
  name               = "${var.environment}VPCLINK"
  security_group_ids = [aws_security_group.All_Open.id]
  subnet_ids         = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
}

resource "aws_apigatewayv2_integration" "OneCampusUI-integration" {
  api_id           = aws_apigatewayv2_api.OneCampusAPIGW-UI.id
  integration_type = "HTTP_PROXY"
  integration_uri  = aws_lb_listener.OneCampusUI-listener.arn

  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.OneCampusVPCLINK.id
}

resource "aws_apigatewayv2_route" "OneCampusUI-route" {
  api_id    = aws_apigatewayv2_api.OneCampusAPIGW-UI.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.OneCampusUI-integration.id}"
}

resource "aws_apigatewayv2_stage" "OneCampusUI-stage" {
  api_id = aws_apigatewayv2_api.OneCampusAPIGW-UI.id
  name   = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_api" "OneCampusAPIGW-API" {
  name          = "${var.environment}-APIGW-API"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "OneCampusAPI-integration" {
  api_id           = aws_apigatewayv2_api.OneCampusAPIGW-API.id
  integration_type = "HTTP_PROXY"
  integration_uri  = aws_lb_listener.OneCampusAPI-listener.arn

  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.OneCampusVPCLINK.id
}

resource "aws_apigatewayv2_route" "OneCampusAPI-route" {
  api_id    = aws_apigatewayv2_api.OneCampusAPIGW-API.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.OneCampusAPI-integration.id}"
}

resource "aws_apigatewayv2_stage" "OneCampusAPI-stage" {
  api_id = aws_apigatewayv2_api.OneCampusAPIGW-API.id
  name   = "$default"
  auto_deploy = true
}

resource "aws_ecs_cluster" "OneCampusCluster" {
  name            = "OneCampusCluster"
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "OneCampusUI-td" {
  family = "OneCampusUI-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu       = 512
  memory    = 1024
  execution_role_arn       = "${data.aws_iam_role.ecs_task_execution_role.arn}"
  container_definitions = jsonencode([
    {
      name      = "onecampusui"
      image     = "866681751834.dkr.ecr.eu-west-3.amazonaws.com/onecampus-ui:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      environment: [
        {
          "name": "REACT_APP_COGNITO_USER_POOL_ID",
          "value": "eu-west-3_RCyvOEcpL"
        },
        {
          "name": "REACT_APP_COGNITO_CLIENT_ID",
          "value": "2j77lnu68bml9hvh4916b27rgk"
        },
        {
          "name": "REACT_APP_SERVER_API",
          "value": aws_apigatewayv2_stage.OneCampusAPI-stage.invoke_url
        }
      ]
    }
  ])
}

resource "aws_ecs_task_definition" "OneCampusAPI-td" {
  family = "OneCampusAPI-td"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu       = 512
  memory    = 1024
  execution_role_arn       = "${data.aws_iam_role.ecs_task_execution_role.arn}"
  container_definitions = jsonencode([
    {
      name      = "onecampusapi"
      image     = "866681751834.dkr.ecr.eu-west-3.amazonaws.com/onecampus-api"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
      environment: [
        {
          "name": "ConnectionStrings__OneCampusDb",
          "value": "server=${aws_db_instance.OneCampusRDS.address};port=3306;database=OneCampusDb;uid=admin;password=Strong!password0n"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "OneCampusUIService" {
  name            = "OneCampusUIService"
  cluster         = aws_ecs_cluster.OneCampusCluster.id
  task_definition = aws_ecs_task_definition.OneCampusUI-td.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.OneCampusUI-TG.arn
    container_name   = "onecampusui"
    container_port   = 3000
  }

  network_configuration {
    subnets = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
    security_groups = [aws_security_group.All_Open.id]
  }
}

resource "aws_ecs_service" "OneCampusAPIService" {
  name            = "OneCampusAPIService"
  cluster         = aws_ecs_cluster.OneCampusCluster.id
  task_definition = aws_ecs_task_definition.OneCampusAPI-td.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.OneCampusAPI-TG.arn
    container_name   = "onecampusapi"
    container_port   = 80
  }

  network_configuration {
    subnets = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]
    security_groups = [aws_security_group.All_Open.id]
  }
}