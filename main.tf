terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34"
    }
  }
}

provider "aws" {
  region     = "${var.AWS_REGION}"
  access_key = "${var.AWS_ACCESS_KEY}"
  secret_key = "${var.AWS_SECRET_KEY}"
}

# Criando VPC, Subnets e Componentes
resource "aws_vpc" "deepesg_main" {
  cidr_block = "128.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "deepesg-main"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.deepesg_main.id
  cidr_block              = "128.0.1.0/24"
  availability_zone       = "sa-east-1a" 
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.deepesg_main.id
  cidr_block              = "128.0.2.0/24"
  availability_zone       = "sa-east-1b" 
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.deepesg_main.id
  cidr_block        = "128.0.3.0/24"
  availability_zone = "sa-east-1a" 

  tags = {
    Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.deepesg_main.id
  cidr_block        = "128.0.4.0/24"
  availability_zone = "sa-east-1b" 

  tags = {
    Name = "private-subnet-b"
  }
}

resource "aws_internet_gateway" "deepesg_gw" {
  vpc_id = aws_vpc.deepesg_main.id

  tags = {
    Name = "gw-deepesg"
  }
}

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.deepesg_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.deepesg_gw.id
  }

  tags = {
    Name = "public-rtb"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rtb.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rtb.id
}

#Criando Security Group

resource "aws_security_group" "deepesg_sg" {
  name        = "deppesg-sg"
  description = "Security group to allow all traffic from a specific IP and all egress traffic."
  vpc_id      = "${aws_vpc.deepesg_main.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["IP.DA.SUA.MAQUINA/32"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_vpc.deepesg_main.cidr_block}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "deppesg-sg"
  }
}


# Criando DB PostgreSQL e Subnet Group

resource "aws_db_subnet_group" "deep_app_db_subg" {
  name       = "deep-db-subnet-group"
  subnet_ids = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]

  tags = {
    Name = "deep-db-subnet-group"
  }
}

resource "aws_db_instance" "deepesg_db" {
  identifier        = "deepesg-db"
  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = "db.t3.micro"
  allocated_storage = 20  
  username          = "${var.DB_USER}"
  password          = "${var.DB_PASS}"
  db_name           = "${var.DB_NAME}"  
  apply_immediately = true
  publicly_accessible = false
  skip_final_snapshot = true

  vpc_security_group_ids = [
    "${aws_security_group.deepesg_sg.id}" 
  ]

  db_subnet_group_name = "${aws_db_subnet_group.deep_app_db_subg.name}"

  tags = {
    Name = "deepesg-db"
  }

  backup_retention_period = 0  
  multi_az                = false  
  storage_type            = "gp2"  
}

#Criando chave para acesso SSH

resource "aws_key_pair" "deepesg_key" {
  key_name = "deepesg-key"
  public_key = "${var.PUBLIC_KEY}"

}

#Criando Instancia

resource "aws_instance" "deepesg-app-runner" {
  ami           = "ami-01a38093d387a7497" 
  instance_type = "t2.micro"               
  subnet_id = "${aws_subnet.public_a.id}"
  key_name = "${aws_key_pair.deepesg_key.key_name}"
  vpc_security_group_ids = ["${aws_security_group.deepesg_sg.id}"]

  tags = {
    Name = "deepesg-app-runner"
  }

  root_block_device {
    volume_size = 20 
    volume_type = "gp2"
  }
  connection {
    type        = "ssh"
    user        = "ubuntu" 
    private_key = file("${var.PRIVATE_KEY_PATH}") 
    host        = self.public_ip
  }

  provisioner "file" { 
     source = "install-deps.sh"
     destination = "/tmp/install-deps.sh"
   }

  provisioner "file" { 
     source = "docker-compose.yml"
     destination = "/tmp/docker-compose.yml"
   }    


  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-deps.sh",
      "/tmp/install-deps.sh",
      "cd /tmp",
      "sudo docker-compose up -d"

    ]
   }
}

#Criando Load Balancer e Componentes

resource "aws_lb" "deepesg_lb" {
  name               = "deepesg-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.deepesg_sg.id]
  subnets            = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"] 

  enable_deletion_protection = false
  enable_http2              = true

  tags = {
    Name = "deepesg-lb"
  }
}

resource "aws_lb_target_group" "deepesg_tg" {
  name     = "deepesg-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.deepesg_main.id}" 

  health_check {
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold    = 2
    unhealthy_threshold  = 5
  }

  target_type = "instance"

  tags = {
    Name = "deepesg-tg"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = "${aws_lb.deepesg_lb.arn}"
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.deepesg_tg.arn}"
  }
}

resource "aws_lb_target_group_attachment" "deepesg_tga" {
  target_group_arn = aws_lb_target_group.deepesg_tg.arn
  target_id        = aws_instance.deepesg-app-runner.id
  port             = 80
}

output "alb_dns_name" {
  value = aws_lb.deepesg_lb.dns_name
}







