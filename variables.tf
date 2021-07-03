variable "aws_region" {
  type = string
  default = "us-east-2"
}

variable "access_key" {
  type        = string
  default     = ""
}

variable "secret_key" {
  type        = string
  default     = ""
}

variable "vpc_cidr_block" {
  type        = string
  default     = "192.168.0.0/16"
}

variable "public_subnet_cidr_block" {
  type        = string
  default     = "192.168.10.0/24"
}

variable "private_subnet_cidr_block" {
  type        = string
  default     = "192.168.20.0/24"
}

variable "cloudmapper_access_key" {
  type        = string
  default     = ""
}

variable "cloudmapper_secret_key" {
  type        = string
  default     = ""
}

variable "aws_account_name" {
  type        = string
  default     = ""
}

variable "aws_account_id" {
  type        = string
  default     = ""
}

variable "public_key_name" {
  type        = string
  default     = "ssh_public_key"
}

variable "private_key_name" {
  type        = string
  default     = "ssh_private_key"
}

variable "key_path" {
  type        = string
  default     = "/var/lib/jenkins/.ssh/"
}
