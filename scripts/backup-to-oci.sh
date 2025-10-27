#!/bin/bash
# Backup Service Mesh Benchmark data to OCI Object Storage
# This script should be run as a Kubernetes CronJob

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-benchmark-system}"
POSTGRES_POD="${POSTGRES_POD:-postgres-0}"
BACKUP_BUCKET="${BACKUP_BUCKET:-benchmark-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are available
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi

    if ! command -v oci &> /dev/null; then
        log_error "OCI CLI not found"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Check if PostgreSQL pod is ready
check_postgres() {
    log_info "Checking PostgreSQL pod status..."

    if ! kubectl get pod "$POSTGRES_POD" -n "$NAMESPACE" &> /dev/null; then
        log_error "PostgreSQL pod $POSTGRES_POD not found in namespace $NAMESPACE"
        exit 1
    fi

    POD_STATUS=$(kubectl get pod "$POSTGRES_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" != "Running" ]; then
        log_error "PostgreSQL pod is not running (status: $POD_STATUS)"
        exit 1
    fi

    log_info "PostgreSQL pod is healthy"
}

# Create database backup
backup_database() {
    local backup_file="backup-db-${TIMESTAMP}.sql.gz"

    log_info "Creating database backup..."

    # Create backup using pg_dump
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- \
        pg_dump -U benchmark service_mesh_benchmark | gzip > "/tmp/$backup_file"

    if [ ! -f "/tmp/$backup_file" ]; then
        log_error "Backup file was not created"
        exit 1
    fi

    local backup_size=$(du -h "/tmp/$backup_file" | cut -f1)
    log_info "Database backup created: $backup_file (Size: $backup_size)"

    echo "/tmp/$backup_file"
}

# Backup results directory
backup_results() {
    local results_backup="backup-results-${TIMESTAMP}.tar.gz"
    local results_dir="/app/benchmarks/results"

    log_info "Creating results directory backup..."

    # Check if there are any results to backup
    if ! kubectl exec -n "$NAMESPACE" deployment/benchmark-api -- \
        [ -d "$results_dir" ] && [ "$(ls -A $results_dir 2>/dev/null)" ]; then
        log_warn "No results directory found or directory is empty, skipping results backup"
        return 0
    fi

    # Create tar archive of results
    kubectl exec -n "$NAMESPACE" deployment/benchmark-api -- \
        tar czf "/tmp/$results_backup" -C /app/benchmarks results/

    # Copy from pod to local
    kubectl cp "$NAMESPACE/$(kubectl get pod -n "$NAMESPACE" -l app=benchmark-api -o jsonpath='{.items[0].metadata.name}'):/tmp/$results_backup" \
        "/tmp/$results_backup"

    if [ -f "/tmp/$results_backup" ]; then
        local backup_size=$(du -h "/tmp/$results_backup" | cut -f1)
        log_info "Results backup created: $results_backup (Size: $backup_size)"
        echo "/tmp/$results_backup"
    else
        log_warn "Results backup was not created"
        return 0
    fi
}

# Upload backup to OCI Object Storage
upload_to_oci() {
    local backup_file="$1"
    local filename=$(basename "$backup_file")

    log_info "Uploading $filename to OCI Object Storage..."

    # Check if bucket exists
    if ! oci os bucket get --bucket-name "$BACKUP_BUCKET" &> /dev/null; then
        log_warn "Bucket $BACKUP_BUCKET not found, creating..."
        oci os bucket create --name "$BACKUP_BUCKET" --compartment-id "$OCI_COMPARTMENT_ID"
    fi

    # Upload file
    if oci os object put \
        --bucket-name "$BACKUP_BUCKET" \
        --name "$filename" \
        --file "$backup_file" \
        --force; then
        log_info "Successfully uploaded $filename to OCI"
    else
        log_error "Failed to upload $filename to OCI"
        return 1
    fi

    # Verify upload
    if oci os object head --bucket-name "$BACKUP_BUCKET" --name "$filename" &> /dev/null; then
        log_info "Verified $filename exists in OCI"
    else
        log_error "Failed to verify $filename in OCI"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."

    local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)

    # List and delete old backups
    local deleted_count=0
    while IFS= read -r object; do
        local object_date=$(echo "$object" | grep -oP '\d{8}' | head -1)
        local object_date_formatted=$(date -d "${object_date:0:4}-${object_date:4:2}-${object_date:6:2}" +%Y-%m-%d)

        if [[ "$object_date_formatted" < "$cutoff_date" ]]; then
            log_info "Deleting old backup: $object"
            if oci os object delete --bucket-name "$BACKUP_BUCKET" --name "$object" --force; then
                ((deleted_count++))
            fi
        fi
    done < <(oci os object list --bucket-name "$BACKUP_BUCKET" --query 'data[].name' --raw-output | grep "^backup-")

    log_info "Deleted $deleted_count old backup(s)"
}

# Clean up local temporary files
cleanup_local() {
    log_info "Cleaning up local temporary files..."
    rm -f /tmp/backup-*.sql.gz /tmp/backup-*.tar.gz
}

# Send notification (optional, requires configuration)
send_notification() {
    local status="$1"
    local message="$2"

    # Example: Send to Slack, email, or monitoring system
    # Implement based on your notification requirements
    log_info "Notification: $status - $message"
}

# Main backup process
main() {
    log_info "=== Starting backup process ==="
    log_info "Timestamp: $TIMESTAMP"

    # Check prerequisites
    check_prerequisites

    # Check PostgreSQL
    check_postgres

    # Backup database
    local db_backup
    db_backup=$(backup_database)

    if [ -n "$db_backup" ] && [ -f "$db_backup" ]; then
        # Upload database backup
        if upload_to_oci "$db_backup"; then
            log_info "Database backup completed successfully"
        else
            log_error "Database backup upload failed"
            send_notification "FAILED" "Database backup upload failed"
            exit 1
        fi
    fi

    # Backup results directory
    local results_backup
    results_backup=$(backup_results)

    if [ -n "$results_backup" ] && [ -f "$results_backup" ]; then
        # Upload results backup
        if upload_to_oci "$results_backup"; then
            log_info "Results backup completed successfully"
        else
            log_warn "Results backup upload failed (non-critical)"
        fi
    fi

    # Clean up old backups
    cleanup_old_backups

    # Clean up local files
    cleanup_local

    log_info "=== Backup process completed successfully ==="
    send_notification "SUCCESS" "Backup completed at $TIMESTAMP"
}

# Run main function
main "$@"
