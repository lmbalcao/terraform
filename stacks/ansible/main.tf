locals {
  eligible_targets = {
    for name, target in var.targets : name => target
    if target.ansible_enabled
  }
}
