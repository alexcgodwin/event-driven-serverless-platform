$ErrorActionPreference = 'Stop'

Write-Host '== Event-Driven Serverless local validation =='
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
node --check src/handler.js

Write-Host 'Validation complete. No cloud resources were created.'
