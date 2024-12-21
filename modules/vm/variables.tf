variable "vm_name" {
  description = "sbuasa_VM"
  type        = string
}

variable "resource_group_name" {
  description = "de_p1_resource_group"
  type        = string
}

variable "location" {
  description = "Azure location"
  type        = string
  default     = "North Europe"
}

variable "vm_size" {
  description = "Size of the Virtual Machine"
  type        = string
  default     = "Standard_DS1_v2"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
}



variable "subnet_id" {
  description = "ID of the subnet to attach the VM's network interface"
  type        = string
}

variable "tags" {
  description = "Tags to assign to resources"
  type        = map(string)
  default     = {}
}
