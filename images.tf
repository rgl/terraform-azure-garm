locals {
  # images to copy into the azure container registry.
  source_images = {
    # see https://hub.docker.com/_/caddy
    caddy = {
      name = "docker.io/library/caddy"
      # renovate: datasource=docker depName=library/caddy
      tag = "2.10.0"
    }
    # see https://github.com/cloudbase/garm/pkgs/container/garm
    garm = {
      name = "ghcr.io/cloudbase/garm"
      # renovate: datasource=docker depName=cloudbase/garm registryUrl=https://ghcr.io
      tag = "v0.1.6"
    }
  }
  images = {
    for key, value in local.source_images : key => "${azurerm_container_registry.garm.login_server}/${key}:${value.tag}"
  }
}

# see https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry
# NB this name must be unique within azure.
#    it will be used as the registry public FQDN as {name}.azurecr.io.
# NB garmcr123.azurecr.io
resource "azurerm_container_registry" "garm" {
  resource_group_name = azurerm_resource_group.garm.name
  location            = azurerm_resource_group.garm.location
  name                = "garm${local.dns_name_label}"
  sku                 = "Basic"
  admin_enabled       = true
}

# see https://developer.hashicorp.com/terraform/language/resources/terraform-data
resource "terraform_data" "acr_image" {
  for_each = local.source_images

  triggers_replace = {
    source_image    = "${each.value.name}:${each.value.tag}"
    target_image    = local.images[each.key]
    target_location = azurerm_container_registry.garm.location
  }

  provisioner "local-exec" {
    when = create
    environment = {
      ACR_IMAGE_COMMAND         = "copy"
      ACR_IMAGE_SOURCE_IMAGE    = "${each.value.name}:${each.value.tag}"
      ACR_IMAGE_TARGET_IMAGE    = local.images[each.key]
      ACR_IMAGE_TARGET_LOCATION = azurerm_container_registry.garm.location
    }
    interpreter = ["bash"]
    command     = "${path.module}/acr-image.sh"
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      ACR_IMAGE_COMMAND         = "delete"
      ACR_IMAGE_SOURCE_IMAGE    = self.triggers_replace.source_image
      ACR_IMAGE_TARGET_IMAGE    = self.triggers_replace.target_image
      ACR_IMAGE_TARGET_LOCATION = self.triggers_replace.target_location
    }
    interpreter = ["bash"]
    command     = "${path.module}/acr-image.sh"
  }
}
