terraform {
  required_providers {
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "2.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "5.16.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  domains = toset(["pluto-usda-actl-ledger-ossd","pluto-fmcsa-actual-lgr-ossd","pluto-dot-actual-ledger-ossd", "pluto-hhs-actual-ledger-ossd", "pluto-cdc-actual-ledger-ossd", "pluto-cms-actual-ledger-ossd", "pluto-dol-actual-ledger-ossd", "pluto-hud-actual-ledger-ossd", "pluto-cfda-code-ossd", "pluto-fra-actual-ledger-ossd"])
}

data "aws_caller_identity" "current" {
}

resource "local_file" "domain_configs" {
  for_each = local.domains
  content  = <<EOT

data "aws_opensearch_domain" "${each.value}" {
  domain_name = "${each.value}"
}

output "endpoint_${each.value}"{
  value = join("", ["https://",data.aws_opensearch_domain.${each.value}.endpoint])
} 

provider "opensearch" {
  alias          = "${each.value}"
  url            = join("", ["https://",data.aws_opensearch_domain.${each.value}.endpoint])
  aws_access_key = join(",", data.aws_iam_access_keys.opensearch.access_keys[*].access_key_id)
  aws_secret_key = data.aws_secretsmanager_secret_version.opensearch.secret_string
}

module "${each.value}" {
  source = "./modules/domain_config"
  providers = {
    opensearch = opensearch.${each.value}
  }
  domain_config = {
    aws_account = "${data.aws_caller_identity.current.account_id}"
    environment = "${var.environment}"
  }
}
EOT
  filename = "./${var.environment}/${each.value}.tf"
}

resource "local_file" "provider_config" {
  content  = <<EOT
terraform {
  required_providers {
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "2.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

EOT
  filename = "./${var.environment}/provider.tf"
}

resource "local_file" "modules_config" {
  content  = <<EOT
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "2.0.0"
    }
  }
}

resource "opensearch_role" "this" {
  role_name           = "admin"
  cluster_permissions = ["*"]

  index_permissions {
    index_patterns  = ["*"]
    allowed_actions = ["*"]
  }
}

variable "domain_config" {
  type = object({
    environment = optional(string, "")
    aws_account = optional(string, "")
  })
}

resource "opensearch_roles_mapping" "this" {
  role_name = "admin"
  backend_roles = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.environment}-opensearch-master",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.environment}-ha-opensearch-ecs-task-execution-role"
  ]
  depends_on = [opensearch_role.this]
}
EOT
  filename = "./${var.environment}/modules/domain_config/main.tf"
}

resource "local_file" "data_configs" {
  content  = <<EOT
data "aws_secretsmanager_secret_version" "opensearch" {
  secret_id = join(",", data.aws_secretsmanager_secrets.opensearch.names) //Making into single string value. 
}

data "aws_iam_users" "opensearch" {
  name_regex = "${var.environment}-opensearch-master.*"
}

data "aws_iam_access_keys" "opensearch" {
  user = join(",", data.aws_iam_users.opensearch.names)
}

data "aws_secretsmanager_secrets" "opensearch" {
  filter {
    name   = "name"
    values = ["${var.environment}-opensearch-master-tf"] //Should only return a single value. 
  }
}
EOT
  filename = "./${var.environment}/data.tf"
}

variable "environment" {
}