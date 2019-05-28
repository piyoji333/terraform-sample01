provider "aws" {
    region = "ap-northeast-1"
}

resource "aws_vpc" "testerVPC" {
  cidr_block = "10.10.0.0/21"
    instance_tenancy = "default"
    enable_dns_support = "true"
    enable_dns_hostnames = "true"
  tags {
    Name = "testerVPC"
  }
}

resource "aws_internet_gateway" "testerGW" {
   vpc_id = "${aws_vpc.testerVPC.id}"

}

resource "aws_subnet" "public-a" {
   vpc_id = "${aws_vpc.testerVPC.id}"
   cidr_block = "10.10.1.0/24"
   availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "public-d" {
   vpc_id = "${aws_vpc.testerVPC.id}"
   cidr_block = "10.10.2.0/24"
   availability_zone = "ap-northeast-1d"
}

resource "aws_subnet" "praivate-a" {
   vpc_id = "${aws_vpc.testerVPC.id}"
   cidr_block = "10.10.5.0/24"
   availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "praivate-d" {
   vpc_id = "${aws_vpc.testerVPC.id}"
   cidr_block = "10.10.6.0/24"
   availability_zone = "ap-northeast-1d"
}

resource "aws_route_table" "public-route" {
   vpc_id = "${aws_vpc.testerVPC.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.testerGW.id}"
    }
}

resource "aws_route_table_association" "puclic-a" {
    subnet_id = "${aws_subnet.public-a.id}"
    route_table_id = "${aws_route_table.public-route.id}"
}

resource "aws_route_table_association" "puclic-d" {
    subnet_id = "${aws_subnet.public-d.id}"
    route_table_id = "${aws_route_table.public-route.id}"
}

resource "aws_security_group" "elb-sg" {
    name = "elb-sg"
    description = "Allow HTTP inbound traffic"
    vpc_id = "${aws_vpc.testerVPC.id}"
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "web-sg" {
    name = "web-sg"
    description = "Allow ssh inbound traffic"
    vpc_id = "${aws_vpc.testerVPC.id}"
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        prefix_list_ids = ["${aws_security_group.elb-sg.id}"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_instance" "web1" {
    ami = "ami-00d101850e971728d"
    instance_type = "t3.nano"
    key_name = "test"
    vpc_security_group_ids = [
      "${aws_security_group.web-sg.id}"
    ]
    subnet_id = "${aws_subnet.public-a.id}"
    associate_public_ip_address = "true"
    root_block_device = {
      volume_type = "gp2"
      volume_size = "8"
    }
    tags {
        Name = "web1"
    }
}

resource "aws_instance" "web2" {
    ami = "ami-00d101850e971728d"
    instance_type = "t3.nano"
    key_name = "test"
    vpc_security_group_ids = [
      "${aws_security_group.web-sg.id}"
    ]
    subnet_id = "${aws_subnet.public-d.id}"
    associate_public_ip_address = "true"
    root_block_device = {
      volume_type = "gp2"
      volume_size = "8"
    }
    tags {
        Name = "web2"
    }
}

resource "aws_alb" "testeralb" {
  name               = "tester-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.elb-sg.id}"]
  subnets            = ["${aws_subnet.public-a.id}"]
  subnets            = ["${aws_subnet.public-d.id}"]

  enable_deletion_protection = false

  access_logs {
    bucket = "aiueokakiku"
  }
 
  tags {
    Environment = "Prd"
  }
}

resource "aws_alb_target_group" "tester-lb" {
  name = "tester-lb"
  port = 80
  protocol = "HTTP"
  vpc_id = "${aws_vpc.testerVPC.id}"
 
  health_check {
    interval = 30
    path = "/index.html"
    port = 80
    protocol = "HTTP"
    timeout = 5
    unhealthy_threshold = 2
    matcher = 200
  }
}

resource "aws_alb_target_group_attachment" "alb-atache-web1" {
  count            = 2
  target_group_arn = "${aws_alb_target_group.tester-lb.arn}"
  target_id        = "${aws_instance.web1.id}"
  port             = 80
}

resource "aws_alb_target_group_attachment" "alb-atache-web2" {
  count            = 2
  target_group_arn = "${aws_alb_target_group.tester-lb.arn}"
  target_id        = "${aws_instance.web2.id}"
  port             = 80
}

resource "aws_alb_listener" "tester-lb" {
  load_balancer_arn = "${aws_alb.testeralb.arn}"
  port = "80"
  protocol = "HTTP"
 
  default_action {
    target_group_arn = "${aws_alb_target_group.tester-lb.arn}"
    type = "forward"
  }
}

resource "aws_alb_listener_rule" "testerweb" {
  listener_arn = "${aws_alb_listener.tester-lb.arn}"
  priority = 100
 
  action {
   type = "forward"
   target_group_arn = "${aws_alb_target_group.tester-lb.arn}"
 }
 
  condition {
    field = "path-pattern"
    values = ["/target/*"]
  }
}

####RDS#######



resource "aws_security_group" "db" {
    name = "db-sg"
    description = "for mysql"
    vpc_id = "${aws_vpc.testerVPC.id}"
    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        cidr_blocks = ["10.10.0.0/21"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_db_subnet_group" "dbsubnet" {
    name        = "tf_dbsubnet"
    description = "It is a DB subnet group on tf_vpc."
    subnet_ids  = ["${aws_subnet.praivate-d.id}", "${aws_subnet.praivate-a.id}"]
    tags {
        Name = "dbsubnet"
    }
}

resource "aws_db_parameter_group" "db-pg" {
    name = "rds-pg"
    family = "mysql5.7"
    description = "Managed by Terraform"

    parameter {
      name = "time_zone"
      value = "Asia/Tokyo"
    }
}

resource "aws_db_instance" "db" {
    identifier              = "dbinstance"
    allocated_storage       = 5
    engine                  = "mysql"
    engine_version          = "5.7.22"
    instance_class          = "db.t3.micro"
    storage_type            = "gp2"
    username                = "admin"
    password                = "adminadmin"
    parameter_group_name = "${aws_db_parameter_group.db-pg.name}"
    publicly_accessible     = true
    multi_az = true
    backup_retention_period = "7"
    backup_window = "19:00-19:30"
    vpc_security_group_ids  = ["${aws_security_group.db.id}"]
    db_subnet_group_name    = "${aws_db_subnet_group.dbsubnet.name}"
}

output "rds_endpoint" {
    value = "${aws_db_instance.db.address}"
}