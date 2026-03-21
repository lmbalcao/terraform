terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    openwrt = {
      source  = "joneshf/openwrt"
      version = "= 0.0.20"
    }
  }
}
