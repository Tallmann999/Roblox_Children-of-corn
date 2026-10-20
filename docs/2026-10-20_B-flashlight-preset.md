# B: параметры фонаря как в принятой A

Автор подтвердил работу A после сброса и открыл B. Через MCP проверена именно
Children_of_corn_B.rbxl d60cd14a-5aa8-499b-acaf-9f8f49a641bc. В первоначальном B Play
уже сохранились ручное игровое качество10, render Level21 и LightingStyle.Realistic.
Новое переключение графики не потребовалось. Старый банк B был2/100/32 и13/30/4,
наклон−4°; он заменён постоянными значениями из принятой A:

| Параметр | Широкий пучок | Центральный пучок |
|---|---:|---:|
| Яркость | 2.08 | 22.62 |
| Угол | 78° | 12° |
| Дальность | 18 | 24 |

Наклон−6°. Цвет/Front/Enabled/noShadows, camera FOV70, плавное движение/ЛКМ прежние.
Изменены только шесть свойств двух SpotLight и один атрибут Pitch существующего
ReplicatedStorage.CornFlashlightSettings. Все156Sources точны, в том числе
CornAppearance.DetailedHeight10, четыре формы кукурузы/LOD, старый B Warden,
тёмный сарай и остальной мир. A не изменялась.

## Проверка и сохранение

Guarded install-B-flashlight-preset.luau проверяет156пинованных Source SHA256,
остановленный owned Corn B/630world/полный известный старый либо новый банк.
Native7changedProperties, repeat0, afterPlay0. Rollback возвращает все7значений
при ошибке записи. Неизвестные/частичные ручные состояния не затираются.

Два новых нормальных bootstrap Stop/Play сохранили Manual10/Level21/Realistic без
вызовов setter качества. Во втором production Start вызван программно; фонарь
сам прочитал новый preset.30render samples вперёд и вниз−75° ON/owned и с точными
значениями. Camera/focus/cursor временно подготовлены диагностикой; Root и ввод
мыши/клавиатуры не управлялись. Измерена конфигурация DetailedHeight10.
Observer и render binding удалены до Stop; финал Edit/CameraFixed/156Sources,
Httpfalse/no diagnostics. Это не новая человеческая приёмка внешнего вида B,
полного выхода/открытия процесса Studio, долгого FPS или страха.

B сохранён1494878байт/SHA256
`f33571e819fb605130b05489789c93f11c0ef92a3e9762c77691130a60c3d9c0`.
Штатная AutoRecovery движка16:33:21 проверена read-only до атомарного переноса
точных байтов в основной B. Verify-B-flashlight-preset.py допускает только шесть
нужных float32, точную замену сериализованного double Pitch−4→−6 и узкие конечные
Camera/FilteredSelection данные редактора.4532instances/156Sources, исходные
идентичности/родители/классы/мир/арт/остальной Lighting/rawTerrain сохранены точно.
Сцена не пересериализована Lune/Python; управление окнами не применялось.

A1491827/`c1f054029ca729f314889ce7874c17c6e5f772cb20541a9c0ceedd796f3446b7`
проверена неизменной. В проекте остались только два loose файла сцен A/B.
Новый B baseline8160… хранится в before-preset.zip внутри evidence, SHA256
`81eef324002c87ce769538f444e288db55c238ed067bfa48b8dad6006afa967b`;
старый общий архив неизменён. Для проверки временная baseline копия извлекается
вне проекта и удаляется по окончании; новые scene файлы в place/build не оставляются.
Production Sources не менялись, check.ps1 не повторялся и build-scena не создавалась.

Доказательства: .artifacts/playtests/2026-10-20-B-flashlight-preset/
{native-install,native-acceptance,recovery-preservation,preservation,saved-scenes}.json.
Текущий settings guard: scripts/install-B-flashlight-preset.luau; saved-copy guard:
scripts/verify-B-flashlight-preset.py. Старые tall/A pipelines ожидают прежние
bank/соседние хэши и не должны запускаться поверх нового preset без нового аудита.
