#!/bin/bash

#==============================================================================
#TITLE:            Telegram-PostgreSQL-Backup.sh
#DESCRIPTION:      Script for automating the daily PostgreSQL backups to Telegram
#AUTHOR:           NimaH79 (adapted for PostgreSQL)
#USAGE:            ./Telegram-PostgreSQL-Backup.sh
#CRON:
  # example cron for daily PostgreSQL backup @ 00:00
  # min hr mday month wday command
  # 0   0  *    *     *    /path/to/Telegram-PostgreSQL-Backup.sh

#RESTORE FROM BACKUP
  #$ gunzip < [backupfile.sql.gz] | psql -U [uname] -d [dbname]
#==============================================================================

# ========================================
# CONFIGURATION VARIABLES
# ========================================

# Telegram Configuration
BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"

# PostgreSQL Configuration
DB_CONTAINER="postgres"                    # Docker container name or service name
DB_USER="postgres"                         # PostgreSQL username
DB_NAME="postgres"                         # Database name to backup
DB_HOST="localhost"                        # PostgreSQL host (if not using Docker)
DB_PORT="5432"                             # PostgreSQL port

# Backup Configuration
BACKUP_DIR="./backups"                     # Directory to store backups
BACKUP_PREFIX="postgres_backup"            # Prefix for backup files
KEEP_LOCAL_COPIES=true                     # Keep local backup files (true/false)
TELEGRAM_MAX_SIZE=50                       # Max file size in MB for Telegram

# Docker Configuration
USE_DOCKER=true                            # Use docker compose (true/false)
DOCKER_COMPOSE_FILE="docker-compose.yml"   # Docker compose file
DOCKER_SERVICE="postgres"                  # Docker service name

# Split Configuration
CHUNK_SIZE_MB=48                           # Size of each chunk in MB
MAX_RETRIES=3                              # Number of retry attempts for sending

# ========================================
# SCRIPT STARTS HERE
# ========================================

date
set -e

# Validate configuration
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "ERROR: BOT_TOKEN and CHAT_ID must be configured"
    exit 1
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Generate backup filename
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_$(date +%F_%H-%M-%S).sql.gz"

echo "=========================================="
echo "Starting PostgreSQL backup process"
echo "=========================================="
echo "Database: ${DB_NAME}"
echo "Container: ${DB_CONTAINER}"
echo "Backup directory: ${BACKUP_DIR}"
echo "Backup file: ${BACKUP_FILE}"
echo ""

# ========================================
# FUNCTIONS
# ========================================

# Telegram functions
telegram_send_message() {
    local chat_id="$1"
    local text="$2"
    local bot_token="$3"
    
    echo "  → Sending Telegram message..."
    curl -s -F chat_id="${chat_id}" -F text="${text}" "https://api.telegram.org/bot${bot_token}/sendMessage" &> /dev/null
    echo "  ✓ Message sent"
}

telegram_send_document() {
    local chat_id="$1"
    local file_path="$2"
    local caption="$3"
    local bot_token="$4"
    
    echo "  → Sending file to Telegram: $(basename "${file_path}")"
    curl -s -F chat_id="${chat_id}" -F document=@"${file_path}" -F caption="${caption}" "https://api.telegram.org/bot${bot_token}/sendDocument" &> /dev/null
    echo "  ✓ File sent successfully"
}

# Database dump function
create_database_dump() {
    echo "[1/5] Creating database dump..."
    
    local dump_command=""
    
    if [ "${USE_DOCKER}" = true ]; then
        # Docker version
        if [ -f "${DOCKER_COMPOSE_FILE}" ]; then
            dump_command="docker compose -f ${DOCKER_COMPOSE_FILE} exec -T ${DB_CONTAINER} pg_dump -U ${DB_USER} -d ${DB_NAME}"
        else
            dump_command="docker exec -T ${DB_CONTAINER} pg_dump -U ${DB_USER} -d ${DB_NAME}"
        fi
    else
        # Direct PostgreSQL connection
        if [ -n "$DB_PASSWORD" ]; then
            export PGPASSWORD="${DB_PASSWORD}"
        fi
        dump_command="pg_dump -U ${DB_USER} -h ${DB_HOST} -p ${DB_PORT} -d ${DB_NAME}"
    fi
    
    # Execute dump and compress
    if eval "${dump_command}" | gzip > "${BACKUP_FILE}"; then
        echo "✓ Database dump created successfully"
        return 0
    else
        echo "✗ Failed to create database dump"
        return 1
    fi
}

# Split and send file function
split_and_send_file() {
    local input_file="$1"
    local base_name=$(basename "${input_file}")
    local temp_dir="${BACKUP_DIR}/temp_split_$$"
    local chunk_size="${CHUNK_SIZE_MB}"
    
    echo "  [2/5] Preparing to split file..."
    echo "  Creating temporary directory: ${temp_dir}"
    mkdir -p "${temp_dir}"
    
    # Get file size
    local file_size_bytes=$(stat -c%s "${input_file}" 2>/dev/null || stat -f%z "${input_file}" 2>/dev/null)
    local file_size_mb=$((file_size_bytes / 1024 / 1024))
    local num_parts=$(( (file_size_mb + chunk_size - 1) / chunk_size ))
    
    echo "  File size: ${file_size_mb}MB"
    echo "  Chunk size: ${chunk_size}MB"
    echo "  Estimated parts: ${num_parts}"
    echo "  → Sending notification to Telegram..."
    telegram_send_message "${CHAT_ID}" "📦 Splitting backup into ${num_parts} parts..." "${BOT_TOKEN}"
    
    # Split the file
    echo "  [3/5] Splitting file into ${num_parts} parts..."
    if split -b ${chunk_size}m "${input_file}" "${temp_dir}/${base_name}.part_"; then
        echo "  ✓ File split completed"
    else
        echo "  ✗ Failed to split file"
        return 1
    fi
    
    # Count actual parts
    local part_count=0
    local part_number=1
    local total_parts=$(ls -1 "${temp_dir}/${base_name}.part_"* 2>/dev/null | wc -l)
    echo "  Actual parts created: ${total_parts}"
    
    # Send each part
    echo "  [4/5] Sending parts to Telegram..."
    for part in "${temp_dir}/${base_name}.part_"*; do
        if [ -f "${part}" ]; then
            local part_name="${base_name}.part${part_number}.gz"
            local part_path="${temp_dir}/${part_name}"
            
            echo "    → Processing part ${part_number}/${total_parts}"
            
            mv "${part}" "${part_path}"
            
            local part_size=$(stat -c%s "${part_path}" 2>/dev/null || stat -f%z "${part_path}" 2>/dev/null)
            local part_size_mb=$((part_size / 1024 / 1024))
            echo "      Part size: ${part_size_mb}MB"
            
            if [ -s "${part_path}" ]; then
                echo "      ✓ Part ${part_number} verified (non-empty)"
                
                local retry_count=0
                local success=0
                
                while [ ${retry_count} -lt ${MAX_RETRIES} ] && [ ${success} -eq 0 ]; do
                    echo "      → Sending part ${part_number} (attempt $((retry_count+1))/${MAX_RETRIES})..."
                    if telegram_send_document "${CHAT_ID}" "${part_path}" "Part ${part_number}/${total_parts}: ${base_name}" "${BOT_TOKEN}"; then
                        success=1
                        echo "      ✓ Part ${part_number} sent successfully"
                    else
                        retry_count=$((retry_count + 1))
                        echo "      ⚠️ Retry ${retry_count}/${MAX_RETRIES} for part ${part_number}"
                        if [ ${retry_count} -lt ${MAX_RETRIES} ]; then
                            echo "      Waiting 2 seconds before retry..."
                            sleep 2
                        fi
                    fi
                done
                
                if [ ${success} -eq 0 ]; then
                    echo "      ✗ Failed to send part ${part_number} after ${MAX_RETRIES} attempts"
                    telegram_send_message "${CHAT_ID}" "❌ Failed to send part ${part_number} after ${MAX_RETRIES} attempts" "${BOT_TOKEN}"
                    return 1
                fi
                
                part_count=$((part_count + 1))
                part_number=$((part_number + 1))
                
                rm -f "${part_path}"
                echo "      ✓ Part file cleaned up"
            else
                echo "      ✗ Part ${part_number} is empty or corrupt"
                telegram_send_message "${CHAT_ID}" "❌ Part ${part_number} is empty or corrupt" "${BOT_TOKEN}"
                return 1
            fi
            echo ""
        fi
    done
    
    # Cleanup
    echo "  [5/5] Cleaning up temporary files..."
    rmdir "${temp_dir}" 2>/dev/null || true
    echo "  ✓ Temporary directory removed"
    
    if [ ${part_count} -eq ${total_parts} ]; then
        echo "  ✓ All ${total_parts} parts sent successfully!"
        telegram_send_message "${CHAT_ID}" "✅ All ${total_parts} parts sent successfully!" "${BOT_TOKEN}"
        return 0
    else
        echo "  ⚠️ Expected ${total_parts} parts, but sent ${part_count}"
        telegram_send_message "${CHAT_ID}" "⚠️ Expected ${total_parts} parts, but sent ${part_count}" "${BOT_TOKEN}"
        return 1
    fi
}

# ========================================
# MAIN EXECUTION
# ========================================

# Create database dump
if ! create_database_dump; then
    echo "ERROR: Failed to create database dump"
    telegram_send_message "${CHAT_ID}" "❌ PostgreSQL backup FAILED - dump creation error!" "${BOT_TOKEN}"
    exit 1
fi

# Check backup file
echo "=========================================="
echo "[1/5] Verifying backup file..."
if [ -f "${BACKUP_FILE}" ]; then
    BACKUP_FILE_SIZE=$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || stat -f%z "${BACKUP_FILE}" 2>/dev/null)
    BACKUP_FILE_SIZE_MB=$((BACKUP_FILE_SIZE / 1024 / 1024))
    echo "✓ Backup file created successfully"
    echo "  File size: ${BACKUP_FILE_SIZE_MB}MB"
    echo "  File path: ${BACKUP_FILE}"
    echo ""
    
    echo "  → Sending start notification to Telegram..."
    telegram_send_message "${CHAT_ID}" "✅ PostgreSQL backup completed: $(basename "${BACKUP_FILE}") (${BACKUP_FILE_SIZE_MB}MB)" "${BOT_TOKEN}"
    
    MAX_SIZE_BYTES=$((TELEGRAM_MAX_SIZE * 1024 * 1024))
    
    if [ ${BACKUP_FILE_SIZE} -le ${MAX_SIZE_BYTES} ]; then
        echo "=========================================="
        echo "[2/5] File is under ${TELEGRAM_MAX_SIZE}MB, sending directly..."
        echo "  → Sending file to Telegram..."
        if telegram_send_document "${CHAT_ID}" "${BACKUP_FILE}" "PostgreSQL backup: $(basename "${BACKUP_FILE}")" "${BOT_TOKEN}"; then
            echo "  ✓ Backup file sent to Telegram successfully"
            echo "  ✓ Backup process completed"
        else
            echo "  ✗ Failed to send backup file"
            telegram_send_message "${CHAT_ID}" "❌ Failed to send backup file" "${BOT_TOKEN}"
            echo "=========================================="
            echo "ERROR: Backup process failed!"
            exit 1
        fi
    else
        echo "=========================================="
        echo "[2/5] File is larger than ${TELEGRAM_MAX_SIZE}MB (${BACKUP_FILE_SIZE_MB}MB)"
        echo "  Starting split and send process..."
        echo ""
        if split_and_send_file "${BACKUP_FILE}"; then
            echo "=========================================="
            echo "✓ Split backup sent to Telegram successfully"
            echo "✓ Backup process completed"
        else
            echo "=========================================="
            echo "✗ Failed to send split backup"
            telegram_send_message "${CHAT_ID}" "❌ Failed to send split backup" "${BOT_TOKEN}"
            echo "ERROR: Backup process failed!"
            exit 1
        fi
    fi
else
    echo "✗ Backup file not found: ${BACKUP_FILE}"
    telegram_send_message "${CHAT_ID}" "❌ PostgreSQL backup FAILED - file not created!" "${BOT_TOKEN}"
    echo "=========================================="
    echo "ERROR: Backup failed!"
    exit 1
fi

# Cleanup local files if configured
echo ""
echo "=========================================="
echo "Backup process completed successfully!"
echo "=========================================="
echo "Backup file: ${BACKUP_FILE}"
echo "File size: ${BACKUP_FILE_SIZE_MB}MB"
echo "Status: SENT TO TELEGRAM"
echo "=========================================="

if [ "${KEEP_LOCAL_COPIES}" = false ]; then
    rm -f "${BACKUP_FILE}"
    echo "✓ Original backup file deleted (KEEP_LOCAL_COPIES=false)"
fi
