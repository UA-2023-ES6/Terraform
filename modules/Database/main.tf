resource "aws_db_subnet_group" "subnet_group" {
  name = "subnet_group"
  subnet_ids = "${element(aws_subnet.private_subnet.*.id, count.index)}"
  tags = {
    Name = "${var.environment}-subnet_group"
  }
}

resource "aws_db_instance" "database" {
  engine                 = "mysql"
  db_name                = "${var.environment}-RDS"
  identifier             = "example"
  instance_class         = "db.t4.micro"
  allocated_storage      = 20
  publicly_accessible    = false
  username               = "${var.db-username}"
  password               = "${var.db-password}"
  vpc_security_group_ids = [aws_security_group.All_Open.id]
  db_subnet_group_name = aws_db_subnet_group.subnet_group.name
  skip_final_snapshot    = true
  tags = {
    Name = "${var.environment}-RDS"
  }
}