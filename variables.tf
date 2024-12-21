variable "vm_name" {
  type        = string
  description = "The name of the virtual machine"
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "vm_size" {
  type        = string
  description = "The size of the virtual machine"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM"
}

variable "admin_public_key" {
  type        = string
  description = "SSH public key for authentication"
}

variable "subnet_id" {
  type        = string
  description = "The subnet ID for the VM's network interface"
}

variable "tags" {
  type        = map(string)
  description = "Tags for the VM resources"
  default     = {}
}
