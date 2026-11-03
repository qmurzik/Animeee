# Проверка AnimeApp 0.3.0 (21)

Дата: 2026-11-03.

IPA: https://github.com/qmurzik/Animeee/releases/download/build-21/AnimeApp-unsigned.ipa
CI: https://github.com/qmurzik/Animeee/actions/runs/41627467414
Исходный код сборки: https://github.com/qmurzik/Animeee/tree/build-21

## Подтверждено

- Xcode собрал приложение для физического iPhone ARM64 с минимальной iOS 18.0, без подписи.
- После скачивания IPA проверены ZIP, ARM64, CFBundleShortVersionString 0.3.0, CFBundleVersion 21 и @executable_path/Frameworks. MobileVLCKit вложена в приложение.
- SHA256 IPA: 17ecb294d8d62457d57b84843023f62f9d14af5af7e018ebce38ff142f85ce32.
- Пять сетевых контрактных проверок прошли: AniLibria, AniSkip, соответствие MAL ID и озвучки YummyAnime, MPD Aksor, MP4 CVH.
- Приложение собрано и запущено на iOS Simulator. Снимок главной: https://github.com/qmurzik/Animeee/releases/download/build-21/home.png
- На симуляторе для тестового Aksor/DASH подтверждены player.hasVideoOut и время 2.07 секунды. Снимок: https://github.com/qmurzik/Animeee/releases/download/build-21/player-aksor.png
- На симуляторе для тестового CVH/MP4 подтверждены player.hasVideoOut и время 2.66 секунды. Снимок: https://github.com/qmurzik/Animeee/releases/download/build-21/player-cvh.png
- Debug-маршруты проверок исключены из Release IPA. Проверка использует те же сетевые адаптеры и движок, что обычный просмотр.

## Пределы проверки

Проверка первых кадров не доказывает просмотр всей серии, отсутствие обрывов или доступность каждого тайтла/озвучки. На физическом iPhone XS приложение, производительность, нагрев, память, PiP и AirPlay не проверялись. Для установки IPA нужна собственная подпись. Swift unit-тестов пока нет; сетевые контракты и проверка симулятора не называются unit-тестами.

Известные ограничения: нет автоматического восстановления путём переключения на другой источник при ошибке, офлайн-загрузок, AniList-синхронизации, расписания и полной поддержки расширенных функций плеера. Другие балансеры YummyAnime, кроме поддерживаемых Aksor и CVH, исключены из списка нативных вариантов. Доступность и состав переводов определяет источник; региональные ограничения и DRM не обходятся.
