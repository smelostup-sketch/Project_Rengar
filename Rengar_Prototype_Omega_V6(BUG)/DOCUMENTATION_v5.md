# Rengar Prototype — версия v5

**Автор:** Manus AI  
**Версия:** v5  
**Проект:** `Rengar_Prototype_Omega_AnimationTracks`  
**Главная сцена:** `res://Актуально_22.08.26.tscn`  
**Движок:** Godot 4.3

## Назначение версии

Версия v5 расширяет стабильную Omega-сборку парным оружием, функциональным блоком противника, гибкими параметрами скорости, экранной диагностической строкой и локальной текстурой травы. Существующая компонентная архитектура сохранена: `CombatComponent` владеет уроном и hitbox, animation-компоненты владеют проигрыванием клипов, `StateComponent` владеет обычным движением и отдельными mobility-действиями, а `EnemyController` владеет поведением врага.

## Общая нумерация

Начиная с этой версии архивы получают единый порядковый номер во всех названиях. Эта сборка является **v5**, поэтому имя архива имеет формат `Rengar_Prototype_v5_...`. Следующая версия должна использовать `v6`, независимо от того, будет ли это исправление, новая механика или расширение визуала.

## Парное оружие

У каждого персонажа теперь два заранее созданных оружия. Правый клинок использует существующие узлы `PlayerWeaponAttachment` или `EnemyWeaponAttachment`, а левый клинок добавлен в `PlayerLeftWeaponAttachment` или `EnemyLeftWeaponAttachment`. Оба attachment используют внешний `Skeleton3D` соответствующей модели и кость Mixamo `mixamorig_RightHand` либо `mixamorig_LeftHand`.

```text
PLayerCharacterBody3D
├── PlayerWeaponAttachment                  BoneAttachment3D → VisualModel/Skeleton3D/mixamorig_RightHand
│   └── Sword
│       └── WeaponHitbox                     Area3D, collision_mask = 6
│           └── CollisionShape3D
└── PlayerLeftWeaponAttachment              BoneAttachment3D → VisualModel/Skeleton3D/mixamorig_LeftHand
    └── Sword
        └── WeaponHitbox                     Area3D, collision_mask = 6
            └── CollisionShape3D

EnemyCharacterBody3D
├── EnemyWeaponAttachment                   BoneAttachment3D → EnemyVisual/Skeleton3D/mixamorig_RightHand
│   └── Sword
│       └── WeaponHitbox                     Area3D, collision_mask = 1
│           └── CollisionShape3D
└── EnemyLeftWeaponAttachment               BoneAttachment3D → EnemyVisual/Skeleton3D/mixamorig_LeftHand
    └── Sword
        └── WeaponHitbox                     Area3D, collision_mask = 1
            └── CollisionShape3D
```

Каждый `WeaponHitbox` существует в сцене заранее и исходно выключен. `CombatComponent.animation_enable_weapon_hitbox()` выбирает правую Area3D для `RIGHT`, левую Area3D для `LEFT` и обе Area3D для `UP`. Само создание Area3D во время атаки запрещено. Call Method Track остаётся единственным штатным источником включения и выключения оружия; отмены атаки используют только аварийное безопасное выключение.

## Блок противника

В `CombatComponent` добавлена отдельная группа настроек `Enemy Block`. Параметр `enemy_block_enabled` включает механику, а `enemy_block_duration` задаёт длительность защитного окна. `EnemyUtilityAIComponent` выбирает `HOLD` при свежей атаке игрока и передаёт направление в `CombatComponent.activate_enemy_block()`.

Направления зеркальны атаке. Защита `RIGHT` блокирует атаку игрока `LEFT`, защита `LEFT` блокирует `RIGHT`, а защита `UP` блокирует `UP`. `EnemyController.is_blocking_active()` предоставляет тот же публичный контракт, который уже использует player hitbox. При блоке урон не проходит, игрок получает событие `blocked`, а enemy hitbox не затрагивается.

Визуальный `StateLabel` врага показывает щит на время активной защиты. Блок не смешан с input игрока и не изменяет правила dash/dodge.

## Скорости

Скорость обычного движения и скорость обычной/боевой анимации разделены от dash и dodge.

| Параметр | Где находится | Назначение |
|---|---|---|
| `character_speed_multiplier` | `Player3d`, `EnemyController` | Общий множитель обычного движения и движения-анимации персонажа. |
| `movement_speed_multiplier` | `StateComponent` | Применяется только к обычному X/Z движению; ветви `is_dodging` и `is_dashing` обходят этот множитель. |
| `movement_animation_speed` | `MixamoAnimationComponent`, `EnemyAnimationComponent` | Скорость Idle/Run и других обычных циклов. |
| `attack_animation_speed` | `Player3d`, `EnemyController`, animation-компоненты | Общий множитель для `AttackLeft`, `AttackRight` и `AttackUp`. Это единый параметр для будущих бонусов. |
| `dodge_speed`, `dash_speed` | `StateComponent` | Не изменяются параметрами v5. |

Базовое значение всех новых множителей равно `1.0`. Значение `2.0` означает вдвое более быстрое обычное движение либо атаку. Значение `0.5` означает половинную скорость. Для атак длительность внутреннего fallback-таймера делится на `attack_animation_speed`, поэтому визуальное окончание и логическое ожидание клипа остаются согласованными.

## Экранная отладка

`PlayerUI` создаёт `DebugInputLine` как обычный экранный `Label` в нижней правой части viewport. Строка обновляется каждый кадр и дублирует ключевые данные `CombatDebugVisualizer`:

```text
DEBUG INPUT: <FSM state> | dir: <UP/LEFT/RIGHT/—> | mouse: (<x>, <y>)
```

Отладочную строку можно выключить параметром `PlayerUI.debug_line_enabled`. Трёхмерные лучи по-прежнему переключаются клавишей F3 независимо от экранной строки.

## Текстура травы

Присланный пользователем файл сохранён локально как `res://Assets/grass_texture.png` и назначен `albedo_texture` материала `StandardMaterial3D_0a3ws`, используемого `Bush/BushMarker`. Внешние ссылки на файл не используются. Исходная текстура не редактировалась.

## Важные ограничения для будущих агентов

Не переносить боевую логику в `EnemyUtilityAIComponent`: этот компонент только выбирает намерение и направление. Не создавать новые Area3D при атаке. При изменении оружия сохранять прямую сценическую иерархию attachment → Sword → WeaponHitbox и проверять оба attachment в `CombatComponent._ready()`.

Общие бонусы скорости должны менять `character_speed_multiplier` или `attack_animation_speed`, но не `dash_speed`, `dodge_speed`, `dash_duration` и `dodge_duration`, если это не станет отдельным согласованным запросом. `attack_animation_speed` является единым параметром для всех трёх направлений атаки.

Профили Utility AI и память между сессиями остаются отдельной системой. Если создаётся новый тип врага, необходимо задать уникальный `EnemyMemoryComponent.profile_id`, чтобы статистика разных архетипов не смешивалась.

## Проверка версии v5

Перед упаковкой выполнены чистый импорт Godot 4.3 и функциональный smoke-тест. Проверены наличие двух статических hitbox у каждого персонажа, наличие `DebugInputLine`, назначение текстуры, экспорт новых параметров скорости, блок `RIGHT` против player-атаки `LEFT`, отмена атаки по блоку и успешное прохождение обычной player-атаки `RIGHT` по врагу через статический hitbox.

Ожидаемые ключевые события боевого лога имеют следующий вид:

```text
ENEMY_BLOCK_ACTIVATED | dir=RIGHT
WEAPON_HITBOX_ENABLED | owner=PLayerCharacterBody3D | dir=LEFT | count=1
HITBOX_CONTACT | kind=block
ATTACK_CANCELLED | reason=blocked
WEAPON_HITBOX_ENABLED | owner=PLayerCharacterBody3D | dir=RIGHT | count=1
HITBOX_CONTACT | kind=target | node=EnemyCharacterBody3D
ATTACK_CANCELLED | reason=hit_confirm
QA_RESULT=PASS
```

В headless dummy-renderer Godot может вывести сообщения `mesh_get_surface_count` при завершении процесса из-за отсутствующего графического backend. Они не являются ошибками GDScript, не относятся к боевой логике и не должны интерпретироваться как failure, если `QA_RESULT=PASS`.
