# Исследование подключения YummyAnime

Проблема старой версии: каталог начинался с AniLibria, а YummyAnime использовался только как источник совпадений по MAL ID. Это исключало тайтлы, которых в AniLibria не было. Теперь каталог, поиск, карточки и видео используют непосредственно YummyAnime ID. Положительные локальные ID сохраняют старую маршрутизацию AniLibria, отрицательные представляют YummyAnime. Авторизация и охват каталога являются разными вопросами: публичные тайтлы доступны без входа.

Изученные исходники YummyTV:

- https://github.com/Helandy/YummyTV/blob/main/docs/network-and-auth.md
- https://github.com/Helandy/YummyTV/blob/main/docs/yani-api.md
- https://github.com/Helandy/YummyTV/blob/main/feature/account/data/src/main/kotlin/su/afk/yummy/tv/data/account/network/YaniAccountApi.kt
- https://github.com/Helandy/YummyTV/blob/main/feature/account/data/src/main/kotlin/su/afk/yummy/tv/data/account/repository/YaniAccountRepository.kt
- https://github.com/yummyanime/yummy-lampa-plugin/blob/main/src/auth.js

YummyTV использует POST /profile/login (login, password, need_json, необязательная recaptcha_response), GET /profile для проверки сессии, GET /profile/token и POST /profile/logout. Авторизация — Bearer token только на API-хост. Приложение не заимствует закрытый application key YummyTV, не обходит капчу или права доступа. На проверенных публичных запросах X-Application не потребовался; работоспособность входа для реального аккаунта без такого заголовка требует ручной проверки.

Проверено 2026-11-03: /anime с offset 0 и 30 вернул по 30 разных записей без пересечения; /anime/111 вернул карточку Наруто, /anime/111/videos — 1353 записи. Пустой POST /profile/login вернул 400 Parameter login is required. Запросов с выдуманными либо чужими учётными данными не выполнялось.

Это доказывает доступность контракта публичного каталога, но не успешный пользовательский вход. Сквозная проверка входа на сайте, капчи, обновления токена и приватных данных аккаунта пока отсутствует. Синхронизация списков аккаунта и удалённой истории в этой версии не реализована.

Проверки кода окна входа: `node --test tests/login-bridge.test.cjs` — 6 пройденных тестов с тестовыми ответами. Проверяются доверенный сайт, API-хост, разрешённый путь, успешный статус, fetch и XHR. Эти тесты не используют реальные учётные данные и не подтверждают успешный вход пользователя.
