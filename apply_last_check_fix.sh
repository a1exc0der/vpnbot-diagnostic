#!/bin/bash

# =============================================================================
# 🔧 ULTIMA VPN Bot - Применение патча last_check в коде
# =============================================================================
# Автор: alexcoder
# Разработчик: alexcoder
# Проект: ULTIMA VPN Bot
# Команда: Team Bot
# Версия: 3.1.1 SE
# Описание: Применяет патч к vpn_service.py для установки last_check при создании конфигов
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$1" ] && [ -d "$1" ]; then
    PROJECT_ROOT="$1"
else
    PROJECT_ROOT="/root/vpnbot-v3"
fi

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "❌ Ошибка: Проект не найден в $PROJECT_ROOT"
    exit 1
fi

PATCH_FILE="$SCRIPT_DIR/patch_last_check_v311.patch"
if [ ! -f "$PATCH_FILE" ]; then
    PATCH_FILE="$PROJECT_ROOT/app/scripts/LastCheckFix/patch_last_check_v311.patch"
fi

TARGET_FILE="$PROJECT_ROOT/app/domain/services/vpn_service.py"

if [ -z "$TARGET_FILE" ] || [ "$TARGET_FILE" = "//app/domain/services/vpn_service.py" ] || [ "$TARGET_FILE" = "/app/domain/services/vpn_service.py" ]; then
    echo "❌ Ошибка: Неправильный путь к файлу: '$TARGET_FILE'"
    TARGET_FILE="/root/vpnbot-v3/app/domain/services/vpn_service.py"
    echo "   Исправлено на: $TARGET_FILE"
fi

echo "=========================================="
echo "🔧 Применение исправления last_check в коде"
echo "   Версия: 3.1.1 SE"
echo "=========================================="
echo ""
echo "📁 PROJECT_ROOT: $PROJECT_ROOT"
echo "📄 TARGET_FILE: $TARGET_FILE"
echo ""

if [ ! -f "$TARGET_FILE" ]; then
    echo -e "${RED}❌ Ошибка: Файл не найден: $TARGET_FILE${NC}"
    echo "   Проверьте, что проект находится в: $PROJECT_ROOT"
    echo "   Список файлов в app/domain/services/:"
    ls -la "$PROJECT_ROOT/app/domain/services/" 2>&1 || echo "   Директория не найдена"
    exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
    echo -e "${RED}❌ Ошибка: Патч не найден: $PATCH_FILE${NC}"
    exit 1
fi

if grep -q "last_check=now_utc" "$TARGET_FILE"; then
    echo -e "${GREEN}✅ Исправление уже применено в файле $TARGET_FILE${NC}"
    echo "   Строка с 'last_check=now_utc' найдена"
    exit 0
fi

BACKUP_FILE="${TARGET_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET_FILE" "$BACKUP_FILE"
echo -e "${CYAN}💾 Создана резервная копия: $BACKUP_FILE${NC}"

echo -e "${BLUE}📝 Применение патча...${NC}"
cd "$PROJECT_ROOT"

if command -v patch >/dev/null 2>&1; then
    if patch -p1 < "$PATCH_FILE"; then
        echo -e "${GREEN}✅ Патч успешно применен!${NC}"
    else
        echo -e "${RED}❌ Ошибка применения патча${NC}"
        echo "🔄 Восстанавливаем из резервной копии..."
        cp "$BACKUP_FILE" "$TARGET_FILE"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  Команда 'patch' не найдена, применяем исправление вручную...${NC}"
    
    if grep -q "logger.info(f\"🆕 Создаю новый конфиг для пользователя {user_id}\")" "$TARGET_FILE"; then
        python3 << 'PYTHON_SCRIPT'
import re
import sys

file_path = sys.argv[1]
backup_path = sys.argv[2]

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'last_check=now_utc' in content:
    print("✅ Исправление уже применено")
    sys.exit(0)

pattern = r'(logger\.info\(f"🆕 Создаю новый конфиг для пользователя \{user_id\}"\)\s*\n)'
replacement = r'\1                from datetime import datetime, timezone\n                now_utc = datetime.now(timezone.utc)\n'

if re.search(pattern, content):
    content = re.sub(pattern, replacement, content)
    
    pattern2 = r'(status="active",\s*\n)'
    replacement2 = r'\1                    last_check=now_utc,  # Устанавливаем last_check при создании, чтобы следующий платеж был через сутки\n'
    
    if re.search(pattern2, content):
        content = re.sub(pattern2, replacement2, content)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print("✅ Исправление применено успешно!")
    else:
        print("❌ Не найдено место для добавления last_check")
        sys.exit(1)
else:
    print("❌ Не найдено место для вставки кода")
    sys.exit(1)
PYTHON_SCRIPT
        "$TARGET_FILE" "$BACKUP_FILE"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Ошибка применения исправления${NC}"
            echo "🔄 Восстанавливаем из резервной копии..."
            cp "$BACKUP_FILE" "$TARGET_FILE"
            exit 1
        fi
    fi
fi

if grep -q "last_check=now_utc" "$TARGET_FILE"; then
    echo ""
    echo -e "${GREEN}✅ Исправление успешно применено!${NC}"
    echo "📋 Файл: $TARGET_FILE"
    echo "💾 Резервная копия: $BACKUP_FILE"
    echo ""
    echo -e "${YELLOW}🔄 Перезапустите бота для применения изменений:${NC}"
    echo "   docker compose restart bot"
else
    echo -e "${RED}❌ Ошибка: Исправление не применено${NC}"
    echo "🔄 Восстанавливаем из резервной копии..."
    cp "$BACKUP_FILE" "$TARGET_FILE"
    exit 1
fi
