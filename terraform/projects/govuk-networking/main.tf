# == Manifest: projects::govuk-networking
#
# This module govuks the creation of full network stacks.
#
# === Variables:
#
# aws_region
# remote_state_govuk_vpc_key
# remote_state_govuk_vpc_bucket
# stackname
# public_subnet_cidrs
# public_subnet_availability_zones
# public_subnet_nat_gateway_enable
# private_subnet_cidrs
# private_subnet_availability_zones
# private_subnet_nat_gateway_association
# private_subnet_elasticache_cidrs
# private_subnet_elasticache_availability_zones
#
# === Outputs:
#
# public_subnet_ids
# public_subnet_names_ids_map
# private_subnet_ids
# private_subnet_names_ids_map
# private_subnet_names_route_tables_map
# private_subnet_elasticache_ids
# private_subnet_elasticache_names_ids_map
# private_subnet_elasticache_names_route_tables_map
#

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "remote_state_govuk_vpc_key" {
  type        = "string"
  description = "VPC TF remote state key"
}

variable "remote_state_govuk_vpc_bucket" {
  type        = "string"
  description = "VPC TF remote state bucket"
}

variable "stackname" {
  type        = "string"
  description = "Stackname"
}

variable "public_subnet_cidrs" {
  type        = "map"
  description = "Map containing public subnet names and CIDR associated"
}

variable "public_subnet_availability_zones" {
  type        = "map"
  description = "Map containing public subnet names and availability zones associated"
}

variable "public_subnet_nat_gateway_enable" {
  type        = "list"
  description = "List of public subnet names where we want to create a NAT Gateway"
}

variable "private_subnet_cidrs" {
  type        = "map"
  description = "Map containing private subnet names and CIDR associated"
}

variable "private_subnet_availability_zones" {
  type        = "map"
  description = "Map containing private subnet names and availability zones associated"
}

variable "private_subnet_nat_gateway_association" {
  type        = "map"
  description = "Map of private subnet names and public subnet used to route external traffic (the public subnet must be listed in public_subnet_nat_gateway_enable to ensure it has a NAT gateway attached)"
}

variable "private_subnet_elasticache_cidrs" {
  type        = "map"
  description = "Map containing private elasticache subnet names and CIDR associated"
}

variable "private_subnet_elasticache_availability_zones" {
  type        = "map"
  description = "Map containing private elasticache subnet names and availability zones associated"
}

# Resources
# --------------------------------------------------------------
terraform {
  backend          "s3"             {}
  required_version = "= 0.9.10"
}

provider "aws" {
  region = "${var.aws_region}"
}

data "terraform_remote_state" "govuk_vpc" {
  backend = "s3"

  config {
    bucket = "${var.remote_state_govuk_vpc_bucket}"
    key    = "${var.remote_state_govuk_vpc_key}"
    region = "eu-west-1"
  }
}

module "govuk_public_subnet" {
  source                    = "../../modules/aws/network/public_subnet"
  vpc_id                    = "${data.terraform_remote_state.govuk_vpc.vpc_id}"
  default_tags              = "${map("Project", var.stackname)}"
  route_table_public_id     = "${data.terraform_remote_state.govuk_vpc.route_table_public_id}"
  subnet_cidrs              = "${var.public_subnet_cidrs}"
  subnet_availability_zones = "${var.public_subnet_availability_zones}"
}

module "govuk_nat" {
  source            = "../../modules/aws/network/nat"
  subnet_ids        = "${matchkeys(values(module.govuk_public_subnet.subnet_names_ids_map), keys(module.govuk_public_subnet.subnet_names_ids_map), var.public_subnet_nat_gateway_enable)}"
  subnet_ids_length = "${length(var.public_subnet_nat_gateway_enable)}"
}

# Intermediate variables in Terraform are not supported.
# There are a few workarounds to get around this limitation,
# https://github.com/hashicorp/terraform/issues/4084
# The template_file resources allow us to use a private_subnet_nat_gateway_association
# variable to select which NAT gateway, if any, each private
# subnet must use to route public traffic.
data "template_file" "nat_gateway_association_subnet_id" {
  count    = "${length(keys(var.private_subnet_nat_gateway_association))}"
  template = "$${subnet_id}"

  vars {
    subnet_id = "${lookup(module.govuk_public_subnet.subnet_names_ids_map, element(values(var.private_subnet_nat_gateway_association), count.index))}"
  }
}

data "template_file" "nat_gateway_association_nat_id" {
  count      = "${length(keys(var.private_subnet_nat_gateway_association))}"
  template   = "$${nat_gateway_id}"
  depends_on = ["data.template_file.nat_gateway_association_subnet_id"]

  vars {
    nat_gateway_id = "${lookup(module.govuk_nat.nat_gateway_subnets_ids_map, element(data.template_file.nat_gateway_association_subnet_id.*.rendered, count.index))}"
  }
}

module "govuk_private_subnet" {
  source                     = "../../modules/aws/network/private_subnet"
  vpc_id                     = "${data.terraform_remote_state.govuk_vpc.vpc_id}"
  default_tags               = "${map("Project", var.stackname)}"
  subnet_cidrs               = "${var.private_subnet_cidrs}"
  subnet_availability_zones  = "${var.private_subnet_availability_zones}"
  subnet_nat_gateways        = "${zipmap(keys(var.private_subnet_nat_gateway_association), data.template_file.nat_gateway_association_nat_id.*.rendered)}"
  subnet_nat_gateways_length = "${length(keys(var.private_subnet_nat_gateway_association))}"
}

module "govuk_private_subnet_elasticache" {
  source                     = "../../modules/aws/network/private_subnet"
  vpc_id                     = "${data.terraform_remote_state.govuk_vpc.vpc_id}"
  default_tags               = "${map("Project", var.stackname, "aws_migration", "elasticache")}"
  subnet_cidrs               = "${var.private_subnet_elasticache_cidrs}"
  subnet_availability_zones  = "${var.private_subnet_elasticache_availability_zones}"
  subnet_nat_gateways_length = "0"
}

# Outputs
# --------------------------------------------------------------
output "vpc_id" {
  value       = "${data.terraform_remote_state.govuk_vpc.vpc_id}"
  description = "VPC ID where the stack resources are created"
}

output "public_subnet_ids" {
  value       = "${module.govuk_public_subnet.subnet_ids}"
  description = "List of public subnet IDs"
}

output "public_subnet_names_ids_map" {
  value       = "${module.govuk_public_subnet.subnet_names_ids_map}"
  description = "Map containing the pair name-id for each public subnet created"
}

output "public_subnet_names_azs_map" {
  value = "${var.public_subnet_availability_zones}"
}

output "private_subnet_ids" {
  value       = "${module.govuk_private_subnet.subnet_ids}"
  description = "List of private subnet IDs"
}

output "private_subnet_names_ids_map" {
  value       = "${module.govuk_private_subnet.subnet_names_ids_map}"
  description = "Map containing the pair name-id for each private subnet created"
}

output "private_subnet_names_azs_map" {
  value = "${var.private_subnet_availability_zones}"
}

output "private_subnet_names_route_tables_map" {
  value       = "${module.govuk_private_subnet.subnet_names_route_tables_map}"
  description = "Map containing the name of each private subnet and route_table ID associated"
}

output "private_subnet_elasticache_ids" {
  value       = "${module.govuk_private_subnet_elasticache.subnet_ids}"
  description = "List of private subnet IDs"
}

output "private_subnet_elasticache_names_ids_map" {
  value       = "${module.govuk_private_subnet_elasticache.subnet_names_ids_map}"
  description = "Map containing the pair name-id for each private subnet created"
}

output "private_subnet_elasticache_names_azs_map" {
  value = "${var.private_subnet_elasticache_availability_zones}"
}

output "private_subnet_elasticache_names_route_tables_map" {
  value       = "${module.govuk_private_subnet_elasticache.subnet_names_route_tables_map}"
  description = "Map containing the name of each private subnet and route_table ID associated"
}
