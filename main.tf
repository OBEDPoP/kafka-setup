terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.67.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket         = "obedpop-terraform-state-bucket"
    key            = "kafka-banking/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# ---------------------- VPC & Networking ----------------------
resource "aws_vpc" "kafka_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.kafka_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "public2" {  # Added second subnet
  vpc_id                  = aws_vpc.kafka_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
}

resource "aws_security_group" "kafka_sg" {
  vpc_id = aws_vpc.kafka_vpc.id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------- IAM ROLES ----------------------

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "ec2_kafka_role"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_kafka_profile"
  role = aws_iam_role.ec2_role.name
}

# IAM Role for Kafka MSK
resource "aws_iam_role" "msk_role" {
  name = "KafkaMSKRole"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "kafka.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
}

# Kafka IAM Policy
resource "aws_iam_policy" "kafka_policy" {
  name        = "KafkaAccessPolicy"
  description = "Allows Kafka Producers/Consumers to connect via IAM authentication"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers",
          "kafka:DescribeConfiguration",
          "kafka:DescribeClusterOperation",
          "kafka:ListClusters",
          "kafka:ListScramSecrets"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData"
        ],
        "Resource": "*"
      }
    ]
  }
  EOF
}

# Attach Kafka Policy to EC2 Role
resource "aws_iam_role_policy_attachment" "ec2_kafka_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.kafka_policy.arn
}

# ---------------------- MSK KAFKA CLUSTER ----------------------
resource "aws_msk_cluster" "kafka" {
  cluster_name           = "banking-kafka-cluster"
  kafka_version          = "3.2.0"  
  number_of_broker_nodes = 2  

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.public1.id, aws_subnet.public2.id]  # Added second subnet
    security_groups = [aws_security_group.kafka_sg.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }
}

# ---------------------- RDS POSTGRES ----------------------
resource "aws_db_instance" "rds" {
  identifier           = "banking-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 5
  username           = "kafka_user"
  password           = "kafka_pass"
  publicly_accessible = true
  skip_final_snapshot = true
}

# ---------------------- EC2 INSTANCE ----------------------
resource "aws_instance" "ec2" {
  ami                    = "ami-02a53b0d62d37a757"
  instance_type          = "t3.nano"
  key_name               = "my-key-pair"
  vpc_security_group_ids = [aws_security_group.kafka_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker python3-pip git
              systemctl start docker
              systemctl enable docker
              pip3 install flask kafka-python psycopg2-binary psycopg2
              
              # Clone the repository and navigate to the banking folder
              git clone https://github.com/OBEDPoP/kafka-setup.git /home/ec2-user/banking
              cd /home/ec2-user/banking
              
              # Start AKHQ (Kafka UI)
              docker run -d -p 8080:8080 tchiotludo/akhq
              
              # Start Flask app
              python3 app.py &
              
              # Start Kafka consumer
              python3 consumer.py &
              EOF
}

# ---------------------- OUTPUTS ----------------------
output "kafka_bootstrap_servers" {
  value = aws_msk_cluster.kafka.bootstrap_brokers
}

output "ec2_public_ip" {
  value = aws_instance.ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.rds.endpoint
}
