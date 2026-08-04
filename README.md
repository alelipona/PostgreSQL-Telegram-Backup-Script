# PostgreSQL Telegram Backup Script

Script for automated PostgreSQL database backups sent to Telegram.

This script is forked from [nimah79/Telegram-MySQL-Backup](https://github.com/nimah79/Telegram-MySQL-Backup) and adapted for PostgreSQL.

## Description

Creates compressed dumps of PostgreSQL databases and sends them to Telegram via bot. Supports both direct and Docker environments. Automatically splits large files (>50MB) into smaller parts and sends them with retry mechanism.

## Features

- Automatic database dump creation
- Send backups to Telegram
- Automatic file splitting for large backups (>50MB)
- Retry mechanism for failed sends
- Docker and non-Docker environments support
- Configurable backup retention
- Detailed logging

## Installation

### Prerequisites

- PostgreSQL client tools (pg_dump, psql)
- Bash 4.0+
- curl
- split (usually pre-installed)

### Setup

1. Make script executable:

`chmod +x backup.sh`

2. Edit configuration in script:

`BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN`
`CHAT_ID=YOUR_CHAT_ID`
`DB_CONTAINER=postgres`
`DB_USER=postgres`
`DB_NAME=postgres`
`BACKUP_DIR=./backups`

### Docker Setup (if using Docker)

For Docker environments, configure:

`USE_DOCKER=true`
`DOCKER_SERVICE=postgres`

For non-Docker environments:

`USE_DOCKER=false`
`DB_HOST=localhost`
`DB_PORT=5432`

### Password Setup

Create .pgpass file:

`echo "localhost:5432:*:username:password" > ~/.pgpass`
`chmod 600 ~/.pgpass`

Or use environment variable:

`export PGPASSWORD=your_password`

Or set in script:

`DB_PASSWORD=your_password`

## Telegram Bot Setup

1. Message @BotFather on Telegram
2. Use /newbot command
3. Get bot token
4. Get CHAT_ID via @userinfobot

## Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| BOT_TOKEN | Telegram bot token | YOUR_TELEGRAM_BOT_TOKEN |
| CHAT_ID | Telegram chat ID | YOUR_CHAT_ID |
| DB_CONTAINER | Docker container name | postgres |
| DB_USER | PostgreSQL username | postgres |
| DB_NAME | Database name to backup | postgres |
| DB_HOST | PostgreSQL host | localhost |
| DB_PORT | PostgreSQL port | 5432 |
| BACKUP_DIR | Backup directory | ./backups |
| BACKUP_PREFIX | Backup file prefix | postgres_backup |
| KEEP_LOCAL_COPIES | Keep local backup files | true |
| TELEGRAM_MAX_SIZE | Max file size in MB | 50 |
| USE_DOCKER | Use docker compose | true |
| DOCKER_COMPOSE_FILE | Docker compose file | docker-compose.yml |
| DOCKER_SERVICE | Docker service name | postgres |
| CHUNK_SIZE_MB | Split chunk size in MB | 48 |
| MAX_RETRIES | Retry attempts for sending | 3 |

## Cron Schedule

Add to crontab for daily backup at 2:00 AM:

`0 2 * * * /path/to/backup.sh`

## Restore from Backup

### Restore single database (for files under 50MB):

`gunzip < backup_file.sql.gz | psql -U username -d database_name`

### Restore from split parts (for files over 50MB):

1. Download all parts to the same directory
2. Combine parts:

`cat postgres_backup_*.part*.gz > restored_backup.sql.gz`

3. Uncompress and restore:

`gunzip restored_backup.sql.gz`
`psql -U username -d database_name < restored_backup.sql`

### Restore with Docker:

`cat postgres_backup_*.part*.gz | gunzip | docker compose exec -T postgres psql -U postgres -d database_name`

## Troubleshooting

### Test PostgreSQL connection:

`psql -U username -h localhost -p 5432 -c "SELECT 1"`

### Test PostgreSQL connection with Docker:

`docker compose exec -T postgres psql -U postgres -c "SELECT 1"`

### Test Telegram bot:

`curl https://api.telegram.org/bot<TOKEN>/getMe`

### Check CHAT_ID:

`curl https://api.telegram.org/bot<TOKEN>/getUpdates`

### Check backup file integrity:

`gzip -t backup_file.sql.gz`

## License

MIT License
