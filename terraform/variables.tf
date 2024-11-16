variable "pm_api_url" {
  description = "URL of Proxmox host"
  sensitive   = true
  type        = string
  default     = "https://1.1.1.1:8006/api2/json"
}
variable "pm_user" {
  description = "Proxmox user account"
  sensitive   = true
  type        = string
  default     = "proxmox"
}
variable "pm_password" {
  description = "Proxmox user account password"
  sensitive   = true
  type        = string
  default     = "proxmox"
}