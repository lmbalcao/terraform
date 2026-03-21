locals {
  policy_targets = {
    for name, target in var.targets : name => target
    if target.backup_policy != null && target.backup_policy != ""
  }
}
