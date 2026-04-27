# Payment Services ("пейбокс")

When the user refers to **"платёжные сервисы"**, **"платёжный модуль"**, or
**"пейбокс"** (Paybox), they mean the set of services below. These terms are
interchangeable. All live under `~/arcadia-volumes/payoffline/` (FUSE volume —
never Glob/Grep from the root).

## Backend — платежи, заказы, карты

| Сервис | Путь | Назначение |
|---|---|---|
| PayPlus | `billing/yandex_pay_plus` | Бэкенд платежей и заказов, оркестратор транзакций |
| pay-transactions | `pay/pay-transactions` | Бэкенд заказов (часть связки с PayPlus) |
| yandex_pay | `billing/yandex_pay` | Бэкенд карт и токенизации |
| pay-tarifficator | `billing/pay_tarifficator` | Тарификатор |

## Интерфейсы и SDK

| Сервис | Путь | Назначение |
|---|---|---|
| Frontend pay (fullPayment/split) | `pay/frontend/services/pay` | Платёжные веб-интерфейсы |
| Fintech SDK backend | `mail/payments-sdk-backend` | External API + платёжные виджеты, backend |
| Fintech SDK mobile | `mobile/fintech-sdk` | Мобильная часть SDK |
| yandex_pay_admin | `billing/yandex_pay_admin` | Admin/ops UI |

## Операционные и вспомогательные

| Сервис | Путь | Назначение |
|---|---|---|
| Castrule | `pay/castrule` | Конфигурация форм |
| Citadel | `pay/citadel` | Операционные инструменты |
| Woody | `pay/woody` | Вебхучная |
| Receiptron | `pay/receiptron` | Фискализация / пробитие чеков |
| Mockender | `pay/mockender` | Моки для тестов |
| Loadtest | `pay/loadtest` | Нагрузочное тестирование (включает Fairload) |

## Биллинг

| Сервис | Путь |
|---|---|
| Balance | `billing/balance` (+ `muzzle`, `mailer`) |
| Snout | `billing/snout` (+ `brest`) |
| Acterka | `billing/acterka` |

## Требуют уточнения при упоминании

- **Шопитон** — точное соответствие не подтверждено (кандидаты: `pay/smb`,
  `pay/tallyman`, `pay/promogateway`)
- **B2B стенд** — вероятно `pay/smb`, но не подтверждено
- **Сервис сверки (reconciliation)** — не локализован
- **Сервис корректировок** — не локализован

Если пользователь упомянет один из этих — переспросить или доисследовать.

## Правила работы

- FUSE: не делать Glob/Grep/ls от `~/arcadia-volumes/` или
  `~/arcadia-volumes/payoffline/` — только глубокие пути (3+ уровня), или
  `mcp__arc-mcp__search-code` для глобального поиска.
- Когда пользователь говорит «платёжные сервисы» / «платёжный модуль» /
  «пейбокс» без уточнения — считать, что речь обо всём множестве выше
  (или наиболее релевантном подмножестве по контексту).
