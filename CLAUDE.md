# CLAUDE.md — Правила проекта МВД Helper

## Общее

МВД Helper — AHK-скрипт-помощник для RP на MTA Province (МВД).
Это **не чит**, не обход античита, не инжект. Скрипт работает как обычный помощник: нажимает T (чат), печатает текст, нажимает Enter.

## Технические требования

- **AutoHotkey v1.1** Unicode (32/64-бит). НЕ v2.
- Кодировка: UTF-8 with BOM для .ahk, UTF-16 LE для profiles.ini.
- Один файл: `MVD_Helper_v5_0_RELEASE.ahk`.

## Ввод в игру — ТОЛЬКО через чат

1. Открыть чат: `cfg.chatKey` (по умолчанию `"t"`)
2. Печать: `SendText()` → `SendInput, {Text}%txt%` или `SendEvent, {Text}%txt%`
3. Подтверждение: `{Enter}` (кроме SafeMode)

## Запрещено

- `SendPlay` — запрещён
- `{F8}` — запрещён (консольные бинды)
- `uiAccess` — запрещён
- Инжекты, хуки, DLL, обходы/маскировка — запрещены
- "anti-cheat bypass" — запрещён

## Модификаторы

Перед отправкой текста отпускать **только Alt**: `{LAlt Up}{RAlt Up}`.
Shift/Ctrl НЕ трогать (если не включён `ForceChatKeyNoMods`).

## Guard / Release — обязательный паттерн

Все хоткеи обязаны использовать:

```ahk
!N::
    if (!Guard()) return
    try {
        ; ... действие ...
    } finally {
        Release()
    }
return
```

`Guard()` проверяет: `busy`, cooldown, профиль загружен, игра в фокусе.
`Release()` очищает `busy`, обновляет cooldown, обрабатывает SafeMode буфер.

## SafeMode

- Переключение: `Ctrl+Pause`
- Когда ON: текст буферизуется, не отправляется. В `Release()` копируется в clipboard.
- Игрок вставляет сам через `Ctrl+V`.

## Seq()

`Seq(lines, minMs, maxMs)` — отправляет массив строк в чат с рандомной задержкой.
Перед каждой строкой проверяет `IsGameActive()`. Если игра не в фокусе — прерывает.

## QuickMenu

- Хранение: секция `[QuickMenu]` в `profiles.ini`
- Типы: SEQ (последовательность строк через `|`), CMD (команда с `{ask:...}` / `{ask_digits:...}`)
- Гендерные плейсхолдеры: `{ok1}`, `{ok2}`, `{ok3}`
- Trailing space в payload = `pressEnter:=false` (для дописывания ID)

## GUI

- Именованные GUI: `Gui, QM:` (popup), `Gui, QMEdit:` (редактор). Основной GUI — без имени (default).
- Стиль: тёмная тема `181C25`, шрифт `Segoe UI`.

## INI секции

- `[Main]` — ActiveProfile
- `[Config]` — настройки скрипта
- `[QuickMenu]` — настройки быстрого меню
- `[ProfileName]` — профили пользователя

Зарезервированные имена секций: Main, Config, QuickMenu.
