//provider bloc AWS
provider "aws" {
  region = "us-east-1"
  shared_credentials_files =  ["~/.aws/credentials"]
}

//generate a tls_private_key to be attached to EC2 Instance. It will generate private and public key. Keys will be available in the terraform state file.
resource "tls_private_key" "mykey" {
 	 algorithm = "RSA"
}

//Create a resource AWS_key named web-key from the terraform state file I am taking the public key and send it to AWS
resource "aws_key_pair" "aws_key" {
  key_name   = "web-key"
  public_key = tls_private_key.mykey.public_key_openssh

// will write a local-exec provisioner which in the current directory will create a Pem file which is the private key file
provisioner "local-exec" {
  command = "echo '${tls_private_key.mykey.private_key_openssh}' > ./web-key.pem"
}

}
//Create a VPC
resource "aws_vpc" "sl-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
   	Name = "sl-vpc"
  }
}
//Create a subnet named subnet-1
  resource "aws_subnet" "subnet-1"{
  vpc_id = aws_vpc.sl-vpc.id
  cidr_block = "10.0.1.0/24"
  //Subnet will be created after the vpc
  depends_on = [aws_vpc.sl-vpc]
  map_public_ip_on_launch = true
    tags = {
     	Name = "sl-subnet"
  }

}
//Creation of route table 
resource "aws_route_table" "sl-route-table"{
  vpc_id = aws_vpc.sl-vpc.id
    tags = {
     	Name = "sl-route-table"
  }
}

//Creation of route table association with subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.sl-route-table.id
}

//Creation of Internet Gateway
  resource "aws_internet_gateway" "gw" {
   vpc_id = aws_vpc.sl-vpc.id
  //It will be created after the vpc
   depends_on = [aws_vpc.sl-vpc]
      tags = {
     	Name = "sl-gw"
  }
}

//Creation of route table association with subnet
resource "aws_route" "sl-route" {
  route_table_id = aws_route_table.sl-route-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

variable "sg_ports" {
  type = list(number)
  default = [8080,80,22,443]
}

resource "aws_security_group" "sl-sg" {
  name        = "sg_rule"
  vpc_id = aws_vpc.sl-vpc.id
  dynamic  "ingress" {
    for_each = var.sg_ports
    iterator = port
    content {
      from_port        = port.value
      to_port          = port.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  }
  egress {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "myec2" {
// this is the AMI we already created from EC2 worker node
  ami           = “ami-0bbdf4ec9c386d4d4”   
  instance_type = "t2.micro"
  key_name = "web-key"
  subnet_id = aws_subnet.subnet-1.id
  security_groups = [aws_security_group.sl-sg.id]
  tags = {
    	Name = "Project-instance"
   }
}

// Adding some wait time to fetch the EC2 public IP
resource "time_sleep" "wait" {
  // Sleep time will start after the creation of EC2
  depends_on = [aws_instance.myec2]
  create_duration = "30s"
}

//Copy the public IP of EC2 instance and put it in myinventory file
resource "null_resource" "addIP" {
  // Once the sleep time is completed we execute the local provisioner
  depends_on = [time_sleep.wait]

  // Put the EC2 public IP in myinventory file
  provisioner "local-exec" {
    command = "echo '${aws_instance.myec2.public_ip}' > ./myinventory"
  }
}

// Trigger execution of the playbook after copying the IP @ of EC2 in the inventory
resource "null_resource" "run_playbook" {
  depends_on = [null_resource.addIP]
  provisioner "local-exec" {
    command = "ansible-playbook -i ./myinventory playbook1.yml"
  }
}
