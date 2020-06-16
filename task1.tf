provider "aws" {
  region     = "ap-south-1"
  profile    = "terra_use"
}

resource "aws_key_pair" "deployer" {
  key_name   = "terra-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41"
}
resource "aws_security_group" "allow_ssh_http" {
  depends_on = [
    aws_key_pair.deployer,
  ]


  name        = "allow_ssh_http"
  description = "Allow http inbound traffic"
  vpc_id      = "vpc-aef7eac6"

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task1_allow_http_ssh"
  }
}


resource "aws_ebs_volume" "ebs_vol_create" {
  depends_on = [
    aws_security_group.allow_ssh_http,
  ]
  availability_zone = "ap-south-1a"
  size              = 1
  
  tags = {
    Name = "task1_ebs"
  }
}


resource "aws_instance" "inst" {
  depends_on = [
    aws_ebs_volume.ebs_vol_create,
  ]
  ami           = "ami-08bb0b6e2094ed09d"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "terra-key"
  security_groups = ["allow_ssh_http"]
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/red_key.pem")
    host     = aws_instance.inst.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install git -y",
      "sudo systemctl start httpd",
    ]
  }
  tags = {
    Name = "task1_os"
  }
}
resource "aws_volume_attachment" "ebs_att" {
  depends_on = [
    aws_ebs_volume.ebs_vol_create,aws_instance.inst,
  ]
  device_name = "/dev/sdf"
  volume_id   = "${aws_ebs_volume.ebs_vol_create.id}"
  instance_id = "${aws_instance.inst.id}"
  force_detach = true
}

resource "null_resource" "public_ip" {
     depends_on = [
    aws_instance.inst,
  ]
	provisioner "local-exec" {
		command = "echo ${aws_instance.inst.public_ip} > publicip.txt"
	}
}

resource "null_resource" "ebs_mount"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/red_key.pem")
    host     = aws_instance.inst.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdf",
      "sudo mount  /dev/xvdf  /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Gaurav-Khore/terra_task1.git /var/www/html/"
    ]
  }
}


resource "aws_s3_bucket" "terra_bucket" {
  depends_on = [
    aws_instance.inst,
  ]
  bucket = "terrabucg"
  acl = "public-read"

  tags = {
    Name        = "terrabucg"
    Environment = "Dev"
  }
}
resource "null_resource" "git_base"  {

  depends_on = [
    aws_s3_bucket.terra_bucket,
  ]
   provisioner "local-exec" {
    working_dir="C:/Users/HP/Desktop/terra_ws/"
    command ="mkdir git_terra"
  }
  provisioner "local-exec" {
    working_dir="C:/Users/HP/Desktop/terra_ws/git_terra"
    command ="git clone https://github.com/Gaurav-Khore/terra_task1.git  C:/Users/HP/Desktop/terra_ws/git_terra"
  }
   
}



resource "aws_s3_bucket_object" "s3_upload" {
  depends_on = [
    null_resource.git_base,
  ]
  for_each = fileset("C:/Users/HP/Desktop/terra_ws/git_terra/", "*.png")

  bucket = "terrabucg"
  key    = each.value
  source = "C:/Users/HP/Desktop/terra_ws/git_terra/${each.value}"
  etag   = filemd5("C:/Users/HP/Desktop/terra_ws/git_terra/${each.value}")
  acl = "public-read"

}


locals {
  s3_origin_id = "s3-${aws_s3_bucket.terra_bucket.id}"
}

resource "aws_cloudfront_distribution" "s3_cloud" {
  depends_on = [
    aws_s3_bucket_object.s3_upload,
  ]
  origin {
    domain_name = "${aws_s3_bucket.terra_bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Terraform connecting s3 to the cloudfront"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "null_resource" "updating_code"  {

  depends_on = [
    aws_cloudfront_distribution.s3_cloud,
  ]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/red_key.pem")
    host = aws_instance.inst.public_ip
	}
  for_each = fileset("C:/Users/HP/Desktop/terra_ws/git_terra/", "*.png")
  provisioner "remote-exec" {
    inline = [
	"sudo su << EOF",
	"echo \"<p>Image access using cloud front url</p>\" >> /var/www/html/terra_page.html",
	"echo \"<img src='http://${aws_cloudfront_distribution.s3_cloud.domain_name}/${each.value}' width='500' height='333'>\" >> /var/www/html/terra_page.html",
        "EOF"
			]
	}
	 provisioner "local-exec" {
		command = "start chrome  ${aws_instance.inst.public_ip}/terra_page.html"
	}

}