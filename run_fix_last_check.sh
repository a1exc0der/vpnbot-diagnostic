#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() {
    echo -e "${CYAN}[ℹ️  INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[✅ SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[⚠️  WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[❌ ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${BLUE}[📋 STEP]${NC} $1" >&2
}

echo "" >&2
echo -e "${PURPLE}=============================================================================${NC}" >&2
echo -e "${WHITE}🔧 ULTIMA VPN Bot - Исправление бага last_check${NC}" >&2
echo -e "${PURPLE}=============================================================================${NC}" >&2
echo -e "${CYAN}Автор:${NC} alexcoder" >&2
echo -e "${CYAN}Разработчик:${NC} alexcoder" >&2
echo -e "${CYAN}Проект:${NC} ULTIMA VPN Bot" >&2
echo -e "${CYAN}Команда:${NC} Team Bot" >&2
echo -e "${CYAN}Версия:${NC} 3.1.1 SE" >&2
echo -e "${PURPLE}=============================================================================${NC}" >&2
echo "" >&2

REPO_URL="https://raw.githubusercontent.com/a1exc0der/vpnbot-diagnostic/last-check-fix"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "/tmp")"

log_step "Инициализация..."

PROJECT_ROOT="/root/vpnbot-v3"
PATCH_APPLIED=false

if [ -f "$SCRIPT_DIR/fix_last_check_bug.py" ] && [ "$SCRIPT_DIR" != "/tmp" ] && [ -d "$SCRIPT_DIR/../../.." ]; then
    FIX_SCRIPT="$SCRIPT_DIR/fix_last_check_bug.py"
    APPLY_PATCH_SCRIPT="$SCRIPT_DIR/apply_last_check_fix.sh"
    PATCH_FILE="$SCRIPT_DIR/patch_last_check_v311.patch"
    log_info "Используем локальные файлы из: $SCRIPT_DIR"
else
    
    TEMP_DIR="/tmp/last_check_fix_$$"
    mkdir -p "$TEMP_DIR"
    
    log_step "Загрузка необходимых файлов из GitHub..."
    cd "$TEMP_DIR"
    
    if ! wget -q "$REPO_URL/fix_last_check_bug.py" -O fix_last_check_bug.py 2>&1; then
        log_error "Не удалось загрузить fix_last_check_bug.py из $REPO_URL/fix_last_check_bug.py"
        exit 1
    fi
    log_info "✓ fix_last_check_bug.py загружен"
    
    if ! wget -q "$REPO_URL/apply_last_check_fix.sh" -O apply_last_check_fix.sh 2>&1; then
        log_error "Не удалось загрузить apply_last_check_fix.sh из $REPO_URL/apply_last_check_fix.sh"
        exit 1
    fi
    log_info "✓ apply_last_check_fix.sh загружен"
    
    if ! wget -q "$REPO_URL/patch_last_check_v311.patch" -O patch_last_check_v311.patch 2>&1; then
        log_error "Не удалось загрузить patch_last_check_v311.patch из $REPO_URL/patch_last_check_v311.patch"
        exit 1
    fi
    log_info "✓ patch_last_check_v311.patch загружен"
    
    chmod +x fix_last_check_bug.py apply_last_check_fix.sh
    
    FIX_SCRIPT="$TEMP_DIR/fix_last_check_bug.py"
    APPLY_PATCH_SCRIPT="$TEMP_DIR/apply_last_check_fix.sh"
    PATCH_FILE="$TEMP_DIR/patch_last_check_v311.patch"
    
    cleanup() {
        rm -rf "$TEMP_DIR"
    }
    trap cleanup EXIT
    
    log_success "Все файлы загружены"
fi

if [ ! -d "$PROJECT_ROOT" ]; then
    log_error "Проект не найден в $PROJECT_ROOT"
    exit 1
fi

log_step "Проверка окружения..."

if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "docker-compose.yml не найден в $PROJECT_ROOT"
    exit 1
fi
log_success "docker-compose.yml найден"

if [ ! -f "$FIX_SCRIPT" ]; then
    log_error "Скрипт исправления не найден: $FIX_SCRIPT"
    exit 1
fi
log_success "Скрипт исправления найден"

if ! docker compose ps 2>/dev/null | grep -q "bot.*Up" && ! docker ps 2>/dev/null | grep -q "vpnbot.*bot"; then
    log_error "Бот не запущен. Запустите бота перед исправлением!"
    exit 1
fi
log_success "Бот запущен"
echo "" >&2

log_step "ШАГ 1: Проверка применения патча к коду..."

if docker compose exec -T bot grep -q "last_check=now_utc" /app/app/domain/services/vpn_service.py 2>/dev/null; then
    log_success "Патч кода уже применен!"
    echo "   Новые конфиги будут создаваться с last_check автоматически" >&2
    PATCH_APPLIED=true
else
    log_warning "Патч кода не применен"
    echo "" >&2
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ:${NC} Для полного исправления нужно применить патч к коду." >&2
    echo "   Это исправит создание новых конфигов в будущем." >&2
    echo "" >&2
    read -p "Применить патч к коду сейчас? (yes/no): " apply_patch
    
    if [ "$apply_patch" = "yes" ]; then
        log_step "Применение патча к коду..."
        if [ -f "$APPLY_PATCH_SCRIPT" ]; then
            SCRIPTS_DIR="$PROJECT_ROOT/app/scripts/LastCheckFix"
            mkdir -p "$SCRIPTS_DIR" 2>/dev/null || true
            
            if [ -n "${PATCH_FILE:-}" ] && [ -f "$PATCH_FILE" ]; then
                cp "$PATCH_FILE" "$SCRIPTS_DIR/" 2>/dev/null || true
            fi
            
            APPLY_PATCH_SCRIPT_IN_PROJECT="$SCRIPTS_DIR/apply_last_check_fix.sh"
            cp "$APPLY_PATCH_SCRIPT" "$APPLY_PATCH_SCRIPT_IN_PROJECT" 2>/dev/null || true
            
            cd "$PROJECT_ROOT"
            if bash "$APPLY_PATCH_SCRIPT_IN_PROJECT" "$PROJECT_ROOT"; then
                log_success "Патч успешно применен!"
                PATCH_APPLIED=true
            else
                log_error "Ошибка применения патча"
                exit 1
            fi
        else
            log_error "Скрипт применения патча не найден: $APPLY_PATCH_SCRIPT"
            exit 1
        fi
    else
        log_warning "Патч кода не применен. Продолжаем только с исправлением БД..."
        PATCH_APPLIED=false
    fi
fi
echo "" >&2

log_step "ШАГ 2: Исправление существующих конфигов в БД..."

log_info "Проверка конфигов в базе данных..."
STATS=$(docker compose exec -T bot python3 -c "
import sys
sys.path.insert(0, '/app')
from app.infrastructure.database.connection import get_session
from app.domain.models.vpn.user_config import UserConfig
from sqlalchemy import select, func
import asyncio

async def get_stats():
    session_maker = get_session()
    async with session_maker() as session:
        total = await session.execute(select(func.count(UserConfig.id)).where(
            UserConfig.status == 'active',
            UserConfig.is_active == True
        ))
        total_count = total.scalar() or 0
        
        none = await session.execute(select(func.count(UserConfig.id)).where(
            UserConfig.status == 'active',
            UserConfig.is_active == True,
            UserConfig.last_check.is_(None)
        ))
        none_count = none.scalar() or 0
        
        print(f'{total_count}|{none_count}')

asyncio.run(get_stats())
" 2>&1)

if [ -n "$STATS" ]; then
    TOTAL=$(echo $STATS | cut -d'|' -f1)
    NONE=$(echo $STATS | cut -d'|' -f2)
    
    echo "   Всего активных конфигов: $TOTAL" >&2
    echo "   Конфигов без last_check: $NONE" >&2
    echo "" >&2
    
    if [ "$NONE" -eq 0 ]; then
        log_success "Все конфиги уже исправлены!"
        echo "   Нет конфигов без last_check в базе данных." >&2
        echo "" >&2
        echo -e "${PURPLE}=============================================================================${NC}" >&2
        log_success "Исправление завершено!"
        echo -e "${PURPLE}=============================================================================${NC}" >&2
        exit 0
    fi
else
    log_warning "Не удалось получить статистику из БД"
    echo "   Продолжаем исправление..." >&2
    NONE="?"
fi

echo "" >&2
log_warning "ВНИМАНИЕ: Этот скрипт изменит данные в базе данных!"
if [ "$NONE" != "?" ]; then
    echo "   Будет исправлено конфигов без last_check: $NONE" >&2
fi
echo "" >&2
read -p "Продолжить исправление? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    log_info "Исправление отменено пользователем"
    exit 0
fi

log_step "Запуск исправления конфигов в БД..."
echo "" >&2

if [ ! -f "$FIX_SCRIPT" ]; then
    log_error "Скрипт исправления не найден: $FIX_SCRIPT"
    exit 1
fi

SCRIPTS_DIR="$PROJECT_ROOT/app/scripts/LastCheckFix"
FIX_SCRIPT_IN_PROJECT="$SCRIPTS_DIR/fix_last_check_bug.py"
FIX_SCRIPT_IN_CONTAINER="/app/app/scripts/LastCheckFix/fix_last_check_bug.py"

log_info "Создание директории для скриптов..."
mkdir -p "$SCRIPTS_DIR" 2>&1 || {
    log_error "Не удалось создать директорию: $SCRIPTS_DIR"
    exit 1
}

log_info "Копирование скрипта в проект..."
log_info "Источник: $FIX_SCRIPT"
log_info "Назначение: $FIX_SCRIPT_IN_PROJECT"

if ! cp "$FIX_SCRIPT" "$FIX_SCRIPT_IN_PROJECT" 2>&1; then
    log_error "Не удалось скопировать скрипт в $SCRIPTS_DIR"
    exit 1
fi

if [ ! -f "$FIX_SCRIPT_IN_PROJECT" ]; then
    log_error "Файл не был скопирован: $FIX_SCRIPT_IN_PROJECT"
    exit 1
fi

log_info "Скрипт скопирован в: $FIX_SCRIPT_IN_PROJECT"
log_info "Запуск скрипта в контейнере: $FIX_SCRIPT_IN_CONTAINER"

cd "$PROJECT_ROOT"
if echo "yes" | docker compose exec -T bot python3 "$FIX_SCRIPT_IN_CONTAINER" 2>&1; then
    FIX_RESULT=0
else
    FIX_RESULT=$?
fi

rm -f "$FIX_SCRIPT_IN_PROJECT"

if [ $FIX_RESULT -eq 0 ]; then
    echo "" >&2
    log_success "Исправление БД завершено успешно!"
else
    log_error "Ошибка при исправлении БД (код: $FIX_RESULT)"
    exit 1
fi

echo "" >&2
log_step "Проверка результата..."

FINAL_STATS=$(docker compose exec -T bot python3 -c "
import sys
sys.path.insert(0, '/app')
from app.infrastructure.database.connection import get_session
from app.domain.models.vpn.user_config import UserConfig
from sqlalchemy import select, func
import asyncio

async def get_stats():
    session_maker = get_session()
    async with session_maker() as session:
        total = await session.execute(select(func.count(UserConfig.id)).where(
            UserConfig.status == 'active',
            UserConfig.is_active == True
        ))
        total_count = total.scalar() or 0
        
        none = await session.execute(select(func.count(UserConfig.id)).where(
            UserConfig.status == 'active',
            UserConfig.is_active == True,
            UserConfig.last_check.is_(None)
        ))
        none_count = none.scalar() or 0
        
        print(f'{total_count}|{none_count}')

asyncio.run(get_stats())
" 2>&1)

if [ -n "$FINAL_STATS" ]; then
    FINAL_TOTAL=$(echo $FINAL_STATS | cut -d'|' -f1)
    FINAL_NONE=$(echo $FINAL_STATS | cut -d'|' -f2)
    
    echo "   Всего активных конфигов: $FINAL_TOTAL" >&2
    echo "   Конфигов без last_check: $FINAL_NONE" >&2
    echo "" >&2
    
    if [ "$FINAL_NONE" -eq 0 ]; then
        log_success "Все конфиги исправлены!"
    else
        log_warning "Осталось конфигов без last_check: $FINAL_NONE"
    fi
fi

echo "" >&2
echo -e "${PURPLE}=============================================================================${NC}" >&2
log_info "Итоговые рекомендации:"
echo "" >&2

if [ "${PATCH_APPLIED:-false}" = "false" ]; then
    log_warning "1. Примените патч к коду для предотвращения проблемы в будущем:"
    echo "   bash $APPLY_PATCH_SCRIPT" >&2
    echo "   docker compose restart bot" >&2
    echo "" >&2
fi

log_info "2. После исправления:"
echo "   • Новые конфиги будут создаваться с last_check автоматически" >&2
echo "   • Старые конфиги исправлены (last_check = created_at)" >&2
echo "   • Двойное списание исключено" >&2
echo "" >&2

log_success "Исправление завершено!"
echo "" >&2

if [ "$PATCH_APPLIED" = "true" ] || [ "${PATCH_APPLIED:-false}" = "true" ]; then
    echo -e "${YELLOW}Для применения изменений в коде необходимо перезапустить бота.${NC}" >&2
    echo "" >&2
    read -p "Перезапустить бота сейчас? (yes/no): " restart_bot
    
    if [ "$restart_bot" = "yes" ]; then
        log_step "Перезапуск бота..."
        cd "$PROJECT_ROOT"
        if docker compose restart bot 2>&1; then
            log_success "Бот успешно перезапущен!"
        else
            log_error "Ошибка при перезапуске бота"
            echo "   Выполните вручную:" >&2
            echo "   cd $PROJECT_ROOT && docker compose restart bot" >&2
        fi
    else
        log_warning "Перезапуск бота пропущен"
        echo "   Выполните вручную:" >&2
        echo "   cd $PROJECT_ROOT && docker compose restart bot" >&2
    fi
    echo "" >&2
fi

echo -e "${PURPLE}=============================================================================${NC}" >&2
