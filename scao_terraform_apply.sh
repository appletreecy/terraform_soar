#!/bin/bash

start_time=$(date +%s)

# Run Terraform
terraform apply -auto-approve

end_time=$(date +%s)
execution_time=$((end_time - start_time))
execution_time_mins = $((end_time - start_time)/60)

echo "Terraform script execution time: ${execution_time} seconds"
echo "Terraform script execution time: ${execution_time_mins} mins"
