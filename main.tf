# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.9.6"
  required_providers {
    # see https://github.com/hashicorp/terraform-provider-random
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    # see https://github.com/Tobotimus/terraform-provider-toml
    # see https://registry.terraform.io/providers/Tobotimus/toml
    toml = {
      source  = "Tobotimus/toml"
      version = "0.3.0"
    }
    # see https://github.com/terraform-providers/terraform-provider-azurerm
    # see https://registry.terraform.io/providers/hashicorp/azurerm
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# NB you can test the relative speed from you browser to a location using https://azurespeedtest.azurewebsites.net/
# get the available locations with: az account list-locations --output table
variable "location" {
  default = "France Central" # see https://azure.microsoft.com/en-us/global-infrastructure/france/
}

# NB this name must be unique within the Azure subscription.
#    all the other names must be unique within this resource group.
variable "resource_group_name" {
  default = "rgl-garm"
}

data "azurerm_client_config" "current" {
}

data "azurerm_subscription" "current" {
}

# NB this name must be unique within the given azure region/location.
#    it will be used as the container public FQDN as {dns_name_label}.{location}.azurecontainer.io.
# NB this FQDN length is limited to Let's Encrypt Certicate CN maximum length of 64 characters.
locals {
  # NB this results in a 32 character string. e.g. f64e997403f65d32aa7fb0a482c49e1b.
  dns_name_label = replace(uuidv5("url", "https://azurecontainer.io/${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}/garm"), "/\\-/", "")
}

output "ip_address" {
  value = azurerm_container_group.garm.ip_address
}

output "fqdn" {
  value = azurerm_container_group.garm.fqdn
}

output "url" {
  value = "https://${azurerm_container_group.garm.fqdn}"
}

# NB this generates a random number for the storage account.
# NB this must be at most 12 bytes.
resource "random_id" "garm_storage" {
  keepers = {
    resource_group = azurerm_resource_group.garm.name
  }
  byte_length = 12
}

resource "random_password" "garm_jwt_auth" {
  length = 64
}

resource "random_password" "garm_database_passphrase" {
  length = 32
}

resource "azurerm_resource_group" "garm" {
  name     = var.resource_group_name # NB this name must be unique within the Azure subscription.
  location = var.location
}

resource "azurerm_role_assignment" "garm" {
  scope                = data.azurerm_subscription.current.id
  principal_id         = azurerm_container_group.garm.identity[0].principal_id
  role_definition_name = "Contributor"
}

resource "azurerm_storage_account" "garm" {
  # NB this name must be globally unique as all the azure storage accounts share the same namespace.
  # NB this name must be at most 24 characters long.
  name                     = random_id.garm_storage.hex
  location                 = azurerm_resource_group.garm.location
  resource_group_name      = azurerm_resource_group.garm.name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "garm_caddy_data" {
  name                 = "garm-caddy-data"
  storage_account_name = azurerm_storage_account.garm.name
  quota                = 1
}

resource "azurerm_storage_share" "garm_garm_data" {
  name                 = "garm-garm-data"
  storage_account_name = azurerm_storage_account.garm.name
  quota                = 1
}

resource "azurerm_log_analytics_workspace" "garm" {
  name                = "garm"
  location            = azurerm_resource_group.garm.location
  resource_group_name = azurerm_resource_group.garm.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_group" "garm" {
  name                = "garm"
  location            = azurerm_resource_group.garm.location
  resource_group_name = azurerm_resource_group.garm.name
  ip_address_type     = "Public"
  dns_name_label      = local.dns_name_label
  os_type             = "Linux"

  identity {
    type = "SystemAssigned"
  }

  diagnostics {
    log_analytics {
      workspace_id  = azurerm_log_analytics_workspace.garm.workspace_id
      workspace_key = azurerm_log_analytics_workspace.garm.primary_shared_key
    }
  }

  container {
    name   = "caddy"
    image  = "caddy:2"
    cpu    = "0.5"
    memory = "0.2"

    volume {
      name       = "caddy-config"
      read_only  = true
      mount_path = "/etc/caddy"
      secret = {
        "Caddyfile" = base64encode(<<-EOF
          ${local.dns_name_label}.${replace(lower(azurerm_resource_group.garm.location), "/ /", "")}.azurecontainer.io {
            log
            reverse_proxy localhost:8080
          }
          EOF
        ),
      }
    }

    # see https://caddyserver.com/docs/conventions#data-directory
    # see https://github.com/caddyserver/caddy-docker
    volume {
      name                 = "caddy-data"
      mount_path           = "/data"
      share_name           = azurerm_storage_share.garm_caddy_data.name
      storage_account_name = azurerm_storage_account.garm.name
      storage_account_key  = azurerm_storage_account.garm.primary_access_key
    }

    ports {
      port     = 80
      protocol = "TCP"
    }

    ports {
      port     = 443
      protocol = "TCP"
    }
  }

  container {
    name   = "garm"
    image  = "ghcr.io/cloudbase/garm:v0.1.5"
    cpu    = "0.5"
    memory = "1.0"

    volume {
      name       = "garm-config"
      read_only  = true
      mount_path = "/etc/garm"
      secret = {
        # see https://github.com/cloudbase/garm/blob/v0.1.5/doc/config.md
        "config.toml" = base64encode(<<-EOF
          [default]
          enable_webhook_management = true

          [logging]
          enable_log_streamer = true
          log_format = "text"
          log_level = "info"
          log_source = false

          [metrics]
          enable = false
          disable_auth = false

          [jwt_auth]
          secret = ${provider::toml::encode(random_password.garm_jwt_auth.result)}
          time_to_live = "8760h"

          [apiserver]
          bind = "127.0.0.1"
          port = 8080
          use_tls = false

          [database]
          backend = "sqlite3"
          passphrase = ${provider::toml::encode(random_password.garm_database_passphrase.result)}

          [database.sqlite3]
          db_file = "/data/garm.db"

          [[provider]]
          provider_type = "external"
          name = "azure"
          description = "Azure"

          [provider.external]
          provider_executable = "/opt/garm/providers.d/garm-provider-azure"
          config_file = "/etc/garm/garm-provider-azure.toml"
          EOF
        ),
        # see https://github.com/cloudbase/garm-provider-azure
        "garm-provider-azure.toml" = base64encode(<<-EOF
          location = ${provider::toml::encode(var.location)}

          [credentials]
          subscription_id = ${provider::toml::encode(data.azurerm_client_config.current.subscription_id)}
          EOF
        ),
      }
    }

    # TODO this is a smb/cifs shared filesystem which sqlite3 might not like. maybe we should use mysql instead?
    volume {
      name                 = "garm-data"
      mount_path           = "/data"
      share_name           = azurerm_storage_share.garm_garm_data.name
      storage_account_name = azurerm_storage_account.garm.name
      storage_account_key  = azurerm_storage_account.garm.primary_access_key
    }

    # TODO drop this depending on the outcome of https://github.com/cloudbase/garm/discussions/290.
    volume {
      name       = "garm-certs"
      read_only  = true
      mount_path = "/etc/ssl/certs"
      secret = {
        "ca-certificates.crt" = base64encode(file("/etc/ssl/certs/ca-certificates.crt"))
      }
    }
  }
}
