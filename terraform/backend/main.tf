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
  description = "Type of project: 'backend'"
  default     = "backend"
}

variable "backend_api_url" {
  type        = string
  description = "Backend API URL for frontend to connect to (single backend scenario)"
  default     = ""
}

variable "runtime_stack" {
  type        = string
  description = "Runtime stack: dotnet, node, python, java"
  default     = "dotnet"
}

variable "tier" {
  type        = string
  description = "Deployment tier: free, standard, premium"
  default     = "free"
}

variable "frontend_allowed_origins" {
  type        = string
  description = "Comma-separated frontend origins allowed for backend CORS"
  default     = ""
}

variable "health_status" {
  type        = string
  description = "Operational health status returned by backend health endpoints"
  default     = "Healthy"
}

variable "service_name" {
  type        = string
  description = "Service name returned by backend health endpoints"
  default     = "calculator-api"
}

variable "service_environment" {
  type        = string
  description = "Environment name returned by backend health endpoints"
  default     = "prod"
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

  # Tier-based SKU
  sku_name  = var.tier == "premium" ? "S1" : var.tier == "standard" ? "B1" : "F1"
  always_on = var.tier != "free"
  frontend_origins = [
    for origin in split(",", var.frontend_allowed_origins) :
    trimspace(origin)
    if trimspace(origin) != ""
  ]

  # Runtime conditions
  is_dotnet  = var.runtime_stack == "dotnet"
  is_linux   = !local.is_dotnet

  # Backend flag
  is_backend = var.project_type == "backend"
}

# ============================================
# RESOURCE GROUP
# ============================================

resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg"
  location = var.location
}

# ============================================
# APP SERVICE PLAN (Dynamic OS: Windows for .NET, Linux for others)
# ============================================

resource "azurerm_service_plan" "main" {
  count               = local.is_backend ? 1 : 0
  name                = "${local.resource_prefix}-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = local.is_dotnet ? "Windows" : "Linux"
  sku_name            = local.sku_name

  depends_on = [azurerm_resource_group.main]
}

# ============================================
# WINDOWS WEB APP (.NET only)
# ============================================

resource "azurerm_windows_web_app" "main" {
  count               = local.is_backend && local.is_dotnet ? 1 : 0
  name                = "${local.resource_prefix}-webapp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main[0].id

  site_config {
    always_on = local.always_on
    application_stack {
      dotnet_version = "v8.0"
    }
    dynamic "cors" {
      for_each = length(local.frontend_origins) > 0 ? [1] : []
      content {
        allowed_origins     = local.frontend_origins
        support_credentials = false
      }
    }
  }

  app_settings = {
    "ASPNETCORE_ENVIRONMENT"       = "Production"
    "HEALTH_STATUS"                = var.health_status
    "HEALTH_SERVICE"               = var.service_name
    "HEALTH_ENVIRONMENT"           = var.service_environment
    "HEALTH_TIMESTAMP_UTC_MODE"    = "runtime"
    "HealthStatus__Status"         = var.health_status
    "HealthStatus__Service"        = var.service_name
    "HealthStatus__Environment"    = var.service_environment
    "HealthStatus__TimestampUtcMode" = "runtime"
    "ALLOWED_ORIGINS"              = var.frontend_allowed_origins
    "Cors__AllowedOrigins"         = var.frontend_allowed_origins
  }

  depends_on = [
    azurerm_resource_group.main,
    azurerm_service_plan.main
  ]
}

# ============================================
# LINUX WEB APP (Node.js, Python, Java)
# ============================================

resource "azurerm_linux_web_app" "main" {
  count               = local.is_backend && local.is_linux ? 1 : 0
  name                = "${local.resource_prefix}-webapp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main[0].id

  site_config {
    always_on = local.always_on
    application_stack {
      node_version   = var.runtime_stack == "node" ? "20-lts" : null
      python_version = var.runtime_stack == "python" ? "3.11" : null
      java_version   = var.runtime_stack == "java" ? "17" : null
      java_server         = var.runtime_stack == "java" ? "JAVA" : null
      java_server_version = var.runtime_stack == "java" ? "17" : null
    }
    dynamic "cors" {
      for_each = length(local.frontend_origins) > 0 ? [1] : []
      content {
        allowed_origins     = local.frontend_origins
        support_credentials = false
      }
    }
  }

  app_settings = {
    "WEBSITES_PORT"               = var.runtime_stack == "node" ? "3000" : var.runtime_stack == "python" ? "8000" : ""
    "HEALTH_STATUS"               = var.health_status
    "HEALTH_SERVICE"              = var.service_name
    "HEALTH_ENVIRONMENT"          = var.service_environment
    "HEALTH_TIMESTAMP_UTC_MODE"   = "runtime"
    "HealthStatus__Status"        = var.health_status
    "HealthStatus__Service"       = var.service_name
    "HealthStatus__Environment"   = var.service_environment
    "HealthStatus__TimestampUtcMode" = "runtime"
    "ALLOWED_ORIGINS"             = var.frontend_allowed_origins
    "Cors__AllowedOrigins"        = var.frontend_allowed_origins
  }

  depends_on = [
    azurerm_resource_group.main,
    azurerm_service_plan.main
  ]
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

output "runtime_stack" {
  value = var.runtime_stack
}

# Backend Web App outputs (works for both Windows and Linux)
output "webapp_name" {
  value = local.is_backend ? (
    local.is_dotnet
      ? (length(azurerm_windows_web_app.main) > 0 ? azurerm_windows_web_app.main[0].name : "")
      : (length(azurerm_linux_web_app.main) > 0 ? azurerm_linux_web_app.main[0].name : "")
  ) : ""
}

output "webapp_url" {
  value = local.is_backend ? (
    local.is_dotnet
      ? (length(azurerm_windows_web_app.main) > 0 ? "https://${azurerm_windows_web_app.main[0].default_hostname}" : "")
      : (length(azurerm_linux_web_app.main) > 0 ? "https://${azurerm_linux_web_app.main[0].default_hostname}" : "")
  ) : ""
}
