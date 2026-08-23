terraform {
  # GitLab-managed state gives locking and versioning for free, and works the
  # same way under OpenTofu's "http" backend as it did under Terraform's.
  # Configure at init time:
  #   tofu init \
  #     -backend-config="address=${GL_API}/projects/${PROJ}/terraform/state/prod" \
  #     -backend-config="lock_address=.../prod/lock" \
  #     -backend-config="unlock_address=.../prod/lock" \
  #     -backend-config="username=gitlab-ci-token" \
  #     -backend-config="password=${CI_JOB_TOKEN}" \
  #     -backend-config="lock_method=POST" \
  #     -backend-config="unlock_method=DELETE" \
  #     -backend-config="retry_wait_min=5"
  backend "http" {}
}
