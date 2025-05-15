terraform {
  backend "s3" {
    bucket         = "user-data-management-bucket"
    key            = "terraform"
    region         = "eu-north-1"
    encrypt        = true
  }
}