# Тимчасові посилання на скріншоти (Shotleaf)

Маленький сервіс: Shotleaf завантажує сюди скріншот і отримує коротке посилання, яке саме зникає за 1 / 6 / 24 години.
Один файл `shots.py`, лише Python 3 (без сторонніх бібліотек). Слухає `127.0.0.1:8787` (або адресу з `SHOTS_HOST`), назовні — через Cloudflare Tunnel.

Якщо `cloudflared` працює в Docker, він не бачить `127.0.0.1` сервера: додайте в `/etc/shotleaf-links.env` рядок
`SHOTS_HOST=<шлюз його docker-мережі>` (напр. `172.17.0.1`, див. `docker network inspect <мережа>`), а в тунелі вкажіть `http://172.17.0.1:8787`.

## Встановлення (на сервері)

```bash
sudo mkdir -p /opt/shotleaf-links
sudo cp shots.py /opt/shotleaf-links/
sudo cp shotleaf-links.service /etc/systemd/system/
```

Секретний ключ і адреса (ключ потім вставите в Shotleaf → Налаштування → Посилання):

```bash
echo "SHOTS_TOKEN=$(openssl rand -hex 24)" | sudo tee /etc/shotleaf-links.env
echo "SHOTS_PUBLIC_URL=https://shot.ВАШ-ДОМЕН" | sudo tee -a /etc/shotleaf-links.env
sudo chmod 600 /etc/shotleaf-links.env
sudo cat /etc/shotleaf-links.env
```

Запуск:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now shotleaf-links
systemctl status shotleaf-links --no-pager
```

## Cloudflare Tunnel

У конфіг тунелю (`/etc/cloudflared/config.yml` або в панелі Zero Trust → Tunnels → Public Hostname) додайте піддомен
**перед** правилом `- service: http_status:404`:

```yaml
  - hostname: shot.ВАШ-ДОМЕН
    service: http://localhost:8787
```

Якщо тунель налаштований через панель — додайте Public Hostname `shot` → `HTTP` → `localhost:8787`.
Для конфігу у файлі потрібен ще DNS-запис: `cloudflared tunnel route dns <назва-тунелю> shot.ВАШ-ДОМЕН`, потім `sudo systemctl restart cloudflared`.

## Перевірка

```bash
curl -s -X POST -H "Authorization: Bearer ВАШ_КЛЮЧ" --data-binary @якийсь.png "https://shot.ВАШ-ДОМЕН/upload?ttl=3600"
```

Відповідь — `{"url": "https://shot.ВАШ-ДОМЕН/abc…", "expires": …}`; посилання відкривається в браузері.

## Що він робить і чого не робить

- Приймає лише PNG/JPEG до 25 МБ і лише з правильним ключем.
- Посилання — 12 випадкових символів, вгадати не вийде; після терміну — 404, файл видаляється (перевірка щохвилини).
- Нічого не пише в лог, крім методу, шляху і коду відповіді (без IP).
