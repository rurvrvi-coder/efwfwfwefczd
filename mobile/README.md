# TG WS Proxy Mobile

Мобильное приложение (Android/iOS) для запуска локального SOCKS5-прокси с поддержкой WebSocket для Telegram.

## Структура проекта

```
mobile/
├── lib/
│   ├── main.dart              # Точка входа и главный экран
│   ├── proxy_core.dart        # Ядро прокси (SOCKS5 + WebSocket)
│   ├── proxy_provider.dart    # State management (Provider)
│   ├── config.dart            # Конфигурация и сохранение настроек
│   ├── settings_screen.dart   # Экран настроек
│   ├── stats_screen.dart      # Экран статистики
│   └── logs_screen.dart       # Экран логов
├── android/
│   └── app/
│       └── src/main/
│           ├── AndroidManifest.xml
│           └── kotlin/.../ProxyService.kt  # Фоновый сервис Android
└── ios/
    └── Runner/
        └── Info.plist
```

## Установка

### Требования
- Flutter SDK 3.0+
- Android Studio / Xcode
- Android SDK / iOS Simulator

### Шаги

```bash
cd mobile

# Установка зависимостей
flutter pub get

# Запуск (Android)
flutter run

# Запуск (iOS)
flutter run

# Сборка APK
flutter build apk --release

# Сборка iOS
flutter build ios --release
```

## Использование

1. **Запустите приложение**
2. **Нажмите "Запустить"** для старта прокси
3. **Настройте Telegram:**
   - Настройки → Продвинутые → Тип подключения → Прокси
   - SOCKS5 → `127.0.0.1` : `1080`
   - Без логина/пароля

## Настройки

- **Порт**: порт SOCKS5-прокси (по умолчанию 1080)
- **DC → IP**: маппинг дата-центров Telegram
- **Verbose**: подробное логирование

## Особенности

- **Автоматический fallback**: при недоступности WebSocket переключается на TCP
- **Статистика**: отслеживание трафика и подключений
- **Логи**: подробное логирование всех событий
- **Фоновая работа**: прокси работает в фоне (Android Service)

## Архитектура

```
Telegram → SOCKS5 (127.0.0.1:1080) → TG WS Proxy → WSS (kws*.web.telegram.org) → Telegram DC
```

### Компоненты

1. **SOCKS5 Server**: принимает подключения от Telegram
2. **DC Detector**: определяет DC ID из MTProto init-пакета
3. **WebSocket Client**: подключается к kws{N}.web.telegram.org
4. **TCP Fallback**: резервный режим при недоступности WS
5. **Bridge**: двунаправленная переадресация трафика

## Лицензия

MIT
