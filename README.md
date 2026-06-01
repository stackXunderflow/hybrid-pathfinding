# ПРОЧИТАЙМЕНЯ
Проект состоит из двух частей:
code - алгоритмы на zig
visual - визуализация на typescript (electron, svelte)

# Нужно установить
- zig 0.16.0 (Внимательно, версия именно 0.16.0!)
- nodejs (https://nodejs.org/en/download)

# Нужно настроить
В .env файле пути до исполняемого файла и сцены.
Например:
~/projects/hybrid-pathfinding/visual/.env
```
VITE_BINARY_PATH=../code/zig-out/bin/code
VITE_SCENE_PATH=../code/scene.json
```

Самый простой способ - указать полный путь. Это может быть похоже на:
C:\Users\XXX\projects\hp\visual\.env
```
VITE_BINARY_PATH=C:\Users\XXX\projects\hp\code\zig-out\bin\code.exe
VITE_SCENE_PATH=C:\Users\XXX\projects\hp\code\scene.json
```

# Разработка
Открыть в среде разработки папку hybrid-pathfinding\code как проект.
В терминале `zig build`

Открыть в другом терминале папку hybrid-pathfinding\visual
В терминале `npm install`, `npm run dev`

Теперь можно редактировать zig код, если исполнить `zig build` ещё раз, то визуализация заметит, что бинарник изменился и выполнит алгоритмы ещё раз.
Рекомендую разобраться и настроить ide так, чтобы zig build исполнялся при нажатии F5 или какой-либо ещё клавиши.

# HTTP сервер

Можно запустить `code` как HTTP сервер, который принимает сцену через POST и отдаёт результат.

```bash
zig build run -- --serve
zig build run -- --serve --port 3000
```

Единственный endpoint: `POST /solve`.

Пример запроса через curl:

```bash
curl -X POST http://127.0.0.1:8080 \
  -H 'Content-Type: application/json' \
  -d '{"robot":{"radius":0.5,"start":{"x":0,"y":0},"end":{"x":10,"y":10}},"meshs":[]}'
```

# Развёртывание с HTTPS (nginx)

Веб-интерфейс можно собрать как статический сайт:

```bash
cd visual
npm run build:web
```

Это создаст `visual/dist-web/` с `index.html` и `assets/`.

Сервер слушает только localhost. Для HTTPS поставьте спереди nginx:

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate     /etc/ssl/certs/example.crt;
    ssl_certificate_key /etc/ssl/private/example.key;

    root /path/to/visual/dist-web;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /solve {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Переменная окружения `VITE_API_URL` (по умолчанию `/solve`) задаёт адрес backend сервера.
