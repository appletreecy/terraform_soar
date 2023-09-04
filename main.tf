provider "aws" {
  region     = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

variable "access_key" {
  description = "The aws access_key"
  type        = string
}
variable "secret_key" {
  description = "The aws secret_key"
  type        = string
}

# 1. Create vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}
# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}
# 3. Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "Prod"
  }
}
# 4. Create a Subnet 

resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet-1"
  }
}

# Create another subnet
resource "aws_subnet" "subnet-2" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "prod-subnet-2"
  }
}

# Create the subnet Group
resource "aws_db_subnet_group" "db_subnet_group_1" {
  name       = "db-subnet-group-1"
  subnet_ids = [aws_subnet.subnet-1.id, aws_subnet.subnet-2.id]
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet-2.id
  route_table_id = aws_route_table.prod-route-table.id
}


# 6. Create Security Group to allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Postgres-port"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "all-port"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}

# 7.5 Sleep for 10 seconds
# resource "time_sleep" "wait_10_seconds" {
#   create_duration = "10s"
# }

# 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}


# 9. Create Ubuntu server and install/enable apache2

resource "aws_instance" "web-server-instance" {
  ami               = "ami-0b18e0c38e02712f1"
  instance_type     = "t2.medium"
  availability_zone = "us-east-1a"
  key_name          = "2023-0804"
  depends_on        = [aws_eip.one, aws_db_instance.default]

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  provisioner "file" {
    source      = "2023-0804.pem"
    destination = "/home/phantom/.ssh/2023-0804.pem"

    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/phantom/.ssh/2023-0804.pem",
      "sudo yum -y install epel-release",
      "sudo yum -y install ansible",
      "git clone https://github.com/appletreecy/ansible_soar_cluster.git",
      "export MY_VAR=${local.rds_db_address}",
      "export MY_LBDNS=${local.lb_dns_address}",
      "echo export MY_VAR=$MY_VAR >> /home/phantom/.bash_profile",
      "echo export MY_LBDNS=$MY_VAR >> /home/phantom/.bash_profile",
      "echo ${local.rds_db_address} > /home/phantom/1.conf",
      "echo ${local.lb_dns_address} > /home/phantom/2.conf",
      "sh /home/phantom/ansible_soar_cluster/scao_known_hosts.sh",
      "/usr/bin/ansible-playbook -i /home/phantom/ansible_soar_cluster/inventory.ini /home/phantom/ansible_soar_cluster/site.yml",
      "/usr/bin/ansible-playbook -i /home/phantom/ansible_soar_cluster/inventory.ini /home/phantom/ansible_soar_cluster/post_conf.yml"
    ]
    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }

  }

  # provisioner "local-exec" {
  #   command     = "ansible-playbook -i inventory.ini site.yml"
  #   working_dir = "/home/phantom/ansible_soar_cluster"
  # }

  # provisioner "local-exec" {
  #   command     = "ansible-playbook -i inventory.ini post_conf.yml"
  #   working_dir = "/home/phantom/ansible_soar_cluster"
  # }

  tags = {
    Name = "soar-server"
  }
}

output "server_private_ip" {
  value = aws_instance.web-server-instance.private_ip

}

output "server_id" {
  value = aws_instance.web-server-instance.id
}

# Setup the second SOAR server
# Create a network interface with an ip in the subnet 

resource "aws_network_interface" "soar-server-nic-1" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.51"]
  security_groups = [aws_security_group.allow_web.id]

}

# Assign an elastic IP to the network interface
resource "aws_eip" "one-1" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.soar-server-nic-1.id
  associate_with_private_ip = "10.0.1.51"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip-1" {
  value = aws_eip.one-1.public_ip
}

# Create SOAR server-1

resource "aws_instance" "soar-server-instance-1" {
  ami               = "ami-0b18e0c38e02712f1"
  instance_type     = "t2.medium"
  availability_zone = "us-east-1a"
  key_name          = "2023-0804"
  depends_on        = [aws_eip.one-1]

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.soar-server-nic-1.id
  }

  provisioner "file" {
    source      = "2023-0804.pem"
    destination = "/home/phantom/.ssh/2023-0804.pem"

    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/phantom/.ssh/2023-0804.pem"
    ]
    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }
  }

  tags = {
    Name = "soar-server-1"
  }

}

output "server_private_ip-1" {
  value = aws_instance.soar-server-instance-1.private_ip

}

output "server_id-1" {
  value = aws_instance.soar-server-instance-1.id
}

# Setup the third SOAR server
# Create a network interface with an ip in the subnet 

resource "aws_network_interface" "soar-server-nic-2" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.52"]
  security_groups = [aws_security_group.allow_web.id]

}

# Assign an elastic IP to the network interface
resource "aws_eip" "one-2" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.soar-server-nic-2.id
  associate_with_private_ip = "10.0.1.52"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip-2" {
  value = aws_eip.one-2.public_ip
}

# Create SOAR server-2

resource "aws_instance" "soar-server-instance-2" {
  ami               = "ami-0b18e0c38e02712f1"
  instance_type     = "t2.medium"
  availability_zone = "us-east-1a"
  key_name          = "2023-0804"
  depends_on        = [aws_eip.one-2]

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.soar-server-nic-2.id
  }

  provisioner "file" {
    source      = "2023-0804.pem"
    destination = "/home/phantom/.ssh/2023-0804.pem"

    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/phantom/.ssh/2023-0804.pem"
    ]
    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }

  }

  tags = {
    Name = "soar-server-2"
  }
}

# Setup the forth SOAR server
# Create a network interface with an ip in the subnet 

resource "aws_network_interface" "soar-server-nic-3" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.53"]
  security_groups = [aws_security_group.allow_web.id]

}

# Assign an elastic IP to the network interface
resource "aws_eip" "one-3" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.soar-server-nic-3.id
  associate_with_private_ip = "10.0.1.53"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip-3" {
  value = aws_eip.one-3.public_ip
}

# Create SOAR server-3

resource "aws_instance" "soar-server-instance-3" {
  ami               = "ami-0b18e0c38e02712f1"
  instance_type     = "t2.medium"
  availability_zone = "us-east-1a"
  key_name          = "2023-0804"
  depends_on        = [aws_eip.one-3]

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.soar-server-nic-3.id
  }

  provisioner "file" {
    source      = "2023-0804.pem"
    destination = "/home/phantom/.ssh/2023-0804.pem"

    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/phantom/.ssh/2023-0804.pem"
    ]
    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }

  }

  tags = {
    Name = "soar-server-3"
  }
}

output "server_private_ip-3" {
  value = aws_instance.soar-server-instance-3.private_ip

}

output "server_id-3" {
  value = aws_instance.soar-server-instance-3.id
}

# Setup the fifth SOAR server
# Create a network interface with an ip in the subnet 

resource "aws_network_interface" "soar-server-nic-4" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.54"]
  security_groups = [aws_security_group.allow_web.id]

}

# Assign an elastic IP to the network interface
resource "aws_eip" "one-4" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.soar-server-nic-4.id
  associate_with_private_ip = "10.0.1.54"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip-4" {
  value = aws_eip.one-4.public_ip
}

# Create SOAR server-4

resource "aws_instance" "soar-server-instance-4" {
  ami               = "ami-0b18e0c38e02712f1"
  instance_type     = "t2.medium"
  availability_zone = "us-east-1a"
  key_name          = "2023-0804"
  depends_on        = [aws_eip.one-4]

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.soar-server-nic-4.id
  }

  provisioner "file" {
    source      = "2023-0804.pem"
    destination = "/home/phantom/.ssh/2023-0804.pem"

    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/phantom/.ssh/2023-0804.pem"
    ]
    connection {
      type        = "ssh"
      user        = "phantom"
      private_key = file("2023-0804.pem")
      host        = self.public_ip
    }

  }

  tags = {
    Name = "soar-server-4"
  }
}

output "server_private_ip-4" {
  value = aws_instance.soar-server-instance-4.private_ip

}

output "server_id-4" {
  value = aws_instance.soar-server-instance-4.id
}

output "server_private_ip-2" {
  value = aws_instance.soar-server-instance-2.private_ip

}

output "server_id-2" {
  value = aws_instance.soar-server-instance-2.id
}

# Create a new Application load balancer 
resource "aws_lb" "soar-lb" {
  name               = "test-lb-soar"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web.id]
  subnets            = [aws_subnet.subnet-1.id, aws_subnet.subnet-2.id]

  enable_deletion_protection = false

  # access_logs {
  #   bucket  = aws_s3_bucket.lb_logs.bucket
  #   prefix  = "test-lb"
  #   enabled = true
  # }

  tags = {
    Environment = "production"
  }
}

#Configure the target group for port 443
resource "aws_lb_target_group" "https_service" {
  name     = "target-group-for-https-service"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.prod-vpc.id



  stickiness {
    type            = "lb_cookie"
    cookie_duration = 604800 # Session duration in seconds
  }

  health_check {
    path     = "/check" # Replace with the health check path for your application
    port     = 443      # Port to perform health checks on
    protocol = "HTTPS"
  }
}

#Configure the target group for port 9999
resource "aws_lb_target_group" "https_service_9999" {
  name     = "target-group-for-https-9999"
  port     = 9999
  protocol = "HTTPS"
  vpc_id   = aws_vpc.prod-vpc.id



  stickiness {
    type            = "lb_cookie"
    cookie_duration = 604800 # Session duration in seconds
  }

  health_check {
    path     = "/check" # Replace with the health check path for your application
    port     = 9999     # Port to perform health checks on
    protocol = "HTTPS"
  }
}

# attach the EC2 instance to the target group
resource "aws_lb_target_group_attachment" "attchment-1" {
  target_group_arn = aws_lb_target_group.https_service.arn
  target_id        = aws_instance.soar-server-instance-1.id
  port             = 443
}

resource "aws_lb_target_group_attachment" "attchment-2" {
  target_group_arn = aws_lb_target_group.https_service.arn
  target_id        = aws_instance.soar-server-instance-2.id
  port             = 443
}

resource "aws_lb_target_group_attachment" "attchment-3" {
  target_group_arn = aws_lb_target_group.https_service.arn
  target_id        = aws_instance.soar-server-instance-3.id
  port             = 443
}

# attach the EC2 instance to the target group for https port 9999
resource "aws_lb_target_group_attachment" "attchment-1-9999" {
  target_group_arn = aws_lb_target_group.https_service.arn
  target_id        = aws_instance.soar-server-instance-1.id
  port             = 9999
}

resource "aws_lb_target_group_attachment" "attchment-2-9999" {
  target_group_arn = aws_lb_target_group.https_service.arn
  target_id        = aws_instance.soar-server-instance-2.id
  port             = 9999
}

resource "aws_lb_target_group_attachment" "attchment-3-9999" {
  target_group_arn = aws_lb_target_group.https_service.arn
  target_id        = aws_instance.soar-server-instance-3.id
  port             = 9999
}

#configure lb listener
resource "aws_lb_listener" "front_end_listener" {
  load_balancer_arn = aws_lb.soar-lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:768298382555:certificate/cee27c32-022a-4c16-9715-92baab8bbf8a"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https_service.arn

  }
}

#configure lb listener for https port 9999
resource "aws_lb_listener" "front_end_listener_9999" {
  load_balancer_arn = aws_lb.soar-lb.arn
  port              = "9999"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:768298382555:certificate/cee27c32-022a-4c16-9715-92baab8bbf8a"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https_service.arn

  }
}

# add one listener rule to the elb
resource "aws_lb_listener_rule" "static-path" {
  listener_arn = aws_lb_listener.front_end_listener_9999.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https_service_9999.arn

  }
  condition {
    path_pattern {
      values = ["/websocket"]
    }
  }


}

#create the EFS File System
resource "aws_efs_file_system" "soar-cluster-efs" {
  creation_token = "soar-efs"

  tags = {
    Name = "soar-efs-name"
  }
}

#create the efs mount target
resource "aws_efs_mount_target" "alpha" {
  file_system_id  = aws_efs_file_system.soar-cluster-efs.id
  subnet_id       = aws_subnet.subnet-1.id
  security_groups = [aws_security_group.allow_web.id]
  ip_address      = "10.0.1.98"
}

#create the efs access point
resource "aws_efs_access_point" "soar-efs-access-point" {
  file_system_id = aws_efs_file_system.soar-cluster-efs.id

}


#create the RDS
resource "aws_db_instance" "default" {
  allocated_storage     = 500
  max_allocated_storage = 1000
  db_name               = "phantom"
  engine                = "postgres"
  engine_version        = "11"
  instance_class        = "db.t2.medium"
  username              = "postgres"
  password              = "splunk3du"
  parameter_group_name  = "default.postgres11"
  skip_final_snapshot   = true
  multi_az              = false
  publicly_accessible   = false

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group_1.name
  vpc_security_group_ids = [aws_security_group.allow_web.id]

}

output "rds_db_address" {
  value = aws_db_instance.default.address
}

output "lb_dns_address" {
  value = aws_lb.soar-lb.dns_name
}

output "lb_dns_address_url" {
  value = "https://${aws_lb.soar-lb.dns_name}:443"
}

locals {
  rds_db_address = aws_db_instance.default.address
  lb_dns_address = aws_lb.soar-lb.dns_name
}
