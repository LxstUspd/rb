# Архитектура проекта Neon Nexus Defense

## Структура Explorer (Roblox Studio)

```
game
├── ReplicatedStorage
│   ├── Remotes                       (Folder)
│   │   ├── TowerActions              RemoteEvent  C→S: buy / upgrade / sell / setTargetMode
│   │   ├── WaveEvents                RemoteEvent  S→C: waveStarted, waveCompleted, countdown
│   │   ├── EconomyUpdate             RemoteEvent  S→C: золото игрока (только владельцу!)
│   │   ├── EnemyService? -> EnemyFX  RemoteEvent  S→All: spawn/despawn/criticalHit (визуал)
│   │   └── RequestWaveStart          RemoteFunction C→S: early call (валидация на сервере)
│   ├── Modules
│   │   ├── Shared
│   │   │   ├── Config.lua            все числа баланса, типизированные таблицы
│   │   │   ├── Types.lua             export type EnemyKind, TowerKind, TargetMode...
│   │   │   └── Signal.lua            лёгкий own-event (быстрее BindableEvent)
│   │   ├── Enemy/Enemy.lua           ООП-класс врага (метатаблица __index), waypoint-движение
│   │   ├── Tower/Tower.lua           ООП-класс башни (таргетинг через GetPartBoundsInRadius)
│   │   └── Projectile/Projectile.lua + Pool.lua (generic object pool)
│   └── Assets (Models башен/врагов — архетипы для клонирования из пула)
├── ServerScriptService
│   └── Server
│       ├── Main.server.lua           bootstrap: строит ремоты, запускает системы
│       ├── WaveManager.server.lua    генератор волн + спавн + награды
│       ├── EconomyManager.server.lua золото за киллы/бонусы, списания, анти-cheat проверки
│       └── PathRuntime.server.lua    читает workspace.Waypoints в массив CFrame (один раз)
├── StarterPlayerScripts (LocalScripts)
│   ├── Client/Main.client.lua        роутинг UI ↔ remotes
│   ├── Client/PlacementUI.client.lua выбор клетки, призрак башни, отправка TowerActions
│   └── Client/HudController.client.lua gold, HP ядра, полоски HP врагов (BillboardGui)
├── StarterGui  (ScreenGui с Frame'ами; UI-логику пишут LocalScript'ы из StarterPlayerScripts)
└── Workspace
    ├── Waypoints (Folder c Part-ами W1..Wn — только редактор карты, не реплицируется динамически)
    ├── BuildGrid (Parts-плитки с Attribute "CellId")
    ├── Core (Part ядра, Attribute HP)
    └── Runtime (Folder: активные Enemy-, Tower-, Projectile- модели; CollectionService tag "Enemy")
```

## Принципы

1. **ModuleScripts + метатаблицы (`__index`)** — классы `Tower`, `Enemy`, `Projectile` создаются
   фабриками `Class.new(...)`, живут на сервере как логика; их Model-представления реплицируются.
2. **Серверный авторитет.** Клиент лишь отправляет намерения ("хочу башню X в клетку Y").
   Сервер валидирует: клетка свободна, золото достаточно, позиция в сетке, rate-limit.
3. **EconomyUpdate шлёт золото только конкретному игроку** (`FireClient`), а не FireAllClients.
4. **Пулинг:** `Pool.lua` хранит освобождённые модели врагов/снарядов; `Get()` переиспользует,
   `Release()` прячет в карман-хранилище ниже карты вместо Destroy (избегаем GC/Instance.new spikes).
5. **Spatial Query:** башни на тике 10 Гц делают один `GetPartBoundsInRadius(origin, range,
   overlapParams)`; OverlapParams ограничивается группой `{"Enemies"}` и Default+DetailCollidable.
6. **Движение:** статические waypoints → предрассчитанный массив позиций + накопленный
   distance; враг хранит `travelledDistance`, позиция = LUT-бинарный поиск сегмента. Никакого
   PathfindingService (нужен был бы при мазе/динамическом пути — тогда `PathfindingService:CreatePath`
   с `AgentParams` и модификатором `Avoidance`, но для TD-пути это overkill и лаг).
