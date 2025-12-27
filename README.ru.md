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

## Движки (Engines)

### tpws
Легковесный прозрачный TCP прокси. Лучший выбор для обычного веб-серфинга и обхода стандартных HTTP/HTTPS блокировок.
- **Протокол:** Только TCP
- **Режим:** Прозрачный прокси (Transparent Proxy)

### ciadpi (ByeDPI)
Продвинутый SOCKS5 прокси с **поддержкой UDP**.
- **Протокол:** TCP + UDP
- **Режим:** Системный SOCKS5 прокси (автонастройка)
- **Возможности:** Фейковые пакеты (Fake packets), проход UDP

## Стратегии

### Стратегии tpws
| Стратегия | Описание |
|-----------|----------|
| **Split+Disorder** | Разбивает TCP пакет в позиции 1 и середине домена (midsld). Отправляет второй фрагмент перед первым через `--disorder`. DPI ожидает упорядоченные пакеты и не может собрать hostname. |
| **TLSRec+Split** | Создаёт два TLS record, разбивая на границе SNI extension (`--tlsrec=sniext`). Плюс TCP split на позиции midsld и disorder. DPI видит неполный TLS handshake в первом record. |
| **TLSRec MidSLD** | Разбивает TLS record прямо посередине домена второго уровня (`--tlsrec=midsld`). Пример: `disco` + `rd.com`. DPI не может сматчить частичный домен со списком блокировок. |
| **TLSRec+OOB** | Всё вышеперечисленное плюс `--hostdot` — добавляет точку после hostname в HTTP Host header. Дополнительный слой путаницы для HTTP-level DPI. |

### Стратегии ciadpi
| Стратегия | Описание |
|-----------|----------|
| **Disorder (Simple)** | Разбивает поток TCP на первом байте (`-d 1`). Отправляет первый байт *после* остальной части пакета. Очень эффективно против большинства DPI. |
| **Disorder (SNI)** | Разбитие в позиции SNI. Более точный метод, чем простой disorder. |
| **Fake (OOB)** | Инъекция OOB (Out-of-Band) данных. Эффективный метод, запутывающий DPI без использования манипуляций с TTL. |
| **Auto (Torst)** | Автоматически определяет тип блокировки методом `torst` и применяет лучший метод обхода. |

## Как это работает

Приложение использует `tpws` (прозрачный прокси) или `ciadpi` (SOCKS5) для модификации исходящего трафика, обходя DPI фильтры. TCP трафик перенаправляется через правила PF файрвола, а UDP маршрутизируется через системный SOCKS прокси (в режиме ciadpi).

## Что работает

- ✅ YouTube
- ✅ Discord (веб + клиент)
- ✅ Другие заблокированные сайты из списка Re-filter

## Сборка из исходников

```bash
git clone https://github.com/RoninReilly/darkware-zapret.git
cd darkware-zapret
cd darkware-zapret
# Компиляция TPWS
cd zapret_src/tpws && make mac && cd ../..
# Сборка приложения
swift build -c release
./create_app.sh
```

Требуется macOS 13+ и Xcode Command Line Tools.

## Благодарности

- Основано на [zapret](https://github.com/bol-van/zapret) от bol-van
- Хостлист от [Re-filter](https://github.com/1andrevich/Re-filter-lists)

## Поддержать разработку

Для того чтобы приложение работало "из коробки" (без ошибок "файл поврежден" и команд в терминале), необходим сертификат Apple Developer Program ($99/год).

Если вы хотите помочь с покупкой сертификата:

- **Solana (SOL):** `2CP3BLyPSjiKYcr6j17UJ35FmmBdvVWkWwESqaeuqMCu`
- **ETH / Polygon:** `0x8aa4a9784995C8f558A46CdB604C7440d0506044`

## Лицензия

MIT License
