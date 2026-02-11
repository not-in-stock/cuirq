# cuirq File Manager — TODO

## Колонки Миллера
- [x] Базовая реализация Miller columns view
- [x] Переключение между list/grid/columns view modes
- [x] Навигация по колонкам (клик на директорию открывает колонку справа)
- [x] Scroll и resize колонок

## Async-навигация (отдельная ветка)
- [ ] Адаптивный порог: sync для малых директорий, future для больших (>1000 файлов)
- [ ] Virtual threads (Loom) для future executor

## Персистентность настроек
- [ ] Глобальное сохранение view mode и сортировки между сессиями
- [ ] Per-directory override (view mode, сортировка)
- [ ] Хранилище: централизованное (sqlite/json в ~/.config/cuirq), не .DS_Store в каждой папке
- [ ] Количество items для директорий в колонке Size

## На будущее
- [ ] Resizable sidebar
- [ ] Длинные breadcrumbs
- [ ] Drag'n'drop в избранное
- [ ] Паддинги в grid без обрезки
- [ ] Системный акцентный цвет
- [ ] Контекстное меню
- [ ] jextract для PanamaBridge.java
