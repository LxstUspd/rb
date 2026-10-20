# Neon Nexus Defense (Roblox Tower Defense)

Полный проект киберпанк Tower Defense для Roblox Studio на Luau (--!strict).

## Быстрый старт
1. Откройте Roblox Studio → пустой Baseplate-проект.
2. **File → Import from File** → выберите [`NeonNexusDefense/NeonNexusDefense.rbxmx`](NeonNexusDefense/NeonNexusDefense.rbxmx).
   Импорт создаст все скрипты в ReplicatedStorage / ServerScriptService / StarterPlayerScripts.
3. Достройте карту и архетипы по инструкции: [`NeonNexusDefense/SETUP_INSTRUCTIONS.md`](NeonNexusDefense/SETUP_INSTRUCTIONS.md).
4. Нажмите Play — сервер залогинит `[NND] Server bootstrap complete`, волна 1 начнётся через 5 секунд.

## Структура
| Путь | Содержимое |
|---|---|
| `NeonNexusDefense/Docs/GDD.md` | Геймдизайн-документ: башни, враги, экономика, волны, баланс |
| `NeonNexusDefense/Docs/ARCHITECTURE.md` | Архитектура: ООП-модули, RemoteEvents, репликация |
| `NeonNexusDefense/NeonNexusDefense.rbxmx` | Единый файл импорта в Studio (все скрипты) |
| `NeonNexusDefense.zip` | Архив всего проекта |
| `NeonNexusDefense/**` | Исходники .lua по папкам сервисов |

## Технологии
- Object Pooling снарядов и врагов, spatial query `GetPartBoundsInRadius` вместо Region3
- Таргетинг First/Last/Strongest/Weakest, hitscan-снайпер, AoE с предикцией, slow-стаки
- WaveManager с процедурными волнами, early-call бонусом, interest-экономикой
