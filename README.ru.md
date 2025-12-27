# Darkware Zapret для macOS

[![Релиз](https://img.shields.io/github/v/release/RoninReilly/darkware-zapret?style=flat&color=green)](https://github.com/RoninReilly/darkware-zapret/releases/latest)
[![Платформа](https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat)](https://github.com/RoninReilly/darkware-zapret)
[![Лицензия](https://img.shields.io/github/license/RoninReilly/darkware-zapret?style=flat&color=blue)](LICENSE)

** [Read in English](README.md)**

**Darkware Zapret** — GUI для [zapret](https://github.com/bol-van/zapret) на macOS. Обход блокировок YouTube, Discord и других сайтов.

![Darkware Zapret UI](assets/preview.png)

## Возможности

- **Нативный UI для macOS** — Чистый SwiftUI интерфейс в меню-баре
- **Включение в один клик** — Моментальное включение/выключение обхода
- **Несколько стратегий** — Переключение между методами обхода
- **Автозапуск** — Запускается автоматически при старте системы
- **Авто-хостлист** — Автоматически определяет заблокированные домены

## Установка

1. Скачай [`DarkwareZapret_Installer.dmg`](https://github.com/RoninReilly/darkware-zapret/releases/latest)
2. Открой DMG, перетащи приложение в **Applications**
3. Запусти приложение
4. Нажми **Install Service** (потребуется пароль админа один раз)
5. Включи переключатель

> **Если видишь ошибку "Приложение повреждено"**, выполни в Терминале:
> ```bash
> xattr -cr /Applications/"darkware zapret.app"
> ```

## Стратегии

| Стратегия | Описание | Для чего |
|-----------|----------|----------|
| **Split+Disorder** | Разбиение TCP с переупорядочиванием | YouTube, большинство сайтов |
| **TLSRec+Split** | TLS record + TCP разбиение | Discord, Telegram |
| **TLSRec MidSLD** | TLS record на границе домена | Некоторые провайдеры |
| **TLSRec+OOB** | TLS record + OOB байт | Крайний случай |

## Как это работает

Приложение использует `tpws` прозрачный прокси для модификации исходящего TCP трафика, обходя DPI (Deep Packet Inspection) фильтры провайдера. Трафик перенаправляется через правила PF файрвола macOS.

## Что работает

- ✅ YouTube
- ✅ Discord (веб + клиент)
- ✅ Другие заблокированные сайты из списка Re-filter

## Сборка из исходников

```bash
git clone https://github.com/RoninReilly/darkware-zapret.git
cd darkware-zapret
swift build -c release
./create_app.sh
```

Требуется macOS 13+ и Xcode Command Line Tools.

## Благодарности

- Основано на [zapret](https://github.com/bol-van/zapret) от bol-van
- Хостлист от [Re-filter](https://github.com/1andrevich/Re-filter-lists)

## Лицензия

MIT License
