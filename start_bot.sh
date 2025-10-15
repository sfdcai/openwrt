#!/bin/bash
# Advanced Telegram Bot Startup Script for OpenWRT

SCRIPT_DIR="/root/openwrt-config-manager"
BOT_SCRIPT="$SCRIPT_DIR/advanced_telegram_bot.py"
PID_FILE="/var/run/advanced_telegram_bot.pid"
LOG_FILE="/var/log/advanced_telegram_bot.log"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root"
    exit 1
fi

# Check if bot is already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Advanced Telegram Bot is already running (PID: $PID)"
        exit 1
    else
        echo "Removing stale PID file"
        rm -f "$PID_FILE"
    fi
fi

# Check if config exists
if [ ! -f "/etc/telegram-bot/config.json" ]; then
    echo "Error: Telegram bot configuration not found!"
    echo "Please run the main setup script first to configure the bot token."
    exit 1
fi

# Make sure the script is executable
chmod +x "$BOT_SCRIPT"

echo "Starting Advanced Telegram Bot..."
echo "Log file: $LOG_FILE"
echo "PID file: $PID_FILE"

# Start the bot in background (OpenWRT compatible)
python3 "$BOT_SCRIPT" > "$LOG_FILE" 2>&1 &

# Save PID
echo $! > "$PID_FILE"

# Wait a moment to ensure it started
sleep 2

# Check if it's actually running
if ps -p $(cat "$PID_FILE") > /dev/null 2>&1; then
    echo "Bot started successfully (PID: $(cat "$PID_FILE"))"
else
    echo "Warning: Bot may not have started properly. Check logs:"
    tail -5 "$LOG_FILE"
fi

echo "Advanced Telegram Bot started successfully!"
echo "Use 'tail -f $LOG_FILE' to view logs"
echo "Use 'kill \$(cat $PID_FILE)' to stop the bot"
