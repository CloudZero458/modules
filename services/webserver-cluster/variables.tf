variable "cluster_name" {
  description = "The name to use for all the server resources"
  type = string
}

variable "db_remote_state_bucket" {
  description = "The name of the S3 bucket for the database's remote state"
  type = string
}

variable "db_remote_state_key" {
  description = "The path for the database's remote state file in the S3 bucket"
  type = string
}

variable "server_port" {
  description = "the port the server uses for http requests"
  type = number
  default = 8080
}

variable "instance_type" {
  description = "The type of EC2 instances to run"
  type = string
}

variable "min_size" {
  description = "The minimum number of EC2 instances in the ASG"
  type = number
}

variable "min_size" {
  description = "The maximum number of EC2 instances in the ASG"
  type = number
}

locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}
