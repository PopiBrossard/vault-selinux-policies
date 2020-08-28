provider "aws" {
  version = "~> 2.32"
  region = var.region
}

variable "region" {
  description = "Region for AWS"
  type = string
  default = "us-east-1"
}

variable "name" {
  description = "Prefix name for stuff"
  type = string
  default = "test"
}

variable "pub_key_file" {
  description = "File location of the SSH pub key"
  type = string
  default = "~/.ssh/id_rsa.pub"
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.38.0.0/16"

  tags = {
    Name = "${var.name} VPC"
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.38.1.0/24"
  // changing this to "false" requires to always
  // manually specify if nodes should have public IPs...
  //
  // also, without this, the vault/consul servers
  // don't have access to the internet
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name} pub subnet",
  }
}

resource "aws_eip" "eip" {
  vpc = true
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.name} IGW",
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.gateway.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public_subnet" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_key_pair" "ssh" {
  key_name_prefix   = var.name
  public_key = file(pathexpand(var.pub_key_file))
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_ami" "centos" {
  owners      = ["679593333241"]
  most_recent = true

  filter {
      name   = "name"
      values = ["CentOS Linux 7 x86_64 HVM EBS *"]
  }

  filter {
      name   = "architecture"
      values = ["x86_64"]
  }

  filter {
      name   = "root-device-type"
      values = ["ebs"]
  }
}

resource "aws_security_group" "ssh" {
  name = "${var.name} sg"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "ssh" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ssh.id
}

resource "aws_security_group_rule" "outbound" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ssh.id
}

resource "aws_security_group_rule" "allow_api_inbound_from_self" {
  type = "ingress"
  from_port = "8200"
  to_port = "8200"
  protocol = "tcp"
  self = true
  security_group_id = aws_security_group.ssh.id
}

resource "aws_security_group_rule" "allow_cluser_inbound_from_self" {
  type = "ingress"
  from_port = "8201"
  to_port = "8201"
  protocol = "tcp"
  self = true
  security_group_id = aws_security_group.ssh.id
}

resource "aws_security_group_rule" "allow_http_inbound_from_self" {
  type = "ingress"
  from_port = "80"
  to_port = "80"
  protocol = "tcp"
  self = true
  security_group_id = aws_security_group.ssh.id
}

data "template_file" "user_data" {
  template = file("user-data-vault.sh")
}

resource "aws_instance" "instance" {
  ami = data.aws_ami.centos.id
  instance_type = "t2.medium"
  key_name = aws_key_pair.ssh.key_name
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = ["${aws_security_group.ssh.id}"]
  user_data = data.template_file.user_data.rendered
}

# resource "aws_instance" "instance2" {
#   ami = data.aws_ami.centos.id
#   instance_type = "t2.medium"
#   key_name = aws_key_pair.ssh.key_name
#   subnet_id = aws_subnet.public.id
#   vpc_security_group_ids = ["${aws_security_group.ssh.id}"]
#   user_data = data.template_file.user_data.rendered
# }

output "instance_ip" {
  value = aws_instance.instance.public_ip
}

output "instance_ip_private" {
  value = aws_instance.instance.private_ip
}

# output "instance2_ip" {
#   value = aws_instance.instance2.public_ip
# }
#
# output "instance2_ip_private" {
#   value = aws_instance.instance2.private_ip
# }

output "instance_az" {
  value = aws_instance.instance.availability_zone
}

# output "instance2_az" {
#   value = aws_instance.instance2.availability_zone
# }

output "vpc_id" {
  value = aws_vpc.vpc.id
}
