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

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.kafka_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.kafka_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
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

resource "aws_route_table_association" "public1_assoc" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public2_assoc" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public_rt.id
}

# ---------------------- Security Groups ----------------------
# Security Group for EC2
resource "aws_security_group" "kafka_sg" {
  vpc_id = aws_vpc.kafka_vpc.id

  ingress {
    from_port   = 9094
    to_port     = 9094
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

  ingress {
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
}

# Security Group for MSK
resource "aws_security_group" "msk_sg" {
  vpc_id = aws_vpc.kafka_vpc.id

  # Allow inbound traffic on Kafka port (9094) from EC2 security group
  ingress {
    from_port        = 9094
    to_port          = 9094
    protocol         = "tcp"
    security_groups  = [aws_security_group.kafka_sg.id]  # Allows EC2 to connect to MSK brokers
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allows outbound traffic to anywhere
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
    security_groups = [aws_security_group.msk_sg.id]  # Apply MSK security group here
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
  key_name               = "docker"
  subnet_id              = aws_subnet.public1.id
  vpc_security_group_ids = [aws_security_group.kafka_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
#!/bin/bash

# Set Kafka broker environment variable and DB host (use actual values or variables)
export KAFKA_BROKER="b-2.bankingkafkacluster.ijsx2p.c18.kafka.us-east-1.amazonaws.com:9094,b-1.bankingkafkacluster.ijsx2p.c18.kafka.us-east-1.amazonaws.com:9094"
export DB_HOST="banking-db.cr4gwkce03c9.us-east-1.rds.amazonaws.com:5432"

# Install dependencies
sudo yum update -y
sudo yum install -y python3 python3-pip git
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
pip3 install flask kafka-python

# Clone the Flask app repository
git clone https://github.com/OBEDPoP/kafka-setup.git ./kafka
cd ./kafka/banking

# Install screen if not installed
sudo yum install -y screen

# Start a new screen session for Flask app and run it in the background
screen -dmS flask-app bash -c "python3 app.py"

# Pull AKHQ (Kafka UI) Docker image
sudo docker pull tchiotludo/akhq

# MSK Bootstrap Servers (ensure this is a single line)
MSK_BOOTSTRAP_SERVER="b-2.bankingkafkacluster.ijsx2p.c18.kafka.us-east-1.amazonaws.com:9094,b-1.bankingkafkacluster.ijsx2p.c18.kafka.us-east-1.amazonaws.com:9094"

# Run AKHQ (Kafka UI) in detached mode
sudo docker run -d -p 8080:8080 \
  -e AKHQ_CONFIGURATION='
  akhq:
    connections:
      kafka-cluster:
        properties:
          bootstrap.servers: "'$MSK_BOOTSTRAP_SERVER'"
  ' tchiotludo/akhq

# Start Kafka consumer (in detached mode)
nohup python3 consumer.py &

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
