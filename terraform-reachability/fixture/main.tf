# Fixture: 3-service stack used to exercise the Alloy reachability
# probe. Not meant to actually `terraform apply` — the SG IDs
# would need real VPC references etc. The purpose is to show what
# the source domain looks like before the .als translation.
#
# Architecture:
#   Frontend  ──HTTP──>  API  ──TCP─5432──>  Database
#
# Each tier lives in its own security group. The intended
# invariant is "frontend can never directly hit the database."

resource "aws_security_group" "frontend" {
  name = "sg-frontend"
  # egress: open (default)
}

resource "aws_security_group" "api" {
  name = "sg-api"
}

resource "aws_security_group" "db" {
  name = "sg-db"
}

# API accepts HTTP from the Frontend tier only.
resource "aws_security_group_rule" "api_from_frontend" {
  type                     = "ingress"
  security_group_id        = aws_security_group.api.id
  source_security_group_id = aws_security_group.frontend.id
  protocol                 = "tcp"
  from_port                = 8080
  to_port                  = 8080
}

# DB accepts Postgres from the API tier only.
resource "aws_security_group_rule" "db_from_api" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.api.id
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
}

# NOTE: NO rule allowing the frontend SG to reach the db SG
# directly. The Alloy probe verifies this absence holds and
# (separately) flags that the indirect path via api exists.
