#!/usr/bin/env python3
"""
Скрипт для исправления бага с last_check в конфигах
Версия: 3.1.1 SE

Проблема: При создании конфигов не устанавливался last_check,
из-за чего они списывались повторно в следующем тике биллинга.

Исправление: Устанавливает last_check = created_at для всех активных
конфигов с last_check = None.
"""

import asyncio
import sys
import os
from datetime import datetime, timezone

if os.path.exists('/app'):
    project_root = '/app'
else:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, '../../..'))

sys.path.insert(0, project_root)
os.chdir(project_root)

from app.infrastructure.database.connection import get_session
from app.domain.models.vpn.user_config import UserConfig
from sqlalchemy import select, update


async def fix_last_check_bug():
    print("🔧 Запуск исправления бага last_check...")
    print("=" * 60)
    
    session_maker = get_session()
    async with session_maker() as session:
        try:
            stmt = select(UserConfig).where(
                UserConfig.status == "active",
                UserConfig.is_active == True,
                UserConfig.last_check.is_(None)
            )
            result = await session.execute(stmt)
            configs_to_fix = result.scalars().all()
            
            total_count = len(configs_to_fix)
            print(f"📊 Найдено конфигов для исправления: {total_count}")
            
            if total_count == 0:
                print("✅ Все конфиги уже исправлены!")
                return
            
            fixed_count = 0
            now_utc = datetime.now(timezone.utc)
            
            for config in configs_to_fix:
                if config.created_at:
                    if config.created_at.tzinfo is None:
                        last_check_value = config.created_at.replace(tzinfo=timezone.utc)
                    else:
                        last_check_value = config.created_at
                else:
                    last_check_value = now_utc
                
                config.last_check = last_check_value
                fixed_count += 1
            
            await session.commit()
            
            print(f"✅ Исправлено конфигов: {fixed_count}")
            print("=" * 60)
            print("🎉 Исправление завершено успешно!")
            print("\nТеперь эти конфиги не будут списываться повторно в следующем тике биллинга.")
            print("Следующий платеж будет только через сутки после создания конфига.")
            
        except Exception as e:
            await session.rollback()
            print(f"❌ Ошибка при исправлении: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


async def show_statistics():
    print("\n📊 Статистика по конфигам:")
    print("=" * 60)
    
    session_maker = get_session()
    async with session_maker() as session:
        try:
            stmt_all = select(UserConfig).where(
                UserConfig.status == "active",
                UserConfig.is_active == True
            )
            result_all = await session.execute(stmt_all)
            all_configs = result_all.scalars().all()
            total_active = len(all_configs)
            
            stmt_none = select(UserConfig).where(
                UserConfig.status == "active",
                UserConfig.is_active == True,
                UserConfig.last_check.is_(None)
            )
            result_none = await session.execute(stmt_none)
            configs_none = result_none.scalars().all()
            count_none = len(configs_none)
            
            count_with_check = total_active - count_none
            
            print(f"Всего активных конфигов: {total_active}")
            print(f"  - С last_check = None: {count_none}")
            print(f"  - С установленным last_check: {count_with_check}")
            print("=" * 60)
            
        except Exception as e:
            print(f"❌ Ошибка при получении статистики: {e}")
            import traceback
            traceback.print_exc()


async def main():
    print("\n" + "=" * 60)
    print("🔧 Скрипт исправления бага last_check")
    print("   Версия: 3.1.1 SE")
    print("=" * 60 + "\n")
    
    await show_statistics()
    
    print("\n⚠️  ВНИМАНИЕ: Этот скрипт изменит данные в базе данных!")
    response = input("Продолжить? (yes/no): ").strip().lower()
    
    if response not in ['yes', 'y', 'да', 'д']:
        print("❌ Отменено пользователем")
        sys.exit(0)
    
    print("\n")
    
    await fix_last_check_bug()
    
    print("\n")
    await show_statistics()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n❌ Прервано пользователем")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Критическая ошибка: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
