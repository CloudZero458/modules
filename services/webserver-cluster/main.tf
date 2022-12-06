

# resource type,resource name, attribute. The resource name is the reference name for terraform
resource "aws_launch_configuration" "example" {
  image_id = "ami-07b91c2d00416c402"
  # "ami-04b3f370082cbadb8"

  instance_type = var.instance_type


  security_groups = [aws_security_group.instance.id]

              # path.module enables the templatfile function to work with non-root modules
  user_data = templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.address
    db_port = data.terraform_remote_state.db.outputs.port
  })

  /*<<-EOF
    #!/bin/bash
    echo "Hello World" > index.html
    echo "${data.terraform_remote_state.db.outputs.address}" >> index.html
    echo "${data.terraform_remote_state.db.outputs.port}" >> index.html
    nohup busybox httpd -f -p ${var.server_port} &
    EOF*/

  # required when using a launch configuration with an autoscaling group
  lifecycle {
    create_before_destroy = true
  }
}


# provider resource type, name
data "aws_vpc" "default" {
  default = true # default vpc?
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id] # references the aws_vpc data source
  }
}

resource "aws_autoscaling_group" "example" {
  # .name refers to the name of the AWS resource, not the terraform reference name. The .name argument is used to auto-generate the name for the autoscaling resource.
  launch_configuration = aws_launch_configuration.example.name

  # references the "aws_subnets" data source and tells the asg where to launch resources
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]

  # uses the target group's health-checker (which is superior) vs the ec2 health-checker, which uses the aws hypervisor to check for health
  health_check_type = "ELB"

  min_size = var.min_size
  desired_capacity = 2
  max_size = var.max_size

  tag {
    key = "Name"
    value = "${var.webserver_cluster}-asg"
    propagate_at_launch = true # copies the tag to each ec2 instance at launch
  }

}

resource "aws_lb" "example" {
  name = "${var.webserver_cluster}-alb"
  load_balancer_type = "application"

  # references the "aws_subnets" data source and attaches the subnets to the load balancer.
  subnets = data.aws_subnets.default.ids

  # resource type, name, attribute. References the alb security group resource. the id is for the actual resource created in AWS.
  security_groups = [aws_security_group.alb.id]
}

# target group tells the load balancer where to send / redirect traffic to. This target group is assigned to the asg resource
resource "aws_lb_target_group" "asg" {
  name = "${var.webserver_cluster}-asg-target-group"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2

  }
}

# listens for requests sent to the load balancer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn # references aws_lb resource. arn is an name id
  port = local.http_port
  protocol = "HTTP"

  #returns a 404 error page or requests that don't match the listener rules
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# security group for load balancer
resource "aws_security_group" "alb" {
  name = "${var.webserver_cluster}-alb-sg"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port = local.http_port
  to_port= local.http_port
  protocol = local.tcp_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id
  from_port = local.any_port
  to_port = local.any_port
  protocol = local.any_protocol
  cidr_blocks = local.all_ips
}

# security group for ec2 instances
resource "aws_security_group" "instance" {
  name = "${var.webserver_cluster}-ec2-sg"
}

resource "aws_security_group_rule" "server_port" {
  type = "ingress"
  from_port = var.server_port
  to_port = var.server_port
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}



locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

# imports data about the mysql db
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "us-east-1"

  }
}
