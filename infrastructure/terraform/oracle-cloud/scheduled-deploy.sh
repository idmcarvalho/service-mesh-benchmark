#!/bin/bash
# OCI Deployment - Scheduled Retry with Fault Domain Cycling
# Runs 999 attempts during 02:00-06:00 BRT, cycling through FDs

LOG_FILE="deploy-scheduled.log"
MAX_RETRIES=999
RETRY_INTERVAL=60
START_HOUR=2   # 02:00 BRT
END_HOUR=6     # 06:00 BRT

# Fault domains to cycle through (0=auto, 1, 2, 3)
FAULT_DOMAINS=(0 1 2 3)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

is_optimal_window() {
    local hour=$(date +%H)
    if [ $hour -ge $START_HOUR ] && [ $hour -lt $END_HOUR ]; then
        return 0
    fi
    return 1
}

wait_for_window() {
    if is_optimal_window; then
        return 0
    fi

    local current_hour=$(date +%H)
    local current_min=$(date +%M)

    if [ $current_hour -ge $END_HOUR ]; then
        local hours_to_wait=$((24 - current_hour + START_HOUR))
        local mins_to_wait=$((hours_to_wait * 60 - current_min))
    else
        local hours_to_wait=$((START_HOUR - current_hour))
        local mins_to_wait=$((hours_to_wait * 60 - current_min))
    fi

    log "Fora do horário ideal (02:00-06:00 BRT)"
    log "Horário atual: $(date '+%H:%M BRT')"
    log "Aguardando $mins_to_wait minutos até 02:00..."
    log "============================================"

    sleep ${mins_to_wait}m
}

try_deploy() {
    local fd=$1

    log "Tentando com fault_domain=$fd"

    OUTPUT=$(terraform apply -auto-approve -var="fault_domain=$fd" 2>&1)
    echo "$OUTPUT" >> $LOG_FILE

    if echo "$OUTPUT" | grep -qi "out of host capacity"; then
        return 1
    fi

    if echo "$OUTPUT" | grep -qi "error"; then
        return 1
    fi

    MASTER_IP=$(terraform output -raw master_public_ip 2>/dev/null)
    if [ -z "$MASTER_IP" ] || [ "$MASTER_IP" = "null" ]; then
        return 1
    fi

    return 0
}

# Main
cd "$(dirname "$0")"

log "============================================"
log "OCI Scheduled Deploy (02:00-06:00 BRT)"
log "Max tentativas: $MAX_RETRIES"
log "Intervalo: ${RETRY_INTERVAL}s"
log "Fault Domains: ${FAULT_DOMAINS[*]}"
log "Target: 1 Master + 2 Workers"
log "============================================"

attempt=0
while [ $attempt -lt $MAX_RETRIES ]; do
    wait_for_window

    if ! is_optimal_window; then
        log "Janela encerrada (06:00). Aguardando próxima..."
        continue
    fi

    # Cycle through fault domains
    fd_index=$((attempt % ${#FAULT_DOMAINS[@]}))
    current_fd=${FAULT_DOMAINS[$fd_index]}

    ((attempt++))
    log ""
    log "=== Tentativa $attempt/$MAX_RETRIES [FD=$current_fd] ==="

    if try_deploy $current_fd; then
        log ""
        log "========================================"
        log "SUCESSO! Deploy concluído!"
        log "Fault Domain: $current_fd"
        log "========================================"
        terraform output 2>&1 | tee -a $LOG_FILE

        MASTER_IP=$(terraform output -raw master_public_ip)
        log ""
        log "SSH: ssh -i ~/.ssh/oci_benchmark_key ubuntu@$MASTER_IP"
        exit 0
    fi

    log "Falhou [FD=$current_fd]. Próxima em ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

log "Limite de $MAX_RETRIES tentativas atingido."
exit 1
