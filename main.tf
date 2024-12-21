provider "azurerm" {
  features {}
}

module "vm" {
  source              = "./modules/vm"
  vm_name             = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  vm_size             = var.vm_size
  admin_username      = var.admin_username
  admin_public_key    = var.admin_public_key
  subnet_id           = var.subnet_id
  tags                = var.tags
}

output "vm_public_ip" {
  value = module.vm.vm_public_ip
}
