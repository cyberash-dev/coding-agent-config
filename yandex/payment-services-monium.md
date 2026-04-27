# Payment Services — Monium mapping

Which Monium project + service labels correspond to each payment-services repo
for logs/metrics (used with `monium-mcp`).

| Repo | Monium project | Main service label(s) |
|---|---|---|
| `mail/payments-sdk-backend` | `payments-sdk-backend` | `backend` (app logs); `pulic_ua`/`internal_ua` (User-Agent ingest); `workload` |
| `billing/yandex_pay_plus` | `yandexpay` | `yandexpay-plus.api-public`, `yandexpay-plus.api-internal` (or `api-internal`), `yandexpay-plus.api`, `yandexpay-plus.api-inventory`, `yandexpay-plus.api-uniqr`, `yandexpay-plus.workers-profile`, `workers*` |
| `pay/pay-tovarisch` | `pay-tovarisch` | `pay-main-deploy-unit_java` (prod), `pay-canary-deploy-unit_java` (canary), `main-deploy-unit_java`, `canary-deploy-unit_java` |
| `billing/yandex_pay_admin` | (no dedicated SBP-bind logs found; check yandexpay project) | — |
| `mobile/fintech-sdk` | (Android client; no backend logs) | — |

## Notes

- For `payments-sdk-backend` the standard log label set is minimal — handler
  info lives in `message` (e.g. `"Failed to call bind_sbp_token"`); operation
  is set via `tracing.SetOperationName` like `"Bind SBP tokens"`.
- For `yandex_pay_plus`, action begin/end is logged as
  `"<ActionClassName>:BEGIN"` / `":END"` in `message`.
