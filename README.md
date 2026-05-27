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
