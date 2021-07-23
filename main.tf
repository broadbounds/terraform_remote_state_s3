# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE AN S3 BUCKET AND DYNAMODB TABLE TO USE AS A TERRAFORM BACKEND
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 0.15.x. However, to make upgrading easier, we are setting
  # 0.12.26 as the minimum version, as that version added support for required_providers with source URLs, making it
  # forwards compatible with 0.15.x code.
  required_version = ">= 0.15.3"
}

# ------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ------------------------------------------------------------------------------

provider "aws" {
   region  = var.aws_region
   access_key = var.access_key
   secret_key = var.secret_key
}

# ------------------------------------------------------------------------------
# CREATE THE S3 BUCKET
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_state" {
  # TODO: change this to your own name! S3 bucket names must be *globally* unique.
  bucket = "broadbounds-terraform-remote-state-s3"

  # Enable versioning so we can see the full revision history of our
  # state files
  versioning {
    enabled = true
  }

  # Enable server-side encryption by default
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# ------------------------------------------------------------------------------
# CREATE THE DYNAMODB TABLE
# ------------------------------------------------------------------------------

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "broadbounds-terraform-remote-state-s3-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}


# ------------------------------------------------------------------------------
# CONFIGURE TERRAFORM BACKEND
# ------------------------------------------------------------------------------
terraform {
  backend "s3" {
    # Replace this with your bucket name!
    bucket         = "broadbounds-terraform-remote-state-s3"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-2"
    # Replace this with your DynamoDB table name!
    dynamodb_table = "broadbounds-terraform-remote-state-s3-locks"
    encrypt        = true
  }
  depends_on = [aws_s3_bucket.terraform_state, aws_dynamodb_table.terraform_locks]
}

# We create a new VPC
resource "aws_vpc" "vpc" {
   cidr_block = var.vpc_cidr_block
   instance_tenancy = "default"
   tags = {
      Name = "VPC"
   }
   enable_dns_hostnames = true
}

# We create a public subnet
# Instances will have a dynamic public IP and be accessible via the internet gateway
resource "aws_subnet" "public_subnet" {
   depends_on = [
      aws_vpc.vpc,
   ]
   vpc_id = aws_vpc.vpc.id
   cidr_block = var.public_subnet_cidr_block
   availability_zone_id = "use2-az1"
   tags = {
      Name = "public-subnet"
   }
   map_public_ip_on_launch = true
}

# We create a private subnet
# Instances will not be accessible via the internet gateway
resource "aws_subnet" "private_subnet" {
   depends_on = [
      aws_vpc.vpc,
   ]
   vpc_id = aws_vpc.vpc.id
   cidr_block = var.private_subnet_cidr_block
   availability_zone_id = "use2-az1"
   tags = {
      Name = "private-subnet"
   }
}

# We create an internet gateway
# Allows communication between our VPC and the internet
resource "aws_internet_gateway" "internet_gateway" {
   depends_on = [
      aws_vpc.vpc,
   ]
   vpc_id = aws_vpc.vpc.id
   tags = {
      Name = "internet-gateway",
   }
}

# We create a route table with target as our internet gateway and destination as "internet"
# Set of rules used to determine where network traffic is directed
resource "aws_route_table" "IG_route_table" {
   depends_on = [
      aws_vpc.vpc,
      aws_internet_gateway.internet_gateway,
   ]
   vpc_id = aws_vpc.vpc.id
   route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.internet_gateway.id
   }
   tags = {
      Name = "IG-route-table"
   }
}

# We associate our route table to the public subnet
# Makes the subnet public because it has a route to the internet via our internet gateway
resource "aws_route_table_association" "associate_routetable_to_public_subnet" {
   depends_on = [
      aws_subnet.public_subnet,
      aws_route_table.IG_route_table,
   ]
   subnet_id = aws_subnet.public_subnet.id
   route_table_id = aws_route_table.IG_route_table.id
}

# We create an elastic IP 
# A static public IP address that we can assign to any EC2 instance
resource "aws_eip" "elastic_ip" {
   vpc = true
}

# We create a NAT gateway with a required public IP
# Lives in a public subnet and prevents externally initiated traffic to our private subnet
# Allows initiated outbound traffic to the Internet or other AWS services
resource "aws_nat_gateway" "nat_gateway" {
   depends_on = [
      aws_subnet.public_subnet,
      aws_eip.elastic_ip,
   ]
   allocation_id = aws_eip.elastic_ip.id
   subnet_id = aws_subnet.public_subnet.id
   tags = {
      Name = "nat-gateway"
   }
}

# We create a route table with target as NAT gateway and destination as "internet"
# Set of rules used to determine where network traffic is directed
resource "aws_route_table" "NAT_route_table" {
   depends_on = [
      aws_vpc.vpc,
      aws_nat_gateway.nat_gateway,
   ]
   vpc_id = aws_vpc.vpc.id
   route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_nat_gateway.nat_gateway.id
   }
   tags = {
      Name = "NAT-route-table"
   }
}

# We associate our route table to the private subnet
# Keeps the subnet private because it has a route to the internet via our NAT gateway 
resource "aws_route_table_association" "associate_routetable_to_private_subnet" {
   depends_on = [
      aws_subnet.private_subnet,
      aws_route_table.NAT_route_table,
   ]
   subnet_id = aws_subnet.private_subnet.id
   route_table_id = aws_route_table.NAT_route_table.id
}

# We create a security group for SSH traffic
# EC2 instances' firewall that controls incoming and outgoing traffic
resource "aws_security_group" "sg_bastion_host" {
   depends_on = [
      aws_vpc.vpc,
   ]
   name = "sg bastion host"
   description = "bastion host security group"
   vpc_id = aws_vpc.vpc.id
   ingress {
      description = "allow ssh"
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
   }
   ingress {
      description = "allow cloudmapper"
      from_port = 8000
      to_port = 8000
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
   }   
   egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
   }
   tags = {
      Name = "sg bastion host"
   }
}

# We create an elastic IP 
# A static public IP address that we can assign to our bastion host
resource "aws_eip" "bastion_elastic_ip" {
   vpc = true
}

# We create an ssh key using the RSA algorithm with 4096 rsa bits
# The ssh key always includes the public and the private key
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# We upload the public key of our created ssh key to AWS
resource "aws_key_pair" "public_ssh_key" {
  key_name   = var.public_key_name
  public_key = tls_private_key.ssh_key.public_key_openssh

   depends_on = [tls_private_key.ssh_key]
}

# We save our public key at our specified path.
# Can upload on remote server for ssh encryption
resource "local_file" "save_public_key" {
  content = tls_private_key.ssh_key.public_key_openssh 
  filename = "${var.key_path}${var.public_key_name}.pem"
}

# We save our private key at our specified path.
# Allows private key instead of a password to securely access our instances
resource "local_file" "save_private_key" {
  content = tls_private_key.ssh_key.private_key_pem
  filename = "${var.key_path}${var.private_key_name}.pem"
}

data "template_file" "cloudmapper_script" {
  template = "${file("cloudmapper_script.sh")}"
  vars = {
    cloudmapper_access_key = var.cloudmapper_access_key
    cloudmapper_secret_key = var.cloudmapper_secret_key
    aws_account_name = var.aws_account_name
    aws_account_id = var.aws_account_id
    aws_region = var.aws_region
  }
}

# We create a bastion host
# Allows SSH into instances in private subnet
resource "aws_instance" "bastion_host" {
   depends_on = [
      aws_security_group.sg_bastion_host,
   ]
   ami = "ami-077e31c4939f6a2f3"
   instance_type = "t2.micro"
   key_name = aws_key_pair.public_ssh_key.key_name
   vpc_security_group_ids = [aws_security_group.sg_bastion_host.id]
   subnet_id = aws_subnet.public_subnet.id
   user_data = "" 
   tags = {
      Name = "bastion host"
   }
   provisioner "file" {
    source      = "${var.key_path}${var.private_key_name}.pem"
    destination = "/home/ec2-user/private_ssh_key.pem"

    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.ssh_key.private_key_pem
    host     = aws_instance.bastion_host.public_ip
    }
  }
}


# We associate the elastic ip to our bastion host
resource "aws_eip_association" "bastion_eip_association" {
  instance_id   = aws_instance.bastion_host.id
  allocation_id = aws_eip.bastion_elastic_ip.id
}


# We save our bastion host public ip in our inventory.ini file.
resource "local_file" "ip_addresses" {
  content = <<EOF
  [Bastion_CloudMapper_Server]
  ${aws_eip.bastion_elastic_ip.public_ip}
  EOF
  filename = "${var.key_path}inventory.ini"
}
