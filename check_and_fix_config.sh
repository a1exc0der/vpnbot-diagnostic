#!/bin/bash

# =============================================================================
# 🔧 Ultima 3.1.0 - Проверка и Исправление Конфигурации
# =============================================================================
# Автор: alexcoder (@ultima_supbot)
# Версия скрипта: 1.0
# Описание: Интерактивный скрипт для проверки и исправления конфигурации системы
# Контакты: https://ultimabots.network | Telegram: @ultima_supbot
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Этот скрипт должен запускаться от root"
        exit 1
    fi
}

detect_project_root() {
    if [ -f "/root/vpnbot-v3/.env" ]; then
        PROJECT_ROOT="/root/vpnbot-v3"
    elif [ -f "$(dirname "$0")/../../.env" ]; then
        PROJECT_ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
    else
        log_error "Не найден .env файл проекта"
        exit 1
    fi
    ENV_FILE="${PROJECT_ROOT}/.env"
    log_info "Проект найден: $PROJECT_ROOT"
}

get_domain() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Файл .env не найден: $ENV_FILE"
        return 1
    fi
    
    DOMAIN=$(grep -E '^DOMAIN=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d ' ')
    
    if [ -z "$DOMAIN" ]; then
        log_error "DOMAIN не найден в .env файле"
        return 1
    fi
    
    MAIN_DOMAIN="${DOMAIN#panel.}"
    MAIN_DOMAIN="${MAIN_DOMAIN#sub.}"
    
    if [ "$DOMAIN" = "$MAIN_DOMAIN" ]; then
        PANEL_DOMAIN="panel.${DOMAIN}"
        SUB_DOMAIN="sub.${DOMAIN}"
    else
        PANEL_DOMAIN="$DOMAIN"
        SUB_DOMAIN="sub.${MAIN_DOMAIN}"
    fi
    
    log_info "Основной домен: $MAIN_DOMAIN"
    log_info "Panel домен: $PANEL_DOMAIN"
    log_info "Sub домен: $SUB_DOMAIN"
    
    return 0
}

check_webhook_snippet() {
    log_step "Проверка сниппета webhook"
    
    SNIPPET_FILE="/etc/nginx/snippets/vpnbot_webhooks.conf"
    
    if [ ! -f "$SNIPPET_FILE" ]; then
        log_warning "Сниппет webhook не найден: $SNIPPET_FILE"
        WEBHOOK_SNIPPET_MISSING=true
        return 1
    fi
    
    if ! grep -q "location /webhooks/" "$SNIPPET_FILE" 2>/dev/null; then
        log_warning "Сниппет найден, но содержимое некорректно"
        WEBHOOK_SNIPPET_INVALID=true
        return 1
    fi
    
    log_success "Сниппет webhook найден и корректен"
    WEBHOOK_SNIPPET_OK=true
    return 0
}

create_webhook_snippet() {
    log_step "Создание сниппета webhook"
    
    mkdir -p /etc/nginx/snippets
    
    cat > /etc/nginx/snippets/vpnbot_webhooks.conf << 'EOF'
location /webhooks/ {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 30s;
    proxy_send_timeout 30s;
    proxy_read_timeout 30s;
}
EOF
    
    log_success "Сниппет создан: /etc/nginx/snippets/vpnbot_webhooks.conf"
}

certificate_covers_domain() {
    local cert_file="$1"
    local domain="$2"
    
    if [ ! -f "$cert_file" ]; then
        return 1
    fi
    
    local san_domains=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | grep -oP 'DNS:\K[^, ]+' || echo "")
    
    local cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p' || echo "")
    
    if echo "$san_domains $cn" | grep -q "\b${domain}\b"; then
        return 0
    fi
    
    return 1
}

check_ssl_certificates() {
    log_step "Проверка SSL сертификатов"
    
    SSL_ISSUES=()
    
    local main_cert="/etc/letsencrypt/live/${MAIN_DOMAIN}/fullchain.pem"
    local panel_cert="/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
    local sub_cert="/etc/letsencrypt/live/${SUB_DOMAIN}/fullchain.pem"
    
    local found_cert=""
    local found_cert_name=""
    
    if [ -f "$main_cert" ]; then
        found_cert="$main_cert"
        found_cert_name="$MAIN_DOMAIN"
    elif [ -f "$panel_cert" ]; then
        found_cert="$panel_cert"
        found_cert_name="$PANEL_DOMAIN"
    elif [ -f "$sub_cert" ]; then
        found_cert="$sub_cert"
        found_cert_name="$SUB_DOMAIN"
    fi
    
    if [ -z "$found_cert" ]; then
        log_warning "SSL сертификаты не найдены ни для одного домена"
        SSL_ISSUES+=("main:$MAIN_DOMAIN")
        SSL_ISSUES+=("panel:$PANEL_DOMAIN")
        SSL_ISSUES+=("sub:$SUB_DOMAIN")
        SSL_CERTS_OK=false
        return 1
    fi
    
    local expiry=$(openssl x509 -enddate -noout -in "$found_cert" 2>/dev/null | cut -d= -f2)
    log_info "Найден SSL сертификат: $found_cert_name (до: $expiry)"
    
    if certificate_covers_domain "$found_cert" "$MAIN_DOMAIN"; then
        log_success "SSL сертификат покрывает основной домен: $MAIN_DOMAIN"
    else
        log_warning "SSL сертификат НЕ покрывает основной домен: $MAIN_DOMAIN"
        SSL_ISSUES+=("main:$MAIN_DOMAIN")
    fi
    
    if certificate_covers_domain "$found_cert" "$PANEL_DOMAIN"; then
        log_success "SSL сертификат покрывает panel домен: $PANEL_DOMAIN"
    else
        log_warning "SSL сертификат НЕ покрывает panel домен: $PANEL_DOMAIN"
        SSL_ISSUES+=("panel:$PANEL_DOMAIN")
    fi
    
    if certificate_covers_domain "$found_cert" "$SUB_DOMAIN"; then
        log_success "SSL сертификат покрывает sub домен: $SUB_DOMAIN"
    else
        log_warning "SSL сертификат НЕ покрывает sub домен: $SUB_DOMAIN"
        SSL_ISSUES+=("sub:$SUB_DOMAIN")
    fi
    
    local san_domains=$(openssl x509 -in "$found_cert" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | grep -oP 'DNS:\K[^, ]+' | tr '\n' ' ' || echo "")
    local cn=$(openssl x509 -in "$found_cert" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p' || echo "")
    
    if [ -n "$san_domains" ] || [ -n "$cn" ]; then
        log_info "Домены в сертификате: $cn $san_domains"
    fi
    
    if [ ${#SSL_ISSUES[@]} -eq 0 ]; then
        SSL_CERTS_OK=true
        return 0
    else
        SSL_CERTS_OK=false
        return 1
    fi
}

get_ssl_certificate() {
    local domain_type="$1"
    local domain="$2"
    
    log_step "Получение SSL сертификата для $domain"
    
    systemctl stop nginx 2>/dev/null || true
    
    local certbot_domains="-d $domain"
    
    if [ "$domain_type" = "main" ]; then
        certbot_domains="-d ${MAIN_DOMAIN} -d ${PANEL_DOMAIN} -d ${SUB_DOMAIN}"
        log_info "Получаем сертификат для всех доменов: ${MAIN_DOMAIN}, ${PANEL_DOMAIN}, ${SUB_DOMAIN}"
    fi
    
    if certbot certonly --standalone $certbot_domains --non-interactive --agree-tos --email "admin@${MAIN_DOMAIN}" 2>/dev/null; then
        log_success "SSL сертификат для $domain получен"
        systemctl start nginx 2>/dev/null || true
        return 0
    else
        log_error "Не удалось получить SSL сертификат для $domain"
        systemctl start nginx 2>/dev/null || true
        return 1
    fi
}

check_nginx_configs() {
    log_step "Проверка конфигов Nginx"
    
    NGINX_ISSUES=()
    
    MAIN_CONFIG="/etc/nginx/sites-available/${MAIN_DOMAIN}_main"
    MAIN_CONFIG_ENABLED="/etc/nginx/sites-enabled/${MAIN_DOMAIN}_main"
    
    if [ ! -f "$MAIN_CONFIG" ]; then
        log_warning "Конфиг для основного домена не найден: $MAIN_CONFIG"
        NGINX_ISSUES+=("main_config:$MAIN_DOMAIN")
    else
        if [ ! -L "$MAIN_CONFIG_ENABLED" ]; then
            log_warning "Конфиг для основного домена не активирован"
            NGINX_ISSUES+=("main_config_enabled:$MAIN_DOMAIN")
        else
            if ! grep -q "include /etc/nginx/snippets/vpnbot_webhooks.conf" "$MAIN_CONFIG" 2>/dev/null; then
                log_warning "Сниппет webhook не включен в конфиг основного домена"
                NGINX_ISSUES+=("main_webhook:$MAIN_DOMAIN")
            else
                log_success "Конфиг для основного домена найден и настроен"
            fi
        fi
    fi
    
    REMNAWAVE_CONFIG="/etc/nginx/sites-available/remnawave"
    
    if [ -f "$REMNAWAVE_CONFIG" ]; then
        log_info "Конфиг remnawave найден (panel/sub домены используются для панели и подписок, не для webhook'ов)"
    fi
    
    if [ ${#NGINX_ISSUES[@]} -eq 0 ]; then
        NGINX_CONFIGS_OK=true
        return 0
    else
        NGINX_CONFIGS_OK=false
        return 1
    fi
}

create_main_domain_config() {
    log_step "Создание конфига для основного домена"
    
    local config_file="/etc/nginx/sites-available/${MAIN_DOMAIN}_main"
    local ssl_cert="/etc/letsencrypt/live/${MAIN_DOMAIN}/fullchain.pem"
    local ssl_key="/etc/letsencrypt/live/${MAIN_DOMAIN}/privkey.pem"
    
    if [ ! -f "$ssl_cert" ]; then
        if [ -f "/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem" ]; then
            ssl_cert="/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
            ssl_key="/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem"
            log_info "Используется SSL сертификат от ${PANEL_DOMAIN}"
        else
            log_error "SSL сертификат не найден ни для основного домена, ни для panel домена"
            return 1
        fi
    fi
    
    cat > "$config_file" << EOF
server {
    listen 80;
    server_name ${MAIN_DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${MAIN_DOMAIN};
    
    ssl_certificate ${ssl_cert};
    ssl_certificate_key ${ssl_key};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    include /etc/nginx/snippets/vpnbot_webhooks.conf;
    
    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    ln -sf "$config_file" "/etc/nginx/sites-enabled/${MAIN_DOMAIN}_main"
    
    log_success "Конфиг для основного домена создан: $config_file"
}

add_webhook_to_remnawave() {
    local domain_type="$1"
    local domain="$2"
    
    log_step "Добавление сниппета webhook в конфиг remnawave для $domain"
    
    local config_file="/etc/nginx/sites-available/remnawave"
    local include_line="    include /etc/nginx/snippets/vpnbot_webhooks.conf;"
    
    if grep -A20 "server_name.*${domain}" "$config_file" | grep -q "include /etc/nginx/snippets/vpnbot_webhooks.conf" 2>/dev/null; then
        log_info "Сниппет уже включен для $domain"
        return 0
    fi
    
    awk -v dom="$domain" -v inc="$include_line" '
        BEGIN { in_server=0; depth=0; found_443=0; added=0 }
        {
            if (/server\s*\{/ && !in_server) {
                in_server=1
                depth=1
                found_443=0
                print $0
                next
            }
            if (in_server) {
                if (/listen[^;]*443/) { found_443=1 }
                if (/server_name/ && $0 ~ dom) { target_server=1 }
                if (/server_name/ && $0 !~ dom) { target_server=0 }
                
                open_cnt = gsub(/\{/, "{", $0)
                close_cnt = gsub(/\}/, "}", $0)
                depth += open_cnt
                depth -= close_cnt
                
                if (found_443 && target_server && depth==1 && !added) {
                    print inc
                    added=1
                }
                
                if (depth==0) {
                    in_server=0
                    found_443=0
                    added=0
                    target_server=0
                }
            }
            print $0
        }
    ' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
    
    log_success "Сниппет добавлен в конфиг remnawave для $domain"
}

check_webhook_availability() {
    log_step "Проверка доступности webhook'ов"
    
    WEBHOOK_ISSUES=()
    
    if ! curl -s http://127.0.0.1:8000/webhooks/health > /dev/null 2>&1; then
        log_warning "Бот не отвечает на порту 8000"
        WEBHOOK_ISSUES+=("bot_port")
    else
        log_success "Бот отвечает на порту 8000"
    fi
    
    if ! curl -k -s "https://${MAIN_DOMAIN}/webhooks/health" > /dev/null 2>&1; then
        log_warning "Webhook недоступен через основной домен: https://${MAIN_DOMAIN}/webhooks/health"
        WEBHOOK_ISSUES+=("main_domain_webhook")
    else
        log_success "Webhook доступен через основной домен"
    fi
    
    if ! curl -k -s "https://${PANEL_DOMAIN}/webhooks/health" > /dev/null 2>&1; then
        log_warning "Webhook недоступен через panel домен: https://${PANEL_DOMAIN}/webhooks/health"
        WEBHOOK_ISSUES+=("panel_domain_webhook")
    else
        log_success "Webhook доступен через panel домен"
    fi
    
    if [ ${#WEBHOOK_ISSUES[@]} -eq 0 ]; then
        WEBHOOKS_OK=true
        return 0
    else
        WEBHOOKS_OK=false
        return 1
    fi
}

check_nginx_status() {
    log_step "Проверка статуса Nginx"
    
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        log_error "Nginx не работает"
        NGINX_STATUS_OK=false
        return 1
    fi
    
    if ! nginx -t > /dev/null 2>&1; then
        log_error "Синтаксис Nginx некорректен"
        NGINX_STATUS_OK=false
        return 1
    fi
    
    log_success "Nginx работает и синтаксис корректен"
    NGINX_STATUS_OK=true
    return 0
}

reload_nginx() {
    log_step "Перезагрузка Nginx"
    
    if nginx -t > /dev/null 2>&1; then
        systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
        log_success "Nginx перезагружен"
        return 0
    else
        log_error "Синтаксис Nginx некорректен, перезагрузка отменена"
        nginx -t
        return 1
    fi
}

show_report() {
    log_step "ОТЧЕТ О ПРОВЕРКЕ КОНФИГУРАЦИИ СИСТЕМЫ"
    
    local has_issues=false
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}              ОТЧЕТ О ПРОВЕРКЕ КОНФИГУРАЦИИ СИСТЕМЫ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}                    НАЙДЕННЫЕ ПРОБЛЕМЫ${NC}"
    echo ""
    
    if [ "${WEBHOOK_SNIPPET_MISSING:-false}" = true ] || [ "${WEBHOOK_SNIPPET_INVALID:-false}" = true ]; then
        echo -e "${RED}❌${NC} Сниппет webhook отсутствует или некорректен"
        has_issues=true
    fi
    
    if [ "${SSL_CERTS_OK:-true}" = false ]; then
        echo -e "${RED}❌${NC} SSL сертификаты отсутствуют для:"
        for issue in "${SSL_ISSUES[@]}"; do
            local domain_type="${issue%%:*}"
            local domain="${issue#*:}"
            echo -e "   - ${domain_type}: ${domain}"
        done
        has_issues=true
    fi
    
    if [ "${NGINX_CONFIGS_OK:-true}" = false ]; then
        echo -e "${RED}❌${NC} Проблемы с конфигами Nginx:"
        for issue in "${NGINX_ISSUES[@]}"; do
            local issue_type="${issue%%:*}"
            local domain="${issue#*:}"
            case "$issue_type" in
                main_config)
                    echo -e "   - Конфиг для основного домена не найден: ${domain}"
                    ;;
                main_config_enabled)
                    echo -e "   - Конфиг для основного домена не активирован: ${domain}"
                    ;;
                main_webhook)
                    echo -e "   - Сниппет webhook не включен для основного домена: ${domain}"
                    ;;
            esac
        done
        has_issues=true
    fi
    
    if [ "${WEBHOOKS_OK:-true}" = false ]; then
        echo -e "${RED}❌${NC} Проблемы с доступностью webhook'ов:"
        for issue in "${WEBHOOK_ISSUES[@]}"; do
            case "$issue" in
                bot_port)
                    echo -e "   - Бот не отвечает на порту 8000"
                    ;;
                main_domain_webhook)
                    echo -e "   - Webhook недоступен через основной домен"
                    ;;
                panel_domain_webhook)
                    echo -e "   - Webhook недоступен через panel домен"
                    ;;
            esac
        done
        has_issues=true
    fi
    
    if [ "${NGINX_STATUS_OK:-true}" = false ]; then
        echo -e "${RED}❌${NC} Nginx не работает или синтаксис некорректен"
        has_issues=true
    fi
    
    if [ "$has_issues" = false ]; then
        echo -e "${GREEN}✅ Все проверки пройдены успешно!${NC}"
        echo ""
        echo -e "${GREEN}Webhook URL для платежных систем:${NC}"
        echo -e "  - YooKassa: https://${MAIN_DOMAIN}/webhooks/yookassa"
        echo -e "  - Heleket: https://${MAIN_DOMAIN}/webhooks/heleket"
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

show_action_menu() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    МЕНЮ ДЕЙСТВИЙ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local action_num=1
    ACTIONS=()
    
    if [ "${WEBHOOK_SNIPPET_MISSING:-false}" = true ] || [ "${WEBHOOK_SNIPPET_INVALID:-false}" = true ]; then
        echo -e "  ${BLUE}${action_num})${NC} Создать/исправить сниппет webhook"
        ACTIONS+=("create_snippet")
        action_num=$((action_num + 1))
    fi
    
    if [ "${SSL_CERTS_OK:-true}" = false ]; then
        for issue in "${SSL_ISSUES[@]}"; do
            local domain_type="${issue%%:*}"
            local domain="${issue#*:}"
            echo -e "  ${BLUE}${action_num})${NC} Получить SSL сертификат для ${domain_type}: ${domain}"
            ACTIONS+=("get_ssl:$domain_type:$domain")
            action_num=$((action_num + 1))
        done
    fi
    
    if [ "${NGINX_CONFIGS_OK:-true}" = false ]; then
        for issue in "${NGINX_ISSUES[@]}"; do
            local issue_type="${issue%%:*}"
            local domain="${issue#*:}"
            case "$issue_type" in
                main_config)
                    echo -e "  ${BLUE}${action_num})${NC} Создать конфиг для основного домена: ${domain}"
                    ACTIONS+=("create_main_config")
                    action_num=$((action_num + 1))
                    ;;
                main_config_enabled)
                    echo -e "  ${BLUE}${action_num})${NC} Активировать конфиг для основного домена: ${domain}"
                    ACTIONS+=("enable_main_config")
                    action_num=$((action_num + 1))
                    ;;
                main_webhook)
                    echo -e "  ${BLUE}${action_num})${NC} Добавить сниппет webhook в конфиг основного домена: ${domain}"
                    ACTIONS+=("add_webhook_main")
                    action_num=$((action_num + 1))
                    ;;
            esac
        done
    fi
    
    if [ "${NGINX_STATUS_OK:-true}" = false ]; then
        echo -e "  ${BLUE}${action_num})${NC} Проверить и исправить синтаксис Nginx"
        ACTIONS+=("fix_nginx")
        action_num=$((action_num + 1))
    fi
    
    if [ ${#ACTIONS[@]} -eq 0 ]; then
        echo -e "  ${GREEN}Нет доступных действий - все настроено правильно!${NC}"
        echo ""
        return 1
    fi
    
    echo ""
    echo -e "  ${BLUE}0)${NC} Выход"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    return 0
}

execute_action() {
    local action="$1"
    
    case "$action" in
        create_snippet)
            create_webhook_snippet
            reload_nginx
            ;;
        get_ssl:*)
            local domain_type="${action#get_ssl:}"
            local domain_type_part="${domain_type%%:*}"
            local domain="${domain_type#*:}"
            get_ssl_certificate "$domain_type_part" "$domain"
            reload_nginx
            ;;
        create_main_config)
            create_main_domain_config
            reload_nginx
            ;;
        enable_main_config)
            ln -sf "/etc/nginx/sites-available/${MAIN_DOMAIN}_main" "/etc/nginx/sites-enabled/${MAIN_DOMAIN}_main"
            log_success "Конфиг активирован"
            reload_nginx
            ;;
        add_webhook_main)
            if [ -f "/etc/nginx/sites-available/${MAIN_DOMAIN}_main" ]; then
                if ! grep -q "include /etc/nginx/snippets/vpnbot_webhooks.conf" "/etc/nginx/sites-available/${MAIN_DOMAIN}_main" 2>/dev/null; then
                    sed -i '/location \//i\    include /etc/nginx/snippets/vpnbot_webhooks.conf;' "/etc/nginx/sites-available/${MAIN_DOMAIN}_main"
                    log_success "Сниппет добавлен в конфиг основного домена"
                    reload_nginx
                fi
            fi
            ;;
        fix_nginx)
            log_step "Проверка синтаксиса Nginx"
            nginx -t
            ;;
    esac
}

show_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║                    ULTIMA 3.1.0                              ║"
    echo "║         Проверка и Исправление Конфигурации Системы          ║"
    echo "║                                                              ║"
    echo "║        SSL • Nginx • Webhooks • Payment Systems             ║"
    echo "║                                                              ║"
    echo "║                  by alexcoder (@ultima_supbot)               ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

main() {
    show_banner
    check_root
    detect_project_root
    
    if ! get_domain; then
        exit 1
    fi
    
    WEBHOOK_SNIPPET_MISSING=false
    WEBHOOK_SNIPPET_INVALID=false
    WEBHOOK_SNIPPET_OK=false
    SSL_CERTS_OK=true
    NGINX_CONFIGS_OK=true
    WEBHOOKS_OK=true
    NGINX_STATUS_OK=true
    
    check_webhook_snippet
    check_ssl_certificates
    check_nginx_configs
    check_webhook_availability
    check_nginx_status
    
    show_report
    
    if [ "${WEBHOOK_SNIPPET_MISSING:-false}" = true ] || [ "${WEBHOOK_SNIPPET_INVALID:-false}" = true ] || \
       [ "${SSL_CERTS_OK:-true}" = false ] || [ "${NGINX_CONFIGS_OK:-true}" = false ] || \
       [ "${WEBHOOKS_OK:-true}" = false ] || [ "${NGINX_STATUS_OK:-true}" = false ]; then
        
        if [ ! -t 0 ] || [ ! -t 1 ]; then
            log_error "Скрипт должен запускаться в интерактивном режиме"
            log_info "Запустите скрипт напрямую: bash check_and_fix_config.sh"
            exit 1
        fi
        
        local max_iterations=100
        local iteration=0
        
        while [ $iteration -lt $max_iterations ]; do
        iteration=$((iteration + 1))
        
        if ! show_action_menu; then
            log_success "Все проблемы решены!"
            break
        fi
        
        echo -n "Выберите действие (0-${#ACTIONS[@]}): "
        if ! read -t 30 choice; then
            read_exit_code=$?
            echo ""
            if [ $read_exit_code -eq 142 ]; then
                log_error "Таймаут ожидания ввода (30 сек). Выход."
            else
                log_error "Ошибка чтения ввода. Скрипт должен запускаться в интерактивном режиме."
            fi
            exit 1
        fi
        
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        if [ -z "$choice" ]; then
            log_error "Пустой ввод. Попробуйте снова."
            sleep 1
            continue
        fi
        
        if [ "$choice" = "0" ]; then
            log_info "Выход"
            exit 0
        fi
        
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            log_error "Неверный формат. Введите число от 1 до ${#ACTIONS[@]} или 0 для выхода."
            sleep 1
            continue
        fi
        
        if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#ACTIONS[@]} ]; then
            log_error "Неверный выбор. Введите число от 1 до ${#ACTIONS[@]} или 0 для выхода."
            sleep 1
            continue
        fi
        
        local action_index=$((choice - 1))
        local action="${ACTIONS[$action_index]}"
        
        execute_action "$action"
        
        echo ""
        log_info "Повторная проверка после выполнения действия..."
        sleep 2
        
        WEBHOOK_SNIPPET_MISSING=false
        WEBHOOK_SNIPPET_INVALID=false
        SSL_CERTS_OK=true
        NGINX_CONFIGS_OK=true
        WEBHOOKS_OK=true
        NGINX_STATUS_OK=true
        SSL_ISSUES=()
        NGINX_ISSUES=()
        WEBHOOK_ISSUES=()
        
        check_webhook_snippet
        check_ssl_certificates
        check_nginx_configs
        check_webhook_availability
        check_nginx_status
        
        show_report
        done
    else
        log_success "Все проверки пройдены успешно!"
    fi
}

main "$@"

