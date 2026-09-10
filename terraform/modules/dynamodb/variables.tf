variable "table_name" {
  type    = string
  default = "SolidaryTechVolunteers"
}

variable "enable_point_in_time_recovery" {
  description = "PITR (restauração em qualquer segundo dos últimos 35 dias)."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
