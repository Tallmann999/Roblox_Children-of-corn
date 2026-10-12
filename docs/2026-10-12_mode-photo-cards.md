# Фотокарточки режимов

Дата: 2026-10-12. Клиентский UI local solo PC. Контракт уже зафиксирован в architecture до изменения RoundHud: изображения настоящего renderer с одной controlled camera, easy/day с зелёной кукурузой, medium/dusk и hard/night с сухой. Source images и camera/GUI restoration фиксирует root. Никакой новой искусственной ViewportFrame-сцены, world cloning или правила раунда.

ModePreviewImages должен содержать три разные непустые Image URI. RoundHud создаёт по одному LightingPreview ImageLabel на easy/medium/hard, ScaleType=Crop. Карточки режима сохраняют название/описание/Select; ready и результат позволяют выбрать режим, active/preparing/caught скрывают ряд. Общая карточка780×530 масштабируется относительно usable viewport, 18px минимальный margin с каждой стороны.

`tests/studio-mode-photo-cards.luau` проверяет актуальный GUI: URI/asset loading, три ImageLabel и отсутствие ViewportFrame/WorldModel, четыре вертикальных диапазона режима без overlap, все phases и controlled choice states, disabled busy/unavailable, общий layout/nooverlap, Crop aspect и cleanup. Viewports1400×800,800×600 и640×480 передаются текущему _fitCard как simulated usable AbsoluteSize; физических размеров окна тест не меняет. URI placeholder не считается PASS. Визуальные screenshots и реальное нажатие Select проверяются root отдельно; fixture не подменяет выбор пользовательским вводом.

Source/UI/world не изменяются данным review; его результат и engine acceptance фиксируются после заполнения и загрузки реальных фото.
