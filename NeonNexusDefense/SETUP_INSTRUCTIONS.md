# Neon Nexus Defense — инструкция по запуску в Roblox Studio

## Быстрый старт (один файл)

1. Откройте Roblox Studio → пустой Baseplate-проект.
2. **File → Import from File** и выберите `NeonNexusDefense.rbxlx`.
   Импорт создаст всю структуру скриптов:
   ```
   ReplicatedStorage
   └── Modules
       ├── Enemy/Enemy            (ModuleScript)
       ├── Projectile/Pool        (ModuleScript)
       ├── Projectile/Projectile  (ModuleScript)
       ├── Shared/Config          (ModuleScript)
       ├── Shared/Types           (ModuleScript)
       └── Tower/Tower            (ModuleScript)
   ServerScriptService
   └── Server
       ├── Main                   (Script — bootstrap, запускать его не нужно отдельно)
       ├── PathRuntime            (ModuleScript)
       └── WaveManager            (Script)
   StarterPlayerScripts
   └── Client
       ├── HudController          (LocalScript)
       └── PlacementUI            (LocalScript)
   ```
3. Альтернатива rbxmx: Rojo (`rojo build`/свои map-файлы) или ручной copy-paste `.lua`
   файлов из папок проекта в соответствующие объекты Explorer (имя объекта = имя файла без суффикса).

## Что нужно достроить руками (арт + карта) — 15 минут

### Workspace
- `Waypoints` (Folder): Part'ы `W1, W2, W3...` вдоль маршрута врагов (S-образный путь ~150 studs).
- `BuildGrid` (Folder): плоские Part'ы `Cell_1 ... Cell_40` в 2 слоя над землёй
  (Transparency 0.6, CanCollide false — raycast клиента должен их видеть).
- `Core` (Model с Part) — ядро базы на конце пути.
- `Runtime` — создавать НЕ надо, `Main` создаст сам (`EnemyPool`, `ProjectilePool`, `Towers`).

### ReplicatedStorage.Assets (Folder → подпапки)
- `Assets/Enemies`: модели `Runner`, `Golem`, `Drone`, `Boss`. Требование: внутри Part с именем
  `HumanoidRootPart` (это hitbox для spatial query).
- `Assets/Towers`: модели `Pulse`, `Mortar`, `Cryo`, `Railgun`. Требование: Part с именем `Muzzle`
  (точка вылета снаряда) + Anchor=true.
- `Assets/Projectiles/Bolt`: маленькая светящаяся модель (Part «Bullet» внутри).

### Game Settings
- Creator Products / Team Create по вкусу. Physical Animation — off (не нужен).

## Порядок запуска
1. Press Play. В Output должно появиться: `[NND] Server bootstrap complete`.
2. Сервер сам: создаёт Remotes, предрассчитывает путь, пулит 20 моделей врагов и 60 снарядов,
   даёт 5 секунд интермиссона → стартует Волна 1.
3. Клиент: внизу панель из 4 кнопок башен; клик по кнопке → наведение на `Cell_*` → ЛКМ = покупка.
   HUD слева: золото / волна / таймер / кнопка «⚡ START WAVE (+25g)».

## Как играть (balance quick-ref)
| Башня | Цена | Роль |
|---|---|---|
| Pulse | 100g | базовый DPS, таргет First |
| Mortar | 250g | AoE сплэш r=6, **не бьёт дронов** |
| Cryo | 180g | slow 45%/2с, приоритет Strongest |
| Railgun | 400g | hitscan 180 урона, range 34, pierce |

Враги: Runner (быстрый), Golem (танк, резист слоу 50%), Drone (летающий, +6 studs высоты),
Boss (каждая 10-я волна). Экономика: kill-gold × scaling(wave), бонус волны 50+10w, early call +25g.

## Известные «TODO» для продакшена (помечены в коде)
- `_G.NND_partRegistry` → заменить на DI через Main (архитектурная косметика).
- VFX: Beam для Railgun / explosion для Mortar через RemoteEvent `EnemyFX`.
- Healthbar над врагами (BillboardGui + атрибут `Health` уже пишется кодом).
- DataStore сохранение золота/волны между сессиями.
