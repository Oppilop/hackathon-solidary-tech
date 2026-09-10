variable "queue_name" {
  type    = string
  default = "solidary-donations"
}

variable "tags" {
  type    = map(string)
  default = {}
}
