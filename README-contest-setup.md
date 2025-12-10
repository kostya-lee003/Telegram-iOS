# Telegram-iOS – Contest Setup (Kostya)

Этот файл описывает мою локальную среду и шаги, которые я использовал, чтобы собрать и запустить Telegram-iOS (release 11.11.2) на Apple Silicon для участия в дизайн-контесте.

## Среда

- MacBook Pro M1 Max (Apple Silicon)
- macOS: 15.6.1 (Sequoia)
- Xcode: **16.2** (Build version 16C5032a)
- Swift tools version: 6.0.3
- Bazel: **7.3.1** (`bazel-7.3.1-darwin-arm64` в `~/bazel-dist/bazel`)
- Репозиторий: fork от `TelegramMessenger/Telegram-iOS`, тег `release-11.11.2`

## Конфигурация

### 1. Bazel

Скачал Bazel 7.3.1 для darwin-arm64 и положил в:

```
mkdir -p ~/bazel-dist
mv bazel-7.3.1-darwin-arm64 ~/bazel-dist/bazel
chmod +x ~/bazel-dist/bazel
```

### 2. Конфиг Telegram
Вне репозитория лежит конфигурация:
```bash
~/telegram-configuration/configuration.json
```

Там настроены:
```bash
bundle_id: org.coolrepka.Telegram
team_id: Z36VGA9KK8
```

### 3. .bazelrc
В корне проекта добавил строку:

```
build --action_env=CMAKE_OSX_ARCHITECTURES=arm64
```

Это нужно для корректной сборки tdlib (third-party/td) под архитектуру arm64 на Apple Silicon симуляторах. Без этого libtde2e.a и libtdutils.a собирались как x86_64, и линковщик падал с ошибками:

```
found architecture 'x86_64', required 'arm64'
Undefined symbols for architecture arm64: tde2e_api::...
```

4. Генерация Xcode-проекта
Проект генерируется командой:

```
python3 build-system/Make/Make.py \
  --bazel="$HOME/bazel-dist/bazel" \
  --cacheDir="$HOME/telegram-bazel-cache" \
  generateProject \
  --configurationPath="$HOME/telegram-configuration/configuration.json" \
  --disableExtensions \
  --disableProvisioningProfiles \
  --xcodeManagedCodesigning
```
