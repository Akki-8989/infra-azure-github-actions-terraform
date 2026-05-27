terraform {
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.116.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ============================================
# VARIABLES
# ============================================

variable "app_name" {
  type        = string
  description = "Application name (used for resource naming)"
}

variable "location" {
  type    = string
  default = "Central India"
}

variable "project_type" {
  type        = string
  description = "Type of project: 'frontend'"
  default     = "frontend"
}

variable "backend_api_url" {
  type        = string
  description = "Backend API URL for frontend to connect to (single backend scenario)"
  default     = ""
}

variable "tier" {
  type        = string
  description = "Deployment tier: free, standard, premium"
  default     = "free"
}

# ============================================
# LOCALS
# ============================================

locals {
  resource_prefix = replace(
    replace(lower(var.app_name), "_", "-"),
    ".",
    "-"
  )
  is_frontend = var.project_type == "frontend"

  # Tier-based SKU
  static_sku_tier = var.tier == "free" ? "Free" : "Standard"
  static_sku_size = var.tier == "free" ? "Free" : "Standard"
}

# ============================================
# RESOURCE GROUP
# ============================================

resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg"
  location = var.location
}

# ============================================
# FRONTEND RESOURCES (Static Web App)
# ============================================

resource "azurerm_static_web_app" "main" {
  count               = local.is_frontend ? 1 : 0
  name                = "${local.resource_prefix}-static"
  resource_group_name = azurerm_resource_group.main.name
  location            = "eastasia"
  sku_tier            = local.static_sku_tier
  sku_size            = local.static_sku_size

  depends_on = [azurerm_resource_group.main]
}

# ============================================
# OUTPUTS
# ============================================

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "project_type" {
  value = var.project_type
}

# Frontend outputs
output "static_webapp_name" {
  value = local.is_frontend ? azurerm_static_web_app.main[0].name : ""
}

output "static_webapp_url" {
  value = local.is_frontend ? "https://${azurerm_static_web_app.main[0].default_host_name}" : ""
}

output "static_webapp_api_key" {
  value     = local.is_frontend ? azurerm_static_web_app.main[0].api_key : ""
  sensitive = true
}
