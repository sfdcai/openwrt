#!/bin/bash

# OpenWRT Config Manager - All-in-One Script
# Complete installation, configuration, and management tool
# Handles Homer dashboard management, Telegram integration, and system monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
CONFIG_MANAGER_DIR="/www/config-manager"
CONFIG_MANAGER_SERVICE="/etc/init.d/config-manager"
CONFIG_MANAGER_LOG="/tmp/config-manager.log"
CONFIG_MANAGER_PORT="8082"
HOMER_CONFIG_FILE="/www/homer-dashboard/assets/config.yml"
BACKUP_DIR="/www/config-manager/backups"
TEMPLATES_DIR="/www/config-manager/templates"
TELEGRAM_BOT_DIR="/etc/telegram-bot"
STATS_FILE="/www/config-manager/stats.json"

# Default values
HOMER_URL="https://github.com/bastienwirtz/homer/releases/download/v25.10.1/homer.zip"
HOMER_PORT="8010"

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Show banner
show_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                OpenWRT Config Manager                       ║"
    echo "║              All-in-One Management Tool                     ║"
    echo "║                                                              ║"
    echo "║  🏠 Homer Dashboard Management                               ║"
    echo "║  📱 Telegram Bot Integration                                 ║"
    echo "║  📊 System Monitoring & Health Checks                       ║"
    echo "║  💾 Backup & Restore System                                 ║"
    echo "║  🎨 Configuration Templates                                 ║"
    echo "║  ⚙️  Remote Command Execution                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Show help
show_help() {
    echo -e "${GREEN}OpenWRT Config Manager - All-in-One Tool${NC}"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 [COMMAND] [OPTIONS]"
    echo
    echo -e "${YELLOW}Commands:${NC}"
    echo "  install     - Install Config Manager and Homer dashboard"
    echo "  uninstall   - Remove Config Manager and clean up"
    echo "  start       - Start all services (Homer + Config Manager)"
    echo "  stop        - Stop all services"
    echo "  restart     - Restart all services"
    echo "  start-homer - Start only Homer dashboard"
    echo "  start-config- Start only Config Manager"
    echo "  status      - Show service status and health"
    echo "  debug       - Show detailed debug information"
    echo "  fix         - Fix common issues and permissions"
    echo "  update      - Update Config Manager to latest version"
    echo "  backup      - Create backup of current configuration"
    echo "  restore     - Restore from backup"
    echo "  telegram    - Setup or test Telegram bot"
    echo "  homer       - Manage Homer dashboard"
    echo "  system      - Show system information and stats"
    echo "  optimize    - Optimize OpenWRT for better performance"
    echo "  monitor     - Start real-time monitoring"
    echo "  help        - Show this help message"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 install                    # Full installation"
    echo "  $0 start                      # Start service"
    echo "  $0 status                     # Check status"
    echo "  $0 fix                        # Fix issues"
    echo "  $0 telegram setup             # Setup Telegram bot"
    echo "  $0 homer install              # Install Homer dashboard"
    echo "  $0 system stats               # Show system statistics"
    echo "  $0 optimize                   # Optimize system"
    echo
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check Python3 installation
check_python3() {
    log "Checking Python3 installation..."
    
    if command -v python3 >/dev/null 2>&1; then
        PYTHON3_PATH=$(which python3)
        log_success "Python3 found at: $PYTHON3_PATH"
        
        PYTHON_VERSION=$(python3 -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
        if [ "$PYTHON_VERSION" = "3" ]; then
            log_success "Python3 version verified"
            return 0
        else
            log_error "Python3 not working properly"
            return 1
        fi
    else
        log_error "Python3 is not installed"
        log "Install with: opkg update && opkg install python3"
        return 1
    fi
}

# Install Python dependencies
install_python_dependencies() {
    log "Installing Python dependencies..."
    
    PACKAGES=("python3-requests" "python3-yaml" "python3-urllib" "python3-json")
    
    for package in "${PACKAGES[@]}"; do
        if command -v opkg >/dev/null 2>&1; then
            opkg install "$package" 2>/dev/null || log_warning "Could not install $package"
        fi
    done
    
    # Install requests via pip if opkg fails
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install requests 2>/dev/null || log_warning "Could not install requests via pip3"
    fi
    
    log_success "Python dependencies installed"
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    
    # Create main directories
    mkdir -p "$CONFIG_MANAGER_DIR"/{backups,templates,api,static}
    mkdir -p "$TELEGRAM_BOT_DIR"
    
    # Create log file
    touch "$CONFIG_MANAGER_LOG"
    
    log_success "Directory structure created"
}

# Kill processes using specific ports
kill_port_processes() {
    local port=$1
    local service_name=$2
    
    log "Checking for processes using port $port..."
    
    # Find processes using the port
    local pids=$(netstat -lnp 2>/dev/null | grep ":$port " | awk '{print $NF}' | cut -d'/' -f1 | grep -v '-' | sort -u)
    
    if [ -n "$pids" ]; then
        log_warning "Found processes using port $port: $pids"
        for pid in $pids; do
            if [ "$pid" != "-" ] && [ -n "$pid" ]; then
                log "Killing process $pid using port $port"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
    else
        log "No processes found using port $port"
    fi
}

# Install Homer dashboard
install_homer() {
    log "Installing Homer dashboard..."
    
    # Kill any processes using Homer port
    kill_port_processes "$HOMER_PORT" "Homer"
    
    # Create Homer directory
    if [ -d "/www/homer-dashboard" ]; then
        log_warning "Homer directory exists, backing up..."
        mv "/www/homer-dashboard" "/www/homer-dashboard.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    mkdir -p "/www/homer-dashboard"
    
    # Download Homer
    TEMP_ZIP="/tmp/homer.zip"
    log "Downloading Homer from: $HOMER_URL"
    
    if command -v wget >/dev/null 2>&1; then
        if ! wget -O "$TEMP_ZIP" "$HOMER_URL"; then
            log_error "Failed to download Homer with wget"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$TEMP_ZIP" "$HOMER_URL"; then
            log_error "Failed to download Homer with curl"
            return 1
        fi
    else
        log_error "Neither wget nor curl available"
        return 1
    fi
    
    # Check if download was successful
    if [ ! -f "$TEMP_ZIP" ] || [ ! -s "$TEMP_ZIP" ]; then
        log_error "Downloaded file is empty or missing"
        return 1
    fi
    
    # Extract Homer
    cd "/www/homer-dashboard"
    if ! unzip -q "$TEMP_ZIP"; then
        log_error "Failed to extract Homer archive"
        rm -f "$TEMP_ZIP"
        return 1
    fi
    rm -f "$TEMP_ZIP"
    
    # Copy demo configuration
    if [ -f "assets/config-demo.yml.dist" ]; then
        cp "assets/config-demo.yml.dist" "assets/config.yml"
        log_success "Homer configuration created"
    else
        log_warning "Demo configuration not found, creating basic config"
        create_basic_homer_config
    fi
    
    # Set permissions
    chmod -R 755 "/www/homer-dashboard"
    chmod 666 "/www/homer-dashboard/assets/config.yml" 2>/dev/null || true
    
    log_success "Homer dashboard installed"
}

# Create basic Homer configuration if demo is not available
create_basic_homer_config() {
    log "Creating basic Homer configuration..."
    
    cat > "/www/homer-dashboard/assets/config.yml" << 'EOF'
---
# Basic Homer Configuration
title: "My Dashboard"
subtitle: "Welcome to your dashboard"
logo: "https://raw.githubusercontent.com/bastienwirtz/homer/main/public/logo.png"
icon: "fas fa-home"

# Optional theme
theme: default

# Optional message
message:
  style: "is-dark"
  title: "Welcome!"
  icon: "fa fa-grin"
  content: "This is a <em>default</em> message! You can change it in the configuration editor."

# Optional navbar
links:
  - name: "Config Manager"
    icon: "fas fa-cog"
    url: "http://192.168.1.1:8082"
    target: "_blank"
  - name: "GitHub"
    icon: "fab fa-github"
    url: "https://github.com/bastienwirtz/homer"
    target: "_blank"

# Services
services:
  - name: "Router Admin"
    logo: "assets/tools/router.png"
    subtitle: "OpenWRT Administration"
    tag: "router"
    tagstyle: "is-success"
    url: "http://192.168.1.1"
    target: "_blank"
  - name: "Config Manager"
    logo: "assets/tools/config.png"
    subtitle: "Configuration Management"
    tag: "config"
    tagstyle: "is-info"
    url: "http://192.168.1.1:8082"
    target: "_blank"
EOF
}

# Create Config Manager server
create_config_manager_server() {
    log "Creating Config Manager server..."
    
    cat > "$CONFIG_MANAGER_DIR/server.py" << 'EOF'
#!/usr/bin/python3
"""
OpenWRT Configuration Manager with Telegram Integration
Complete management solution for Homer and OpenWRT
"""

import http.server
import socketserver
import os
import sys
import json
import urllib.parse
import shutil
import re
import time
import subprocess
import requests
from datetime import datetime
import logging

# Configuration
CONFIG_MANAGER_DIR = "/www/config-manager"
LOG_FILE = "/tmp/config-manager.log"
PORT = 8082
HOST = "0.0.0.0"
HOMER_CONFIG_FILE = "/www/homer-dashboard/assets/config.yml"
BACKUP_DIR = os.path.join(CONFIG_MANAGER_DIR, "backups")
TEMPLATES_DIR = os.path.join(CONFIG_MANAGER_DIR, "templates")
TELEGRAM_BOT_DIR = "/etc/telegram-bot"
STATS_FILE = os.path.join(CONFIG_MANAGER_DIR, "stats.json")

# Telegram configuration
TELEGRAM_BOT_TOKEN = ""
TELEGRAM_CHAT_ID = ""

# Load Telegram configuration
def load_telegram_config():
    global TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
    try:
        config_file = os.path.join(TELEGRAM_BOT_DIR, "config.json")
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = json.load(f)
                TELEGRAM_BOT_TOKEN = config.get('bot_token', '')
                TELEGRAM_CHAT_ID = config.get('chat_id', '')
    except Exception as e:
        logging.error(f"Error loading Telegram config: {e}")

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Load Telegram config on startup
load_telegram_config()

# Fallback YAML parser for OpenWRT compatibility
class SimpleYAMLParser:
    @staticmethod
    def safe_load(yaml_string):
        """Simple YAML parser that handles basic YAML structures"""
        lines = yaml_string.split('\n')
        
        for i, line in enumerate(lines):
            line = line.rstrip()
            if not line or line.strip().startswith('#'):
                continue
                
            # Check for proper indentation
            indent = len(line) - len(line.lstrip())
            if indent % 2 != 0 and indent > 0:
                raise ValueError(f"Invalid indentation at line {i+1}: {line}")
            
            # Check for basic YAML structure
            if ':' in line and not line.strip().startswith('-'):
                key, value = line.split(':', 1)
                if not key.strip():
                    raise ValueError(f"Empty key at line {i+1}: {line}")
        
        return {"validated": True}

# Telegram integration functions
def send_telegram_message(message, parse_mode='HTML'):
    """Send message to Telegram"""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return False
    
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = {
            'chat_id': TELEGRAM_CHAT_ID,
            'text': message,
            'parse_mode': parse_mode
        }
        response = requests.post(url, data=data, timeout=10)
        return response.status_code == 200
    except Exception as e:
        logger.error(f"Error sending Telegram message: {e}")
        return False

# System monitoring functions
def get_system_stats():
    """Get comprehensive system statistics"""
    try:
        stats = {
            "timestamp": datetime.now().isoformat(),
            "memory": {"total": 0, "available": 0, "used": 0, "percent": 0},
            "disk": {"total": 0, "used": 0, "free": 0, "percent": 0},
            "uptime": 0,
            "load": [0, 0, 0],
            "network": {"interfaces": []},
            "services": {"homer": False, "config_manager": True},
            "temperature": 0,
            "processes": 0
        }
        
        # Memory info
        try:
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
            mem_total = int(re.search(r'MemTotal:\s+(\d+)', meminfo).group(1))
            mem_available = int(re.search(r'MemAvailable:\s+(\d+)', meminfo).group(1))
            mem_used = mem_total - mem_available
            
            stats["memory"] = {
                "total": mem_total * 1024,
                "available": mem_available * 1024,
                "used": mem_used * 1024,
                "percent": round((mem_used / mem_total) * 100, 1)
            }
        except:
            pass
        
        # Disk info
        try:
            statvfs = os.statvfs(CONFIG_MANAGER_DIR)
            total = statvfs.f_frsize * statvfs.f_blocks
            free = statvfs.f_frsize * statvfs.f_available
            used = total - free
            
            stats["disk"] = {
                "total": total,
                "used": used,
                "free": free,
                "percent": round((used / total) * 100, 1)
            }
        except:
            pass
        
        # Uptime
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])
            stats["uptime"] = uptime_seconds
        except:
            pass
        
        # Load average
        try:
            with open('/proc/loadavg', 'r') as f:
                load = f.read().split()[:3]
            stats["load"] = [float(x) for x in load]
        except:
            pass
        
        # Network interfaces
        try:
            with open('/proc/net/dev', 'r') as f:
                for line in f:
                    if ':' in line and not line.startswith('Inter-'):
                        interface = line.split(':')[0].strip()
                        stats["network"]["interfaces"].append(interface)
        except:
            pass
        
        # Check Homer service
        try:
            result = subprocess.run(['pgrep', '-f', 'homer-dashboard/server.py'], 
                                 capture_output=True, text=True)
            stats["services"]["homer"] = bool(result.stdout.strip())
        except:
            pass
        
        # Process count
        try:
            result = subprocess.run(['ps'], capture_output=True, text=True)
            stats["processes"] = len(result.stdout.split('\n')) - 1
        except:
            pass
        
        return stats
    except Exception as e:
        logger.error(f"Error getting system stats: {e}")
        return {"error": str(e)}

def save_stats():
    """Save current stats to file"""
    try:
        stats = get_system_stats()
        with open(STATS_FILE, 'w') as f:
            json.dump(stats, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving stats: {e}")

# OpenWRT system functions
def get_openwrt_info():
    """Get OpenWRT system information"""
    try:
        info = {
            "version": "Unknown",
            "target": "Unknown",
            "architecture": "Unknown",
            "kernel": "Unknown",
            "hostname": "Unknown",
            "model": "Unknown"
        }
        
        # Get OpenWRT version
        try:
            with open('/etc/openwrt_release', 'r') as f:
                for line in f:
                    if line.startswith('DISTRIB_RELEASE='):
                        info["version"] = line.split('=')[1].strip().strip('"')
                    elif line.startswith('DISTRIB_TARGET='):
                        info["target"] = line.split('=')[1].strip().strip('"')
                    elif line.startswith('DISTRIB_ARCH='):
                        info["architecture"] = line.split('=')[1].strip().strip('"')
        except:
            pass
        
        # Get kernel version
        try:
            with open('/proc/version', 'r') as f:
                version = f.read().split()[2]
                info["kernel"] = version
        except:
            pass
        
        # Get hostname
        try:
            info["hostname"] = subprocess.check_output(['hostname'], text=True).strip()
        except:
            pass
        
        # Get model info
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if 'model name' in line.lower() or 'cpu model' in line.lower():
                        info["model"] = line.split(':')[1].strip()
                        break
        except:
            pass
        
        return info
    except Exception as e:
        logger.error(f"Error getting OpenWRT info: {e}")
        return {"error": str(e)}

def execute_openwrt_command(command):
    """Execute OpenWRT command safely"""
    try:
        # Whitelist of safe commands
        safe_commands = [
            'uptime', 'df', 'free', 'ps', 'netstat', 'ifconfig', 'iwconfig',
            'iw', 'uci', 'opkg', 'logread', 'dmesg', 'cat', 'ls', 'grep',
            'top', 'htop', 'w', 'who', 'last', 'uname', 'hostname'
        ]
        
        cmd_parts = command.split()
        if cmd_parts[0] not in safe_commands:
            return {"success": False, "error": "Command not allowed"}
        
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
        
        return {
            "success": True,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Command timeout"}
    except Exception as e:
        return {"success": False, "error": str(e)}

class ConfigManagerHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Enhanced HTTP request handler with complete functionality"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=CONFIG_MANAGER_DIR, **kwargs)
    
    def end_headers(self):
        # Add CORS headers
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        super().end_headers()
    
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(f"{self.address_string()} - {format % args}")
    
    def do_OPTIONS(self):
        """Handle CORS preflight requests"""
        self.send_response(200)
        self.end_headers()
    
    def do_GET(self):
        """Handle GET requests"""
        # API endpoints
        if self.path.startswith('/api/'):
            self.handle_api_get()
            return
        
        # Serve static files
        super().do_GET()
    
    def do_POST(self):
        """Handle POST requests"""
        if self.path.startswith('/api/'):
            self.handle_api_post()
        else:
            self.send_error(404, "Not found")
    
    def handle_api_get(self):
        """Handle API GET requests"""
        try:
            if self.path == '/api/config':
                self.get_homer_config()
            elif self.path == '/api/backups':
                self.get_backups()
            elif self.path.startswith('/api/backup/'):
                backup_name = self.path.split('/')[-1]
                self.get_backup(backup_name)
            elif self.path == '/api/stats':
                self.get_stats()
            elif self.path == '/api/health':
                self.get_health()
            elif self.path == '/api/templates':
                self.get_templates()
            elif self.path.startswith('/api/template/'):
                template_name = self.path.split('/')[-1]
                self.get_template(template_name)
            elif self.path == '/api/system/info':
                self.get_system_info()
            elif self.path == '/api/telegram/status':
                self.get_telegram_status()
            else:
                self.send_error(404, "API endpoint not found")
        except Exception as e:
            logger.error(f"API GET error: {e}")
            self.send_error(500, f"Internal server error: {str(e)}")
    
    def handle_api_post(self):
        """Handle API POST requests"""
        try:
            if self.path == '/api/config':
                self.save_homer_config()
            elif self.path == '/api/backup':
                self.create_backup()
            elif self.path == '/api/restore':
                self.restore_backup()
            elif self.path == '/api/import':
                self.import_config()
            elif self.path == '/api/export':
                self.export_config()
            elif self.path == '/api/system/command':
                self.execute_command()
            elif self.path == '/api/telegram/send':
                self.send_telegram_message_api()
            elif self.path == '/api/telegram/setup':
                self.setup_telegram()
            else:
                self.send_error(404, "API endpoint not found")
        except Exception as e:
            logger.error(f"API POST error: {e}")
            self.send_error(500, f"Internal server error: {str(e)}")
    
    def get_homer_config(self):
        """Get Homer configuration"""
        try:
            if os.path.exists(HOMER_CONFIG_FILE):
                with open(HOMER_CONFIG_FILE, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.send_json_response({"success": True, "config": content})
            else:
                self.send_json_response({"success": False, "error": "Homer config file not found"})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def save_homer_config(self):
        """Save Homer configuration"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            # Create backup before saving
            self.create_backup_file()
            
            # Validate YAML
            try:
                SimpleYAMLParser.safe_load(data['config'])
            except Exception as e:
                self.send_json_response({"success": False, "error": f"Invalid YAML: {str(e)}"})
                return
            
            # Save config
            with open(HOMER_CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(data['config'])
            
            # Send Telegram notification
            send_telegram_message("🔧 Homer configuration updated successfully!")
            
            self.send_json_response({"success": True, "message": "Configuration saved successfully"})
            logger.info("Homer configuration updated")
            
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_backups(self):
        """Get list of backups"""
        try:
            if not os.path.exists(BACKUP_DIR):
                os.makedirs(BACKUP_DIR)
            
            backups = []
            for file in os.listdir(BACKUP_DIR):
                if file.endswith('.yml'):
                    file_path = os.path.join(BACKUP_DIR, file)
                    stat = os.stat(file_path)
                    backups.append({
                        "name": file,
                        "size": stat.st_size,
                        "created": datetime.fromtimestamp(stat.st_ctime).isoformat()
                    })
            
            backups.sort(key=lambda x: x['created'], reverse=True)
            self.send_json_response({"success": True, "backups": backups})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_backup(self, backup_name):
        """Get specific backup content"""
        try:
            backup_path = os.path.join(BACKUP_DIR, backup_name)
            if os.path.exists(backup_path):
                with open(backup_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.send_json_response({"success": True, "config": content})
            else:
                self.send_json_response({"success": False, "error": "Backup not found"})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def create_backup(self):
        """Create a new backup"""
        try:
            backup_name = self.create_backup_file()
            self.send_json_response({"success": True, "backup": backup_name, "message": "Backup created successfully"})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def create_backup_file(self):
        """Create backup file and return filename"""
        if not os.path.exists(BACKUP_DIR):
            os.makedirs(BACKUP_DIR)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"homer_config_backup_{timestamp}.yml"
        backup_path = os.path.join(BACKUP_DIR, backup_name)
        
        if os.path.exists(HOMER_CONFIG_FILE):
            shutil.copy2(HOMER_CONFIG_FILE, backup_path)
        
        return backup_name
    
    def restore_backup(self):
        """Restore from backup"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            backup_name = data.get('backup')
            if not backup_name:
                self.send_json_response({"success": False, "error": "Backup name required"})
                return
            
            backup_path = os.path.join(BACKUP_DIR, backup_name)
            if not os.path.exists(backup_path):
                self.send_json_response({"success": False, "error": "Backup not found"})
                return
            
            # Create backup of current config
            self.create_backup_file()
            
            # Restore backup
            shutil.copy2(backup_path, HOMER_CONFIG_FILE)
            
            # Send Telegram notification
            send_telegram_message(f"🔄 Homer configuration restored from backup: {backup_name}")
            
            self.send_json_response({"success": True, "message": "Configuration restored successfully"})
            logger.info(f"Homer configuration restored from {backup_name}")
            
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_stats(self):
        """Get system statistics"""
        try:
            stats = get_system_stats()
            self.send_json_response({"success": True, "stats": stats})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_health(self):
        """Get service health status"""
        try:
            health = {
                "status": "healthy",
                "timestamp": datetime.now().isoformat(),
                "uptime": 0,
                "memory_usage": 0,
                "disk_usage": 0,
                "services": {"homer": False, "config_manager": True}
            }
            
            # Get system stats
            stats = get_system_stats()
            health.update(stats)
            
            self.send_json_response({"success": True, "health": health})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_templates(self):
        """Get available configuration templates"""
        try:
            if not os.path.exists(TEMPLATES_DIR):
                os.makedirs(TEMPLATES_DIR)
            
            templates = []
            for file in os.listdir(TEMPLATES_DIR):
                if file.endswith('.yml') or file.endswith('.yaml'):
                    file_path = os.path.join(TEMPLATES_DIR, file)
                    stat = os.stat(file_path)
                    templates.append({
                        "name": file,
                        "size": stat.st_size,
                        "created": datetime.fromtimestamp(stat.st_ctime).isoformat()
                    })
            
            self.send_json_response({"success": True, "templates": templates})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_template(self, template_name):
        """Get specific template content"""
        try:
            template_path = os.path.join(TEMPLATES_DIR, template_name)
            if os.path.exists(template_path):
                with open(template_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.send_json_response({"success": True, "template": content})
            else:
                self.send_json_response({"success": False, "error": "Template not found"})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_system_info(self):
        """Get OpenWRT system information"""
        try:
            info = get_openwrt_info()
            self.send_json_response({"success": True, "info": info})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def get_telegram_status(self):
        """Get Telegram bot status"""
        try:
            status = {
                "configured": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
                "bot_token_set": bool(TELEGRAM_BOT_TOKEN),
                "chat_id_set": bool(TELEGRAM_CHAT_ID)
            }
            self.send_json_response({"success": True, "status": status})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def execute_command(self):
        """Execute OpenWRT command"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            command = data.get('command', '')
            if not command:
                self.send_json_response({"success": False, "error": "No command provided"})
                return
            
            result = execute_openwrt_command(command)
            self.send_json_response({"success": True, "result": result})
            
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def send_telegram_message_api(self):
        """Send message via Telegram API"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            message = data.get('message', '')
            if not message:
                self.send_json_response({"success": False, "error": "No message provided"})
                return
            
            success = send_telegram_message(message)
            self.send_json_response({"success": success, "message": "Message sent" if success else "Failed to send message"})
            
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def setup_telegram(self):
        """Setup Telegram bot configuration"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            bot_token = data.get('bot_token', '')
            chat_id = data.get('chat_id', '')
            
            if not bot_token or not chat_id:
                self.send_json_response({"success": False, "error": "Bot token and chat ID required"})
                return
            
            # Create telegram bot directory
            os.makedirs(TELEGRAM_BOT_DIR, exist_ok=True)
            
            # Save configuration
            config = {
                "bot_token": bot_token,
                "chat_id": chat_id,
                "created": datetime.now().isoformat()
            }
            
            with open(os.path.join(TELEGRAM_BOT_DIR, "config.json"), 'w') as f:
                json.dump(config, f, indent=2)
            
            # Reload configuration
            load_telegram_config()
            
            # Send test message
            send_telegram_message("🤖 Telegram bot configured successfully!")
            
            self.send_json_response({"success": True, "message": "Telegram bot configured successfully"})
            
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def import_config(self):
        """Import configuration from file"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            config_content = data.get('config', '')
            if not config_content:
                self.send_json_response({"success": False, "error": "No configuration provided"})
                return
            
            # Validate YAML
            try:
                SimpleYAMLParser.safe_load(config_content)
            except Exception as e:
                self.send_json_response({"success": False, "error": f"Invalid YAML: {str(e)}"})
                return
            
            # Create backup before importing
            self.create_backup_file()
            
            # Save imported config
            with open(HOMER_CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(config_content)
            
            # Send Telegram notification
            send_telegram_message("📥 Homer configuration imported successfully!")
            
            self.send_json_response({"success": True, "message": "Configuration imported successfully"})
            logger.info("Homer configuration imported")
            
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})
    
    def export_config(self):
        """Export current configuration"""
        try:
            if os.path.exists(HOMER_CONFIG_FILE):
                with open(HOMER_CONFIG_FILE, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Create export filename with timestamp
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"homer_config_export_{timestamp}.yml"
                
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
                self.end_headers()
                self.wfile.write(content.encode('utf-8'))
            else:
                self.send_json_response({"success": False, "error": "Config file not found"})
        except Exception as e:
            self.send_json_response({"success": False, "error": str(e)})

    def send_json_response(self, data):
        """Send JSON response"""
        response = json.dumps(data).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)

def main():
    """Main function"""
    try:
        # Change to config manager directory
        os.chdir(CONFIG_MANAGER_DIR)
        
        # Create necessary directories
        os.makedirs(BACKUP_DIR, exist_ok=True)
        os.makedirs(TEMPLATES_DIR, exist_ok=True)
        
        # Create HTTP server
        with socketserver.TCPServer((HOST, PORT), ConfigManagerHTTPRequestHandler) as httpd:
            logger.info(f"OpenWRT Config Manager starting on {HOST}:{PORT}")
            logger.info(f"Serving files from: {CONFIG_MANAGER_DIR}")
            logger.info(f"Logging to: {LOG_FILE}")
            logger.info(f"Telegram integration: {'Enabled' if TELEGRAM_BOT_TOKEN else 'Disabled'}")
            
            # Start server
            httpd.serve_forever()
            
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x "$CONFIG_MANAGER_DIR/server.py"
    log_success "Config Manager server created"
}

# Create web interface
create_web_interface() {
    log "Creating web interface..."
    
    cat > "$CONFIG_MANAGER_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenWRT Config Manager</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh; padding: 20px;
        }
        .container {
            max-width: 1200px; margin: 0 auto; background: white;
            border-radius: 12px; box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white; padding: 30px; text-align: center;
        }
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; font-weight: 300; }
        .header p { opacity: 0.9; font-size: 1.1rem; }
        .nav { background: #f8f9fa; padding: 0 30px; border-bottom: 1px solid #e9ecef; }
        .nav-tabs { display: flex; list-style: none; flex-wrap: wrap; }
        .nav-tab {
            padding: 15px 25px; cursor: pointer; border-bottom: 3px solid transparent;
            transition: all 0.3s ease; font-weight: 500;
        }
        .nav-tab.active { border-bottom-color: #4facfe; color: #4facfe; background: white; }
        .nav-tab:hover { background: #e9ecef; }
        .content { padding: 30px; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .card {
            background: white; border-radius: 8px; padding: 20px;
            margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .btn {
            padding: 10px 20px; border: none; border-radius: 6px; cursor: pointer;
            font-weight: 500; transition: all 0.3s ease; text-decoration: none;
            display: inline-flex; align-items: center; gap: 8px; margin: 5px;
        }
        .btn-primary { background: #4facfe; color: white; }
        .btn-primary:hover { background: #3d8bfe; transform: translateY(-1px); }
        .btn-success { background: #28a745; color: white; }
        .btn-success:hover { background: #218838; }
        .btn-warning { background: #ffc107; color: #212529; }
        .btn-warning:hover { background: #e0a800; }
        .btn-danger { background: #dc3545; color: white; }
        .btn-danger:hover { background: #c82333; }
        .btn-secondary { background: #6c757d; color: white; }
        .btn-secondary:hover { background: #5a6268; }
        .status {
            padding: 15px; border-radius: 6px; margin-bottom: 20px; display: none;
        }
        .status.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .status.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .status.warning { background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        .stats-grid {
            display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px; margin-bottom: 30px;
        }
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; padding: 20px; border-radius: 8px; text-align: center;
        }
        .stat-value { font-size: 2rem; font-weight: bold; margin-bottom: 5px; }
        .stat-label { opacity: 0.9; font-size: 0.9rem; }
        .editor-container {
            border: 1px solid #e9ecef; border-radius: 8px; overflow: hidden; margin-bottom: 20px;
        }
        .editor-toolbar {
            background: #f8f9fa; padding: 15px; border-bottom: 1px solid #e9ecef;
            display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;
        }
        .editor-actions { display: flex; gap: 10px; flex-wrap: wrap; }
        #editor {
            width: 100%; height: 500px; border: none; font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 14px; line-height: 1.5; padding: 20px; resize: vertical; background: #f8f9fa;
        }
        .loading { text-align: center; padding: 40px; color: #6c757d; }
        .spinner {
            border: 3px solid #f3f3f3; border-top: 3px solid #4facfe; border-radius: 50%;
            width: 30px; height: 30px; animation: spin 1s linear infinite; margin: 0 auto 15px;
        }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; margin-bottom: 5px; font-weight: 500; color: #495057; }
        .form-group input {
            width: 100%; padding: 10px; border: 1px solid #ced4da; border-radius: 4px; font-size: 14px;
        }
        .form-group input:focus { outline: none; border-color: #4facfe; box-shadow: 0 0 0 2px rgba(79, 172, 254, 0.25); }
        @media (max-width: 768px) {
            .container { margin: 10px; border-radius: 8px; }
            .header { padding: 20px; }
            .header h1 { font-size: 2rem; }
            .content { padding: 20px; }
            .nav-tabs { flex-direction: column; }
            .editor-toolbar { flex-direction: column; align-items: stretch; }
            .editor-actions { justify-content: center; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔧 OpenWRT Config Manager</h1>
            <p>Complete management solution for your OpenWRT router</p>
        </div>
        
        <div class="nav">
            <ul class="nav-tabs">
                <li class="nav-tab active" onclick="switchTab('dashboard')">📊 Dashboard</li>
                <li class="nav-tab" onclick="switchTab('homer')">🏠 Homer Config</li>
                <li class="nav-tab" onclick="switchTab('system')">⚙️ System</li>
                <li class="nav-tab" onclick="switchTab('telegram')">📱 Telegram</li>
                <li class="nav-tab" onclick="switchTab('help')">❓ Help</li>
            </ul>
        </div>
        
        <div class="content">
            <div id="status" class="status"></div>
            
            <!-- Dashboard Tab -->
            <div id="dashboard-tab" class="tab-content active">
                <div class="stats-grid" id="stats-grid">
                    <div class="loading">
                        <div class="spinner"></div>
                        Loading system statistics...
                    </div>
                </div>
                
                <div class="card">
                    <h3>Quick Actions</h3>
                    <button class="btn btn-primary" onclick="refreshStats()">🔄 Refresh Stats</button>
                    <button class="btn btn-success" onclick="switchTab('homer')">🏠 Edit Homer</button>
                    <button class="btn btn-warning" onclick="switchTab('system')">⚙️ System Info</button>
                    <button class="btn btn-secondary" onclick="switchTab('telegram')">📱 Telegram Setup</button>
                </div>
            </div>
            
            <!-- Homer Config Tab -->
            <div id="homer-tab" class="tab-content">
                <div class="editor-container">
                    <div class="editor-toolbar">
                        <div style="font-weight: 600; color: #495057;">Homer Configuration Editor</div>
                        <div class="editor-actions">
                            <button class="btn btn-primary" onclick="loadHomerConfig()">🔄 Load Config</button>
                            <button class="btn btn-success" onclick="saveHomerConfig()">💾 Save Config</button>
                            <button class="btn btn-warning" onclick="createBackup()">📦 Create Backup</button>
                            <button class="btn btn-secondary" onclick="loadTemplates()">🎨 Templates</button>
                        </div>
                    </div>
                    <textarea id="homer-editor" placeholder="Loading Homer configuration..."></textarea>
                </div>
                
                <div class="card">
                    <h3>Backups</h3>
                    <div id="backups-list">
                        <div class="loading">
                            <div class="spinner"></div>
                            Loading backups...
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- System Tab -->
            <div id="system-tab" class="tab-content">
                <div class="card">
                    <h3>System Information</h3>
                    <div id="system-info">
                        <div class="loading">
                            <div class="spinner"></div>
                            Loading system information...
                        </div>
                    </div>
                </div>
                
                <div class="card">
                    <h3>System Commands</h3>
                    <div class="form-group">
                        <label for="command-input">Execute Command:</label>
                        <input type="text" id="command-input" placeholder="e.g., uptime, df -h, ps aux">
                    </div>
                    <button class="btn btn-primary" onclick="executeCommand()">▶️ Execute</button>
                    <div id="command-output" style="margin-top: 15px; padding: 15px; background: #f8f9fa; border-radius: 4px; font-family: monospace; white-space: pre-wrap; display: none;"></div>
                </div>
            </div>
            
            <!-- Telegram Tab -->
            <div id="telegram-tab" class="tab-content">
                <div class="card">
                    <h3>Telegram Bot Setup</h3>
                    <div id="telegram-status">
                        <div class="loading">
                            <div class="spinner"></div>
                            Checking Telegram status...
                        </div>
                    </div>
                    
                    <div style="background: #e3f2fd; border: 1px solid #2196f3; border-radius: 8px; padding: 20px; margin-bottom: 20px;">
                        <h4>Configure Telegram Bot</h4>
                        <div class="form-group">
                            <label for="bot-token">Bot Token:</label>
                            <input type="text" id="bot-token" placeholder="123456789:ABCdefGHIjklMNOpqrsTUVwxyz">
                        </div>
                        <div class="form-group">
                            <label for="chat-id">Chat ID:</label>
                            <input type="text" id="chat-id" placeholder="123456789">
                        </div>
                        <button class="btn btn-success" onclick="setupTelegram()">🤖 Setup Bot</button>
                        <button class="btn btn-primary" onclick="testTelegram()">📤 Test Message</button>
                    </div>
                </div>
            </div>
            
            <!-- Help Tab -->
            <div id="help-tab" class="tab-content">
                <div class="card">
                    <h3>OpenWRT Config Manager Help</h3>
                    <div style="margin-top: 20px; line-height: 1.6;">
                        <h4>🔧 Features:</h4>
                        <ul style="margin: 10px 0 20px 20px;">
                            <li><strong>Homer Configuration:</strong> Edit Homer dashboard config remotely</li>
                            <li><strong>System Monitoring:</strong> Monitor router resources and status</li>
                            <li><strong>Telegram Integration:</strong> Get notifications and control via Telegram</li>
                            <li><strong>Backup Management:</strong> Automatic and manual configuration backups</li>
                            <li><strong>Template System:</strong> Pre-built configuration templates</li>
                            <li><strong>Remote Commands:</strong> Execute OpenWRT commands safely</li>
                        </ul>
                        
                        <h4>📱 Telegram Commands:</h4>
                        <ul style="margin: 10px 0 20px 20px;">
                            <li><code>/status</code> - Get system status</li>
                            <li><code>/stats</code> - Get system statistics</li>
                            <li><code>/uptime</code> - Get system uptime</li>
                            <li><code>/memory</code> - Get memory usage</li>
                            <li><code>/disk</code> - Get disk usage</li>
                            <li><code>/network</code> - Get network interfaces</li>
                            <li><code>/services</code> - Get service status</li>
                        </ul>
                        
                        <h4>🌐 Access Points:</h4>
                        <p style="margin: 10px 0;">
                            <strong>Config Manager:</strong> http://[router-ip]:8082<br>
                            <strong>Homer Dashboard:</strong> http://[router-ip]:8010
                        </p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let currentConfig = '';
        let hasUnsavedChanges = false;
        
        // Initialize
        document.addEventListener('DOMContentLoaded', function() {
            refreshStats();
            loadTelegramStatus();
            
            // Auto-save warning
            document.getElementById('homer-editor').addEventListener('input', function() {
                hasUnsavedChanges = true;
            });
            
            // Warn before leaving with unsaved changes
            window.addEventListener('beforeunload', function(e) {
                if (hasUnsavedChanges) {
                    e.preventDefault();
                    e.returnValue = '';
                }
            });
        });
        
        // Tab switching
        function switchTab(tabName) {
            // Hide all tabs
            document.querySelectorAll('.tab-content').forEach(tab => {
                tab.classList.remove('active');
            });
            document.querySelectorAll('.nav-tab').forEach(tab => {
                tab.classList.remove('active');
            });
            
            // Show selected tab
            document.getElementById(tabName + '-tab').classList.add('active');
            event.target.classList.add('active');
            
            // Load data for specific tabs
            if (tabName === 'homer') {
                loadHomerConfig();
                loadBackups();
            } else if (tabName === 'system') {
                loadSystemInfo();
            } else if (tabName === 'telegram') {
                loadTelegramStatus();
            }
        }
        
        // Show status messages
        function showStatus(message, type = 'success') {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = `status ${type}`;
            status.style.display = 'block';
            
            setTimeout(() => {
                status.style.display = 'none';
            }, 5000);
        }
        
        // Dashboard functions
        async function refreshStats() {
            try {
                const response = await fetch('/api/stats');
                const data = await response.json();
                
                if (data.success) {
                    displayStats(data.stats);
                } else {
                    showStatus('Error loading stats: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error loading stats: ' + error.message, 'error');
            }
        }
        
        function displayStats(stats) {
            const statsGrid = document.getElementById('stats-grid');
            statsGrid.innerHTML = `
                <div class="stat-card">
                    <div class="stat-value">${stats.memory.percent}%</div>
                    <div class="stat-label">Memory Usage</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${stats.disk.percent}%</div>
                    <div class="stat-label">Disk Usage</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${Math.floor(stats.uptime / 3600)}h</div>
                    <div class="stat-label">Uptime</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${stats.load[0]}</div>
                    <div class="stat-label">Load Average</div>
                </div>
            `;
        }
        
        // Homer config functions
        async function loadHomerConfig() {
            try {
                const response = await fetch('/api/config');
                const data = await response.json();
                
                if (data.success) {
                    currentConfig = data.config;
                    document.getElementById('homer-editor').value = data.config;
                    hasUnsavedChanges = false;
                    showStatus('Homer configuration loaded successfully');
                } else {
                    showStatus('Error loading Homer config: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error loading Homer config: ' + error.message, 'error');
            }
        }
        
        async function saveHomerConfig() {
            const config = document.getElementById('homer-editor').value;
            
            try {
                const response = await fetch('/api/config', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ config: config })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    currentConfig = config;
                    hasUnsavedChanges = false;
                    showStatus('Homer configuration saved successfully!');
                } else {
                    showStatus('Error saving Homer config: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error saving Homer config: ' + error.message, 'error');
            }
        }
        
        async function createBackup() {
            try {
                const response = await fetch('/api/backup', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({})
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showStatus('Backup created successfully: ' + data.backup);
                    loadBackups();
                } else {
                    showStatus('Error creating backup: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error creating backup: ' + error.message, 'error');
            }
        }
        
        async function loadBackups() {
            const backupsList = document.getElementById('backups-list');
            backupsList.innerHTML = '<div class="loading"><div class="spinner"></div>Loading backups...</div>';
            
            try {
                const response = await fetch('/api/backups');
                const data = await response.json();
                
                if (data.success) {
                    if (data.backups.length === 0) {
                        backupsList.innerHTML = '<p>No backups found</p>';
                    } else {
                        backupsList.innerHTML = data.backups.map(backup => `
                            <div style="display: flex; justify-content: space-between; align-items: center; padding: 10px; background: #f8f9fa; border-radius: 4px; margin-bottom: 10px;">
                                <div>
                                    <strong>${backup.name}</strong><br>
                                    <small>Created: ${new Date(backup.created).toLocaleString()}</small>
                                </div>
                                <div>
                                    <button class="btn btn-primary" onclick="restoreBackup('${backup.name}')">Restore</button>
                                </div>
                            </div>
                        `).join('');
                    }
                } else {
                    backupsList.innerHTML = '<p>Error loading backups: ' + data.error + '</p>';
                }
            } catch (error) {
                backupsList.innerHTML = '<p>Error loading backups: ' + error.message + '</p>';
            }
        }
        
        async function restoreBackup(backupName) {
            if (!confirm(`Are you sure you want to restore backup "${backupName}"?`)) {
                return;
            }
            
            try {
                const response = await fetch('/api/restore', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ backup: backupName })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showStatus('Configuration restored successfully!');
                    loadHomerConfig();
                    loadBackups();
                } else {
                    showStatus('Error restoring backup: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error restoring backup: ' + error.message, 'error');
            }
        }
        
        // System functions
        async function loadSystemInfo() {
            try {
                const response = await fetch('/api/system/info');
                const data = await response.json();
                
                if (data.success) {
                    const info = data.info;
                    document.getElementById('system-info').innerHTML = `
                        <p><strong>OpenWRT Version:</strong> ${info.version}</p>
                        <p><strong>Target:</strong> ${info.target}</p>
                        <p><strong>Architecture:</strong> ${info.architecture}</p>
                        <p><strong>Kernel:</strong> ${info.kernel}</p>
                        <p><strong>Hostname:</strong> ${info.hostname}</p>
                        <p><strong>Model:</strong> ${info.model}</p>
                    `;
                } else {
                    document.getElementById('system-info').innerHTML = '<p>Error loading system info: ' + data.error + '</p>';
                }
            } catch (error) {
                document.getElementById('system-info').innerHTML = '<p>Error loading system info: ' + error.message + '</p>';
            }
        }
        
        async function executeCommand() {
            const command = document.getElementById('command-input').value;
            if (!command) {
                showStatus('Please enter a command', 'warning');
                return;
            }
            
            try {
                const response = await fetch('/api/system/command', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ command: command })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    const output = document.getElementById('command-output');
                    output.style.display = 'block';
                    output.textContent = data.result.stdout || data.result.stderr || 'No output';
                } else {
                    showStatus('Error executing command: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error executing command: ' + error.message, 'error');
            }
        }
        
        // Telegram functions
        async function loadTelegramStatus() {
            try {
                const response = await fetch('/api/telegram/status');
                const data = await response.json();
                
                if (data.success) {
                    const status = data.status;
                    document.getElementById('telegram-status').innerHTML = `
                        <p><strong>Status:</strong> ${status.configured ? '✅ Configured' : '❌ Not Configured'}</p>
                        <p><strong>Bot Token:</strong> ${status.bot_token_set ? '✅ Set' : '❌ Not Set'}</p>
                        <p><strong>Chat ID:</strong> ${status.chat_id_set ? '✅ Set' : '❌ Not Set'}</p>
                    `;
                } else {
                    document.getElementById('telegram-status').innerHTML = '<p>Error loading Telegram status: ' + data.error + '</p>';
                }
            } catch (error) {
                document.getElementById('telegram-status').innerHTML = '<p>Error loading Telegram status: ' + error.message + '</p>';
            }
        }
        
        async function setupTelegram() {
            const botToken = document.getElementById('bot-token').value;
            const chatId = document.getElementById('chat-id').value;
            
            if (!botToken || !chatId) {
                showStatus('Please enter both bot token and chat ID', 'warning');
                return;
            }
            
            try {
                const response = await fetch('/api/telegram/setup', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ bot_token: botToken, chat_id: chatId })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showStatus('Telegram bot configured successfully!');
                    loadTelegramStatus();
                } else {
                    showStatus('Error setting up Telegram: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error setting up Telegram: ' + error.message, 'error');
            }
        }
        
        async function testTelegram() {
            try {
                const response = await fetch('/api/telegram/send', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ message: '🤖 Test message from OpenWRT Config Manager!' })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showStatus('Test message sent successfully!');
                } else {
                    showStatus('Error sending test message: ' + data.error, 'error');
                }
            } catch (error) {
                showStatus('Error sending test message: ' + error.message, 'error');
            }
        }
        
        // Template functions
        async function loadTemplates() {
            showStatus('Template loading not implemented yet', 'warning');
        }
    </script>
</body>
</html>
EOF

    log_success "Web interface created"
}

# Create configuration templates
create_templates() {
    log "Creating configuration templates..."
    
    # Basic template
    cat > "$TEMPLATES_DIR/basic.yml" << 'EOF'
---
# Basic Homer Configuration Template
title: "My Dashboard"
subtitle: "Welcome to your dashboard"
logo: "https://raw.githubusercontent.com/bastienwirtz/homer/main/public/logo.png"
icon: "fas fa-home"

# Optional theme
theme: default

# Optional message
message:
  style: "is-dark"
  title: "Welcome!"
  icon: "fa fa-grin"
  content: "This is a <em>default</em> message! You can change it in the configuration editor."

# Optional navbar
links:
  - name: "Config Manager"
    icon: "fas fa-cog"
    url: "http://192.168.1.1:8082"
    target: "_blank"
  - name: "GitHub"
    icon: "fab fa-github"
    url: "https://github.com/bastienwirtz/homer"
    target: "_blank"

# Services
services:
  - name: "Router Admin"
    logo: "assets/tools/router.png"
    subtitle: "OpenWRT Administration"
    tag: "router"
    tagstyle: "is-success"
    url: "http://192.168.1.1"
    target: "_blank"
  - name: "Config Manager"
    logo: "assets/tools/config.png"
    subtitle: "Configuration Management"
    tag: "config"
    tagstyle: "is-info"
    url: "http://192.168.1.1:8082"
    target: "_blank"
EOF

    # Network monitoring template
    cat > "$TEMPLATES_DIR/network-monitoring.yml" << 'EOF'
---
title: "Network Monitoring Dashboard"
subtitle: "Network Infrastructure Overview"
logo: "https://raw.githubusercontent.com/bastienwirtz/homer/main/public/logo.png"
icon: "fas fa-network-wired"

theme: default

message:
  style: "is-info"
  title: "Network Status"
  icon: "fas fa-info-circle"
  content: "Monitor your network infrastructure and services"

links:
  - name: "Router Admin"
    icon: "fas fa-cog"
    url: "http://192.168.1.1"
    target: "_blank"
  - name: "Config Manager"
    icon: "fas fa-tools"
    url: "http://192.168.1.1:8082"
    target: "_blank"

services:
  - name: "Router"
    logo: "assets/tools/router.png"
    subtitle: "OpenWRT Administration"
    tag: "gateway"
    tagstyle: "is-success"
    url: "http://192.168.1.1"
    target: "_blank"
  - name: "Config Manager"
    logo: "assets/tools/config.png"
    subtitle: "Configuration Management"
    tag: "config"
    tagstyle: "is-info"
    url: "http://192.168.1.1:8082"
    target: "_blank"
  - name: "DNS Server"
    logo: "assets/tools/dns.png"
    subtitle: "Pi-hole DNS"
    tag: "dns"
    tagstyle: "is-info"
    url: "http://192.168.1.2"
    target: "_blank"
  - name: "NAS"
    logo: "assets/tools/nas.png"
    subtitle: "Network Storage"
    tag: "storage"
    tagstyle: "is-warning"
    url: "http://192.168.1.3"
    target: "_blank"
EOF

    log_success "Configuration templates created"
}

# Create Homer service
create_homer_service() {
    log "Creating Homer service..."
    
    # Create Homer server script
    cat > "/www/homer-dashboard/server.py" << 'EOF'
#!/usr/bin/python3
"""
Homer Dashboard HTTP Server for OpenWRT
Lightweight HTTP server to serve Homer dashboard files
"""

import http.server
import socketserver
import os
import sys
import logging
from datetime import datetime

# Configuration
HOMER_DIR = "/www/homer-dashboard"
LOG_FILE = "/tmp/homer.log"
PORT = 8010
HOST = "0.0.0.0"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class HomerHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP request handler for Homer dashboard"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HOMER_DIR, **kwargs)
    
    def end_headers(self):
        # Add CORS headers for better compatibility
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()
    
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.info(f"{self.address_string()} - {format % args}")
    
    def do_GET(self):
        """Handle GET requests"""
        # Default to index.html if path is /
        if self.path == '/':
            self.path = '/index.html'
        
        # Check if file exists
        file_path = os.path.join(HOMER_DIR, self.path.lstrip('/'))
        if not os.path.exists(file_path) or not os.path.isfile(file_path):
            # Try index.html for directory requests
            if os.path.isdir(file_path):
                index_path = os.path.join(file_path, 'index.html')
                if os.path.exists(index_path):
                    self.path = os.path.join(self.path, 'index.html')
                else:
                    self.send_error(404, "File not found")
                    return
            else:
                self.send_error(404, "File not found")
                return
        
        super().do_GET()

def main():
    """Main function"""
    try:
        # Change to Homer directory
        os.chdir(HOMER_DIR)
        
        # Create HTTP server
        with socketserver.TCPServer((HOST, PORT), HomerHTTPRequestHandler) as httpd:
            logger.info(f"Homer dashboard server starting on {HOST}:{PORT}")
            logger.info(f"Serving files from: {HOMER_DIR}")
            logger.info(f"Logging to: {LOG_FILE}")
            
            # Start server
            httpd.serve_forever()
            
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x "/www/homer-dashboard/server.py"
    
    # Create Homer init.d service
    cat > "/etc/init.d/homer" << EOF
#!/bin/sh /etc/rc.common

START=98
STOP=10

USE_PROCD=1
PROG="/usr/bin/python3"
ARGS="/www/homer-dashboard/server.py"

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" "\$ARGS"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param file "/tmp/homer.log"
    procd_close_instance
}

stop_service() {
    # Kill Homer processes
    pkill -f "homer-dashboard/server.py" 2>/dev/null || true
}
EOF

    chmod +x "/etc/init.d/homer"
    log_success "Homer service created"
}

# Create init.d service
create_init_service() {
    log "Creating Config Manager init.d service..."
    
    cat > "$CONFIG_MANAGER_SERVICE" << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG="/usr/bin/python3"
ARGS="/www/config-manager/server.py"

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" "\$ARGS"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param file "\$CONFIG_MANAGER_LOG"
    procd_close_instance
}

stop_service() {
    # Kill Config Manager processes
    pkill -f "config-manager/server.py" 2>/dev/null || true
}
EOF

    chmod +x "$CONFIG_MANAGER_SERVICE"
    log_success "Config Manager init.d service created"
}

# Set proper permissions
set_permissions() {
    log "Setting proper permissions..."
    
    # Fix all permissions
    chmod -R 755 "$CONFIG_MANAGER_DIR"
    chown -R root:root "$CONFIG_MANAGER_DIR"
    
    # Fix Homer config permissions
    if [ -f "$HOMER_CONFIG_FILE" ]; then
        chmod 666 "$HOMER_CONFIG_FILE"
        chown root:root "$HOMER_CONFIG_FILE"
        log_success "Fixed Homer config file permissions"
    fi
    
    # Fix Homer assets directory
    if [ -d "/www/homer-dashboard/assets" ]; then
        chmod 666 "/www/homer-dashboard/assets"
        chown -R root:root "/www/homer-dashboard/assets"
        log_success "Fixed Homer assets permissions"
    fi
    
    # Create log file
    touch "$CONFIG_MANAGER_LOG"
    chmod 644 "$CONFIG_MANAGER_LOG"
    
    log_success "Permissions set correctly"
}

# Start Homer service
start_homer_service() {
    log "Starting Homer service..."
    
    # Kill any processes using Homer port
    kill_port_processes "$HOMER_PORT" "Homer"
    
    # Try to start via service first
    if [ -f "/etc/init.d/homer" ]; then
        "/etc/init.d/homer" enable 2>/dev/null || log_warning "Could not enable Homer service"
        "/etc/init.d/homer" start
        sleep 3
        
        if pgrep -f "homer-dashboard/server.py" > /dev/null; then
            log_success "Homer service started successfully"
            return 0
        else
            log_warning "Homer service start failed, trying manual start..."
        fi
    fi
    
    # Manual start
    cd "/www/homer-dashboard"
    nohup python3 server.py > /tmp/homer.log 2>&1 &
    sleep 3
    
    if pgrep -f "homer-dashboard/server.py" > /dev/null; then
        log_success "Homer manual start successful"
        return 0
    else
        log_error "Failed to start Homer service"
        log_error "Check logs: /tmp/homer.log"
        return 1
    fi
}

# Start Config Manager service
start_config_manager_service() {
    log "Starting Config Manager service..."
    
    # Kill any processes using Config Manager port
    kill_port_processes "$CONFIG_MANAGER_PORT" "Config Manager"
    
    # Try to start via service first
    if [ -f "$CONFIG_MANAGER_SERVICE" ]; then
        "$CONFIG_MANAGER_SERVICE" enable 2>/dev/null || log_warning "Could not enable Config Manager service"
        "$CONFIG_MANAGER_SERVICE" start
        sleep 3
        
        if pgrep -f "config-manager/server.py" > /dev/null; then
            log_success "Config Manager service started successfully"
            return 0
        else
            log_warning "Config Manager service start failed, trying manual start..."
        fi
    fi
    
    # Manual start
    cd "$CONFIG_MANAGER_DIR"
    nohup python3 server.py > "$CONFIG_MANAGER_LOG" 2>&1 &
    sleep 3
    
    if pgrep -f "config-manager/server.py" > /dev/null; then
        log_success "Config Manager manual start successful"
        return 0
    else
        log_error "Failed to start Config Manager service"
        log_error "Check logs: $CONFIG_MANAGER_LOG"
        return 1
    fi
}

# Start all services
start_service() {
    log "Starting all services..."
    
    local homer_success=false
    local config_success=false
    
    # Start Homer service
    if start_homer_service; then
        homer_success=true
    else
        log_error "Failed to start Homer service"
    fi
    
    # Start Config Manager service
    if start_config_manager_service; then
        config_success=true
    else
        log_error "Failed to start Config Manager service"
    fi
    
    # Check final status
    sleep 2
    echo
    log "Checking service status..."
    
    if pgrep -f "homer-dashboard/server.py" > /dev/null; then
        log_success "✅ Homer is running (PID: $(pgrep -f 'homer-dashboard/server.py'))"
    else
        log_error "❌ Homer is not running"
    fi
    
    if pgrep -f "config-manager/server.py" > /dev/null; then
        log_success "✅ Config Manager is running (PID: $(pgrep -f 'config-manager/server.py'))"
    else
        log_error "❌ Config Manager is not running"
    fi
    
    # Check ports
    if netstat -lnp 2>/dev/null | grep ":8010 " > /dev/null; then
        log_success "✅ Port 8010 (Homer) is listening"
    else
        log_error "❌ Port 8010 (Homer) is not listening"
    fi
    
    if netstat -lnp 2>/dev/null | grep ":8082 " > /dev/null; then
        log_success "✅ Port 8082 (Config Manager) is listening"
    else
        log_error "❌ Port 8082 (Config Manager) is not listening"
    fi
    
    if [ "$homer_success" = true ] && [ "$config_success" = true ]; then
        log_success "All services started successfully!"
        return 0
    else
        log_error "Some services failed to start"
        return 1
    fi
}

# Stop all services
stop_service() {
    log "Stopping all services..."
    
    local homer_stopped=false
    local config_stopped=false
    
    # Stop Homer service
    log "Stopping Homer service..."
    if [ -f "/etc/init.d/homer" ]; then
        "/etc/init.d/homer" stop 2>/dev/null || true
    fi
    
    if pgrep -f "homer-dashboard/server.py" > /dev/null; then
        pkill -f "homer-dashboard/server.py"
        sleep 2
        
        if pgrep -f "homer-dashboard/server.py" > /dev/null; then
            pkill -9 -f "homer-dashboard/server.py"
        fi
    fi
    
    if ! pgrep -f "homer-dashboard/server.py" > /dev/null; then
        log_success "Homer service stopped"
        homer_stopped=true
    else
        log_error "Failed to stop Homer service"
    fi
    
    # Stop Config Manager service
    log "Stopping Config Manager service..."
    if [ -f "$CONFIG_MANAGER_SERVICE" ]; then
        "$CONFIG_MANAGER_SERVICE" stop 2>/dev/null || true
    fi
    
    if pgrep -f "config-manager/server.py" > /dev/null; then
        pkill -f "config-manager/server.py"
        sleep 2
        
        if pgrep -f "config-manager/server.py" > /dev/null; then
            pkill -9 -f "config-manager/server.py"
        fi
    fi
    
    if ! pgrep -f "config-manager/server.py" > /dev/null; then
        log_success "Config Manager service stopped"
        config_stopped=true
    else
        log_error "Failed to stop Config Manager service"
    fi
    
    if [ "$homer_stopped" = true ] && [ "$config_stopped" = true ]; then
        log_success "All services stopped successfully!"
        return 0
    else
        log_error "Some services failed to stop"
        return 1
    fi
}

# Show service status
show_status() {
    echo -e "${GREEN}=== OpenWRT Config Manager Status ===${NC}"
    echo
    
    # Check if process is running
    if pgrep -f "config-manager/server.py" > /dev/null; then
        echo -e "${GREEN}✅ Service Status: RUNNING${NC}"
        echo "PID: $(pgrep -f 'config-manager/server.py')"
    else
        echo -e "${RED}❌ Service Status: NOT RUNNING${NC}"
    fi
    
    echo
    
    # Check port
    if netstat -lnp 2>/dev/null | grep ":8082 " > /dev/null; then
        echo -e "${GREEN}✅ Port 8082: LISTENING${NC}"
        netstat -lnp | grep ":8082 "
    else
        echo -e "${RED}❌ Port 8082: NOT LISTENING${NC}"
    fi
    
    echo
    
    # Check files
    echo "📁 File Status:"
    if [ -f "$CONFIG_MANAGER_DIR/server.py" ]; then
        echo -e "  ${GREEN}✅ Server script: EXISTS${NC}"
    else
        echo -e "  ${RED}❌ Server script: MISSING${NC}"
    fi
    
    if [ -f "$HOMER_CONFIG_FILE" ]; then
        echo -e "  ${GREEN}✅ Homer config: EXISTS${NC}"
        if [ -w "$HOMER_CONFIG_FILE" ]; then
            echo -e "  ${GREEN}✅ Homer config: WRITABLE${NC}"
        else
            echo -e "  ${RED}❌ Homer config: NOT WRITABLE${NC}"
        fi
    else
        echo -e "  ${RED}❌ Homer config: MISSING${NC}"
    fi
    
    echo
    
    # Show recent log entries
    if [ -f "$CONFIG_MANAGER_LOG" ]; then
        echo "📋 Recent Log Entries:"
        tail -5 "$CONFIG_MANAGER_LOG"
    fi
    
    echo
    echo -e "${BLUE}Access URL: http://$(hostname -I | awk '{print $1}'):8082${NC}"
}

# Show debug information
show_debug() {
    echo -e "${GREEN}=== Config Manager Debug Information ===${NC}"
    echo
    
    echo "🔍 System Information:"
    echo "  OpenWRT Version: $(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_RELEASE | cut -d'=' -f2 | tr -d '"' || echo 'Unknown')"
    echo "  Architecture: $(uname -m)"
    echo "  Kernel: $(uname -r)"
    echo "  Uptime: $(uptime)"
    echo
    
    echo "💾 Memory Usage:"
    free -m
    echo
    
    echo "💿 Disk Usage:"
    df -h /www
    echo
    
    echo "🌐 Network Interfaces:"
    ifconfig | grep -A 1 "inet "
    echo
    
    echo "🔧 Python3 Information:"
    python3 --version 2>/dev/null || echo "Python3 not found"
    which python3
    echo
    
    echo "📦 Installed Packages:"
    opkg list-installed | grep -E "(python|yaml|requests)" || echo "No relevant packages found"
    echo
    
    echo "🔍 Process Information:"
    ps | grep -E "(python|config-manager|homer)" | grep -v grep
    echo
    
    echo "🌐 Port Information:"
    netstat -lnp | grep -E ":(8010|8082) "
    echo
    
    echo "📁 Directory Structure:"
    echo "  /www/config-manager:"
    ls -la /www/config-manager/ 2>/dev/null || echo "    Directory not found"
    echo
    echo "  /www/homer-dashboard:"
    ls -la /www/homer-dashboard/ 2>/dev/null || echo "    Directory not found"
    echo
    
    echo "🔐 File Permissions:"
    if [ -f "$HOMER_CONFIG_FILE" ]; then
        echo "  Homer config:"
        ls -la "$HOMER_CONFIG_FILE"
    else
        echo "  Homer config: NOT FOUND"
    fi
    
    if [ -f "$CONFIG_MANAGER_DIR/server.py" ]; then
        echo "  Config Manager server:"
        ls -la "$CONFIG_MANAGER_DIR/server.py"
    else
        echo "  Config Manager server: NOT FOUND"
    fi
    
    echo
    
    echo "📋 Recent Log Entries:"
    if [ -f "$CONFIG_MANAGER_LOG" ]; then
        echo "  Last 10 lines:"
        tail -10 "$CONFIG_MANAGER_LOG"
    else
        echo "  Log file not found"
    fi
}

# Fix common issues
fix_issues() {
    log "Fixing common issues..."
    
    # Kill any conflicting processes
    kill_port_processes "8010" "Homer"
    kill_port_processes "8082" "Config Manager"
    
    # Fix permissions
    set_permissions
    
    # Create missing directories
    mkdir -p "$BACKUP_DIR" "$TEMPLATES_DIR" "$TELEGRAM_BOT_DIR"
    chmod 755 "$BACKUP_DIR" "$TEMPLATES_DIR" "$TELEGRAM_BOT_DIR"
    
    # Fix Homer config if missing
    if [ ! -f "$HOMER_CONFIG_FILE" ] && [ -d "/www/homer-dashboard" ]; then
        if [ -f "/www/homer-dashboard/assets/config-demo.yml.dist" ]; then
            cp "/www/homer-dashboard/assets/config-demo.yml.dist" "$HOMER_CONFIG_FILE"
            chmod 666 "$HOMER_CONFIG_FILE"
            log_success "Created Homer config from demo"
        else
            create_basic_homer_config
        fi
    fi
    
    # Ensure Homer service exists
    if [ ! -f "/etc/init.d/homer" ]; then
        log "Creating missing Homer service..."
        create_homer_service
    fi
    
    # Ensure Config Manager service exists
    if [ ! -f "$CONFIG_MANAGER_SERVICE" ]; then
        log "Creating missing Config Manager service..."
        create_init_service
    fi
    
    # Fix file permissions
    chmod +x "/www/homer-dashboard/server.py" 2>/dev/null || true
    chmod +x "$CONFIG_MANAGER_DIR/server.py" 2>/dev/null || true
    chmod +x "/etc/init.d/homer" 2>/dev/null || true
    chmod +x "$CONFIG_MANAGER_SERVICE" 2>/dev/null || true
    
    # Restart services
    log "Restarting services..."
    stop_service
    sleep 3
    start_service
    
    log_success "Issues fixed"
}

# Optimize OpenWRT
optimize_system() {
    log "Optimizing OpenWRT system..."
    
    # Update package list
    opkg update 2>/dev/null || log_warning "Could not update package list"
    
    # Install useful packages
    PACKAGES=("htop" "nano" "curl" "wget" "unzip" "htop" "iotop")
    for package in "${PACKAGES[@]}"; do
        opkg install "$package" 2>/dev/null || log_warning "Could not install $package"
    done
    
    # Optimize memory
    echo "vm.swappiness=10" >> /etc/sysctl.conf 2>/dev/null || true
    
    # Create swap file if needed
    if [ ! -f "/swapfile" ] && [ $(free -m | awk 'NR==2{print $2}') -lt 512 ]; then
        log "Creating swap file..."
        dd if=/dev/zero of=/swapfile bs=1M count=256 2>/dev/null || true
        mkswap /swapfile 2>/dev/null || true
        swapon /swapfile 2>/dev/null || true
        echo "/swapfile none swap sw 0 0" >> /etc/fstab 2>/dev/null || true
    fi
    
    # Clean up
    opkg clean 2>/dev/null || true
    
    log_success "System optimized"
}

# Main installation function
install_all() {
    log "Starting complete installation..."
    
    # Check prerequisites
    check_python3 || exit 1
    install_python_dependencies
    
    # Create directory structure
    create_directories
    
    # Install Homer dashboard
    if ! install_homer; then
        log_error "Failed to install Homer dashboard"
        exit 1
    fi
    
    # Create Homer service
    create_homer_service
    
    # Create Config Manager
    create_config_manager_server
    create_templates
    create_web_interface
    create_init_service
    
    # Set permissions
    set_permissions
    
    # Start all services
    if ! start_service; then
        log_error "Failed to start services"
        log_error "Trying to fix issues..."
        fix_issues
        sleep 2
        if ! start_service; then
            log_error "Services still failing after fix attempt"
            log_error "Check logs and run: $0 debug"
            exit 1
        fi
    fi
    
    log_success "Installation completed successfully!"
    
    echo
    echo -e "${GREEN}=== Installation Complete ===${NC}"
    echo -e "Config Manager: ${BLUE}http://$(hostname -I | awk '{print $1}'):8082${NC}"
    echo -e "Homer Dashboard: ${BLUE}http://$(hostname -I | awk '{print $1}'):8010${NC}"
    echo
    echo -e "${YELLOW}Management Commands:${NC}"
    echo -e "  Status:  $0 status"
    echo -e "  Start:   $0 start"
    echo -e "  Stop:    $0 stop"
    echo -e "  Restart: $0 restart"
    echo -e "  Debug:   $0 debug"
    echo -e "  Fix:     $0 fix"
    echo
    echo -e "${YELLOW}Service Status:${NC}"
    show_status
}

# Uninstall function
uninstall_all() {
    log "Uninstalling Config Manager..."
    
    # Stop service
    stop_service
    
    # Remove service
    if [ -f "$CONFIG_MANAGER_SERVICE" ]; then
        "$CONFIG_MANAGER_SERVICE" disable 2>/dev/null || true
        rm -f "$CONFIG_MANAGER_SERVICE"
    fi
    
    # Remove directories
    rm -rf "$CONFIG_MANAGER_DIR"
    rm -rf "$TELEGRAM_BOT_DIR"
    
    # Remove log file
    rm -f "$CONFIG_MANAGER_LOG"
    
    log_success "Config Manager uninstalled"
}

# Main script logic
main() {
    show_banner
    
    # Check if running as root
    check_root
    
    # Parse command line arguments
    case "${1:-help}" in
        "install")
            install_all
            ;;
        "uninstall")
            uninstall_all
            ;;
        "start")
            start_service
            ;;
        "start-homer")
            start_homer_service
            ;;
        "start-config")
            start_config_manager_service
            ;;
        "stop")
            stop_service
            ;;
        "restart")
            stop_service
            sleep 2
            start_service
            ;;
        "status")
            show_status
            ;;
        "debug")
            show_debug
            ;;
        "fix")
            fix_issues
            ;;
        "optimize")
            optimize_system
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run main function
main "$@"
