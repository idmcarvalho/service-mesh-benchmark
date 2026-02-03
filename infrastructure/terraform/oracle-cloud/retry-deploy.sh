#!/bin/bash
# Continuous retry script for OCI deployment
# Properly detects capacity errors and keeps retrying

LOG_FILE="deploy-retry.log"
MAX_RETRIES=500
RETRY_INTERVAL=60

echo "Starting continuous deployment retry at $(date)" | tee $LOG_FILE
echo "Will retry every ${RETRY_INTERVAL}s up to ${MAX_RETRIES} times" | tee -a $LOG_FILE
echo "Target: 1 Master (2 OCPUs, 12GB) + 2 Workers (1 OCPU, 6GB each)" | tee -a $LOG_FILE

for i in $(seq 1 $MAX_RETRIES); do
    echo "" | tee -a $LOG_FILE
    echo "=== Attempt $i at $(date) ===" | tee -a $LOG_FILE

    # Capture output
    OUTPUT=$(terraform apply -auto-approve 2>&1)
    EXIT_CODE=$?

    # Log the output
    echo "$OUTPUT" | tee -a $LOG_FILE

    # Check for capacity error
    if echo "$OUTPUT" | grep -qi "out of host capacity"; then
        echo "Capacity error detected. Waiting ${RETRY_INTERVAL}s..." | tee -a $LOG_FILE
        sleep $RETRY_INTERVAL
        continue
    fi

    # Check if terraform failed for other reasons
    if [ $EXIT_CODE -ne 0 ]; then
        echo "Terraform failed with exit code $EXIT_CODE. Waiting ${RETRY_INTERVAL}s..." | tee -a $LOG_FILE
        sleep $RETRY_INTERVAL
        continue
    fi

    # Terraform succeeded, but verify instances were created
    MASTER_IP=$(terraform output -raw master_public_ip 2>/dev/null)

    if [ -z "$MASTER_IP" ] || [ "$MASTER_IP" = "null" ]; then
        echo "Instances not created (master_ip is null). Waiting ${RETRY_INTERVAL}s..." | tee -a $LOG_FILE
        sleep $RETRY_INTERVAL
        continue
    fi

    # Success!
    echo "" | tee -a $LOG_FILE
    echo "========================================" | tee -a $LOG_FILE
    echo "SUCCESS! Deployment completed at $(date)" | tee -a $LOG_FILE
    echo "========================================" | tee -a $LOG_FILE
    terraform output 2>&1 | tee -a $LOG_FILE

    echo "" | tee -a $LOG_FILE
    echo "SSH to master: ssh -i ~/.ssh/oci_benchmark_key ubuntu@$MASTER_IP" | tee -a $LOG_FILE
    exit 0
done

echo "Max retries ($MAX_RETRIES) reached. Deployment failed." | tee -a $LOG_FILE
exit 1
