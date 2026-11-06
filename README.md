# vps-watch

Мониторинг VPN-сервера (Amnezia) с алертами в Telegram. Почти не нагружает сервер: никаких агентов, только cron раз в минуту и один `curl`, висящий в long polling.

| Что случилось | Кто сообщит |
|---|---|
| Упал VPN-контейнер, кончается память, хостер отжимает CPU, тормозит диск | бот на сервере |
| Сервер умер, завис, пропала сеть у хостера | GitHub Actions (этот репозиторий) |
| Сервер жив, но из РФ не пускает (блокировка, DPI) | никто — снаружи РФ это не видно |

## 1. Бот

1. В @BotFather создай бота, получи токен.
2. Создай группу, добавь туда бота (и друзей), напиши в группе `/start@имя_бота`.
3. Узнай ID группы (отрицательное число):
   ```bash
   curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | grep -o '"chat":{"id":-*[0-9]*'
   ```
4. В @BotFather → `/setcommands` → `server_info - состояние сервера`.

## 2. Сервер

Одна команда по ssh от root:

```bash
curl -fsSL https://raw.githubusercontent.com/passha228/vps-watch/main/server/install.sh | TOKEN=123:ABC CHAT=-100123 bash
```

Должно прийти «✅ Мониторинг установлен». Несколько чатов — через пробел: `CHAT="111 -100222"`.
Обновить скрипты без смены настроек — та же команда без `TOKEN`/`CHAT`. Настройки лежат в `/etc/vpswatch.conf`.

Что ставится:
- `vps-status` — состояние сервера в консоли;
- `/server_info` в Telegram — то же самое (сервис `vps-bot`);
- cron `/etc/cron.d/vps-watch` — алерты при проблеме и при восстановлении;
- `sysstat` — история метрик: `sar -u` (смотри `%steal`), `sar -r`, `sar -n DEV`;
- снимается запрет ping, который ставит Amnezia.

## 3. Внешний сторож (GitHub Actions)

Settings → Secrets and variables → Actions → New repository secret:

| Секрет | Значение |
|---|---|
| `IP` | IP сервера |
| `TOKEN` | токен бота |
| `CHAT` | ID группы (можно несколько через пробел) |
| `PORT` | необязательно, по умолчанию `22` |

Затем Actions → watch → **Run workflow**. Зелёный запуск — всё работает.

Ограничения: GitHub может задерживать cron на 5–15 минут; пока сервер лежит, алерт приходит каждые 5 минут; через 60 дней без коммитов GitHub отключает расписание — нужно нажать Enable в Actions или сделать любой коммит.

## Отладка

```bash
vps-status                      # состояние
journalctl -u vps-bot -n 30     # почему бот не отвечает
grep vps-watch /var/log/syslog  # работает ли cron
```
