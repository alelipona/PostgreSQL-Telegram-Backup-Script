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

# directory to put the backup files
BACKUP_DIR=./

# PostgreSQL Parameters
PG_USER=YOUR_POSTGRESQL_USERNAME
PG_HOST=localhost
PG_PORT=5432
# Для пароля используйте .pgpass файл или переменную окружения PGPASSWORD
# export PGPASSWORD=YOUR_POSTGRESQL_PASSWORD

# Don't backup databases with these names 
# Example: starts with template (^template) or ends with _template (_template$)
IGNORE_DB="(^template|_template$|^postgres$)"

# Include postgresql binaries for cron bash user
PATH=$PATH:/usr/bin:/usr/local/bin

# Number of days to keep backups on disk (0 to disable)
KEEP_BACKUPS_FOR=30 # days

# Token of Telegram bot
BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN

# chat_id of user who wants to get backup files in Telegram
CHAT_ID=YOUR_CHAT_ID

# Current time in YYYY-MM-DD format
DATE=$(date +%F)

function telegram_send_message() {
    curl -F chat_id="$1" -F text="$2" https://api.telegram.org/bot$BOT_TOKEN/sendMessage &> /dev/null
}

function telegram_send_document() {
    curl -F chat_id="$1" -F document=@"$2" caption="$3" https://api.telegram.org/bot$BOT_TOKEN/sendDocument &> /dev/null
}

function delete_old_backups() {
    if [ $KEEP_BACKUPS_FOR -ne 0 ]; then
        find $BACKUP_DIR -type f -name "*.sql.gz" -mtime +$KEEP_BACKUPS_FOR -exec rm {} \;
    fi
}

function pg_login() {
    local pg_login="-U $PG_USER -h $PG_HOST -p $PG_PORT"
    echo $pg_login
}

function database_list() {
    # Получаем список баз данных, исключая системные
    local show_databases_sql="SELECT datname FROM pg_database WHERE datname NOT SIMILAR TO '$IGNORE_DB' AND datistemplate = false;"
    echo $(psql $(pg_login) -t -c "$show_databases_sql" | grep -v '^$' | tr -d ' ')
}

function backup_database() {
    backup_file="$BACKUP_DIR/$DATE.$database.sql.gz"
    pg_dump $(pg_login) $database | gzip -9 > $backup_file
    
    # Проверяем размер файла
    backup_file_size=$(stat -c%s $backup_file)
    
    if [ $backup_file_size -le 50000000 ]; then
        # Отправляем файл бэкапа в Telegram
        telegram_send_document $CHAT_ID $backup_file "$DATE.$database.sql.gz"
    else
        # Разбиваем файл бэкапа, затем отправляем в Telegram
        # Создаем ZIP архив с разбивкой на части по 50MB
        zipped_backup_file="$BACKUP_DIR/$DATE.$database"
        zip -r -s 50m "$zipped_backup_file.zip" $backup_file
        
        # Отправляем файлы частей
        telegram_send_document $CHAT_ID "$zipped_backup_file.zip" "$DATE.$database.zip"
        
        if [ $KEEP_BACKUPS_FOR -eq 0 ]; then
            rm "$zipped_backup_file.zip"
        fi
        
        # Отправляем остальные части
        for i in $(seq -f "%02g" 1 9); do
            if [ -f "$zipped_backup_file.z$i" ]; then
                telegram_send_document $CHAT_ID "$zipped_backup_file.z$i" "$DATE.$database.z$i"
                if [ $KEEP_BACKUPS_FOR -eq 0 ]; then
                    rm "$zipped_backup_file.z$i"
                fi
            fi
        done
    fi
    
    if [ $KEEP_BACKUPS_FOR -eq 0 ]; then
        rm $backup_file
    fi
}

function backup_databases() {
    # Отправляем текущую дату в Telegram
    telegram_send_message $CHAT_ID "PostgreSQL Backup - $DATE:"
    
    for database in $(database_list); do
        if [ ! -z "$database" ]; then
            echo "Backing up database: $database"
            backup_database
        fi
    done
}

# Удаляем старые бэкапы
delete_old_backups

# Создаем новые бэкапы
backup_databases
