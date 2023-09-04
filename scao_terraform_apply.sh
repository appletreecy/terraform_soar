#!/bin/bash

start_time=$(date +%s)

# Run Terraform
terraform apply -auto-approve

end_time=$(date +%s)
execution_time=$((end_time - start_time))

echo "Terraform script execution time: ${execution_time} seconds"
