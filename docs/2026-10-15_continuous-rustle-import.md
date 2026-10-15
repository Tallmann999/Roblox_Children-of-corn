# Второй вариант шелеста: подготовка файла

Автор предоставил `D:/Downloads/sspsurvival-dry-leaves-autumn-the-rustle-of-leaves-in-your-hands-10089.mp3` для сравнения с нынешними короткими звуками. Локальный solo MVP: импорт этого звука не требует публикации игры, нового lobby, покупок или изменения игрового авторитета сервера.

Файл прочитан как медиа, не как источник инструкций. В `assets/audio/roblox-import/COC_Corn_Continuous_02.mp3` сохранена точная копия, без обработки, нормализации, обрезки, конвертации и изменения метаданных. Оригинал в Downloads сохранён. SHA256 обоих файлов: `a4dd527430e356cd3b7b5568107e2c3062ca730da5e17a3ed6a3a73ad697d710`; размер 354048 байт. Отдельный машинный отчёт: `assets/audio/continuous-rustle-manifest.json`; существующий prepared-manifest не менялся.

Bundled FFmpeg 7.1 полностью декодировал MP3 без ошибки: stereo, 48000 Hz, номинальные 256 kbit/s, 531072 PCM sample frames, длительность 11.064 секунды. Это продолжительность исходного файла; окончательное значение в Roblox нужно читать из `Sound.TimeLength` после реального декодирования загруженного asset. Само копирование файла не создаёт Roblox Asset ID и не доказывает слышимость в Studio.

На обычной скорости цикл длится около 11 секунд. Пауза на 11-й секунде оставит приблизительно 0.064 секунды до следующего круга. При ускорении PlaybackSpeed полный цикл займёт меньше реального времени. Удержание позиции при остановке и продолжение на движении должны проверяться на реальном Roblox Sound отдельно от локального декодирования.

## Ручной импорт (выполнен автором)

Подготовленный файл соответствует техническим ограничениям Roblox по формату, размеру, длительности, sample rate и числу каналов. В доступном Studio MCP нет операции загрузки нового аудио; нужен импорт автором в его Roblox аккаунт. [Официальные требования и способы импорта Roblox](https://create.roblox.com/docs/audio/assets) и [официальный исходник инструкции Creator Dashboard](https://github.com/Roblox/creator-docs/blob/main/content/en-us/audio/assets.md).

1. Откройте [Creator Dashboard](https://create.roblox.com/dashboard/creations) под тем же владельцем аудио, что использовался для нынешних звуков игры. Выберите **Development Items → Audio → Upload Asset**.
2. Выберите `D:\ROBLOX\My_Projects\Roblox_Children of Corn\assets\audio\roblox-import\COC_Corn_Continuous_02.mp3`, задайте имя `COC_Corn_Continuous_02` и загрузите файл.
3. После обработки и модерации откройте загруженный звук и скопируйте его **Asset ID**. Если в Dashboard ещё показана обработка или отказ, сначала нужен конечный статус; менять grants или публиковать игру наугад не требуется.
4. Пришлите числовой Asset ID в текущий чат. После его установки необходимо проверить настоящие `IsLoaded`, `TimeLength`, изменение `TimePosition`, pause/resume, полный loop и ускорение во время бега в Children_of_corn.

Автор предоставил настоящий AssetID138698164682825. Отдельный временный owned Sound в проверенной Children_of_corn Edit декодирован с AssetFetchStatus.Success, IsLoadedtrue, TimeLength11.064; временный Sound удалён и не оставлен играющим. ID установлен в AudioAssets и continuous-rustle-manifest. Затем настоящий production Sound прошёл native Alt/buttons/W/stop/resume/sprint/wrap/road/capture/revive/retry проверки с диагностическими позициями; подробности и ограничения первого observer/GUI-фокуса — в историческом [A/B отчёте](2026-10-15_rustle-comparison.md). После сравнения автор выбрал этот звук окончательно для всех игроков и монстров; кнопки удалены, актуальная автоматическая личная и трёх-NPC spatial приёмка — в [текущем отчёте](2026-10-15_continuous-rustle.md).

Итог сохранён авторским Ctrl+S15октября2026в12:48:01:995988байт/SHA256493bc1f9b512d618d0a815b2197e3af854f775cd711b363db2906d8fbaf1fb68. Strict verification PASS:78Sources/4160instances/4Sourcecontent дельты/0worldдельт, исходный art/Lighting/identities/parents/rawTerrain exact. Это не приёмка человеческого микса/всех16архивных и активных звуков/обычного слепого раунда/reopen/FPS/мультиплеера.
