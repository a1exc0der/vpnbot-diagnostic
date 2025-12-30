#!/bin/bash

REPO_URL="https://raw.githubusercontent.com/a1exc0der/vpnbot-diagnostic/last-check-fix"
SCRIPT_URL="$REPO_URL/run_fix_last_check.sh"

echo "Загрузка скрипта исправления..."
wget "$SCRIPT_URL?v=$(date +%s)" -O /tmp/fix_last_check_main.sh 2>&1

if [ $? -ne 0 ]; then
    echo "Ошибка загрузки скрипта"
    exit 1
fi

chmod +x /tmp/fix_last_check_main.sh
echo "Запуск скрипта исправления..."
echo ""

bash /tmp/fix_last_check_main.sh
