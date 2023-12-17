variable "public_subnets_cidr" {
  default = [
    "10.0.2.0/26",
    "10.0.3.0/26"
  ]
}

variable "private_subnets_cidr" {
  default = [
    "10.0.0.0/26",
    "10.0.1.0/26"
  ]
}

variable "environment" {
  default = "OneCampus"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "region" {
  description = "eu-west-3"
}

variable "availability_zones" {
  default = [
    "eu-west-3a",
    "eu-west-3c"
  ]
}