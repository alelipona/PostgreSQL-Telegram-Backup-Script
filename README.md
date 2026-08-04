# PostgreSQL Telegram Backup Script

Script for automated PostgreSQL database backups sent to Telegram.
This script is forked from [nimah79/Telegram-MySQL-Backup](https://github.com/nimah79/Telegram-MySQL-Backup) and adapted for PostgreSQL.

## Description

Creates compressed dumps of PostgreSQL databases and sends them to Telegram via bot. Excludes system databases.

## Installation

### Prerequisites
- PostgreSQL client tools (pg_dump, psql)
- Bash
- curl
- zip/unzip

### Setup

1. Make script executable:
chmod +x Telegram-PostgreSQL-Backup.sh

text

2. Edit configuration in script:
PG_USER=YOUR_POSTGRESQL_USERNAME
PG_HOST=localhost
PG_PORT=5432
BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN
CHAT_ID=YOUR_CHAT_ID

text

### Password Setup

Create .pgpass file:
echo "localhost:5432:*:username:password" > ~/.pgpass
chmod 600 ~/.pgpass

text

Or use environment variable:
export PGPASSWORD=your_password

text

## Telegram Bot Setup

1. Message @BotFather on Telegram
2. Use /newbot command
3. Get bot token
4. Get CHAT_ID via @userinfobot

## Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| PG_USER | PostgreSQL username | YOUR_POSTGRESQL_USERNAME |
| PG_HOST | PostgreSQL host | localhost |
| PG_PORT | PostgreSQL port | 5432 |
| BACKUP_DIR | Backup directory | ./ |
| KEEP_BACKUPS_FOR | Days to keep backups | 30 |
| IGNORE_DB | Databases to exclude | (^template|_template$|^postgres$) |
| BOT_TOKEN | Telegram bot token | YOUR_TELEGRAM_BOT_TOKEN |
| CHAT_ID | Telegram chat ID | YOUR_CHAT_ID |

## Cron Schedule

Add to crontab for daily backup at 2:00 AM:
0 2 * * * /path/to/Telegram-PostgreSQL-Backup.sh

text

## Restore from Backup

Restore single database:
gunzip < backup_file.sql.gz | psql -U username -d database_name

text

Restore from split zip:
cat backup.z01 backup.z02 backup.zip > combined.zip
unzip combined.zip
gunzip < backup.sql.gz | psql -U username -d database_name

text

## Troubleshooting

Test PostgreSQL connection:
psql -U username -h localhost -p 5432 -c "SELECT 1"

text

Test Telegram bot:
curl https://api.telegram.org/bot<TOKEN>/getMe

text

Check CHAT_ID:
curl https://api.telegram.org/bot<TOKEN>/getUpdates

text

## License

MIT License
