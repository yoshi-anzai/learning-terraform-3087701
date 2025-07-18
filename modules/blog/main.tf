data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner] # Bitnami
}

data "aws_vpc" "default" {
  default = true
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]

  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name = "${var.environment.name}-blog"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}


module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.1"
  
  name = "${var.environment.name}-blog"
  min_size = var.asg_min_size
  max_size = var.asg_max_size

  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]
  
  image_id = data.aws_ami.app_ami.id
  instance_type = var.instance_type

  traffic_source_attachments = {
    blog_alb = {
      traffic_source_identifier = module.blog_alb.target_groups["blog_asg"].arn
      traffic_source_type       = "elbv2"
    }
  }
}

module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "${var.environment.name}-blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]
  enable_deletion_protection = false
  
  
  listeners = {
    http-forward = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "blog_asg"
      }
    }
  }

  target_groups = {
    blog_asg = {
      name_prefix      = "${var.environment.name}-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      create_attachment = false
    }
  }

  tags = {
    Environment = var.environment.name
  }
}