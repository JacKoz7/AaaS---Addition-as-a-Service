# CLAUDE.md — AaaS (Addition as a Service)

Ten plik jest instrukcją dla Claude (i ludzi) pracujących w tym repozytorium. Czytaj go w całości przed każdą sesją pracy. Specyfikacja źródłowa (wersja do czytania dla ludzi): dokument „AaaS – Addition as a Service: specyfikacja” w claude.ai.

---

## 1. O co chodzi w tym projekcie

AaaS **dodaje dwie liczby całkowite**. Nic więcej. Cała reszta to celowa, przesadzona, ale **logicznie spójna** złożoność: 35 mikroserwisów, każdy z własną bazą danych, napisanych w 28 językach, komunikujących się przez gRPC, HTTP i zdarzenia na Redpandzie, uruchamianych lokalnie w Docker Compose, plus jedna funkcja w AWS w darmowych limitach.

### Zasady nadrzędne (nie łam ich nigdy)

1. **Aplikacja dla użytkownika jest debilnie prosta.** Klawiatura kalkulatora, wyświetlacz, licznik czasu, przycisk pobrania faktury. Żadnych dodatkowych funkcji: bez ciekawostek o liczbach, tłumaczeń, historii obliczeń w UI, maili, wykresów dla użytkownika, innych działań niż dodawanie.
2. **Złożoność jest celem, ale każdy element ma uzasadnienie.** Każdy serwis albo bierze udział w liczeniu, albo pilnuje, żeby liczenie się udało (bezpieczeństwo, spójność, niezawodność, obserwowalność). Nie dodawaj serwisów „dla ozdoby” bez roli w przepływie. Nie upraszczaj istniejącej architektury („przecież wystarczy `a + b`” — tak, wiemy, w tym cały żart).
3. **Koszt 0 zł.** Tylko oprogramowanie open source / darmowe. Jedyna chmura to AWS w limitach Always Free (Lambda, SQS, DynamoDB). Żadnych innych zewnętrznych API.
4. **Każdy serwis ma własną bazę** i nigdy nie sięga do bazy innego serwisu.
5. **Dodawanie liczymy arytmetyką Peano.** `a + b` to `b` wywołań serwisu successor. Natywnego `+` wolno użyć tylko w replikach konsensusu (one niezależnie weryfikują wynik) i w kodzie pomocniczym (np. liczniki pętli, indeksy).
6. **Wszystko ma działać po `make up`** na jednym komputerze (16 GB RAM minimum, 32 GB wygodnie).

### Zakres funkcjonalny

- Dodawanie dwóch nieujemnych liczb całkowitych z zakresu **0–99 999** (wynik max 199 998).
- Interfejs: przyciski `0`–`9`, `+`, `=`, `C`, wyświetlacz, licznik czasu oczekiwania, przycisk „Pobierz fakturę”.
- Po każdym dodawaniu: faktura PDF na 0,00 zł z dopiskiem, że to żart i nie jest to faktura VAT (sprzedawca fikcyjny, bez NIP).

### Czas oczekiwania (to feature, nie bug)

Successor jest wołany tyle razy, ile wynosi **mniejsza** z liczb (commutator ustawia mniejszą jako `b`). Szacunek 10–20 ms na wywołanie, do zmierzenia w fazie 11:

| Przykład | Wywołania successora | Szacowany czas |
| --- | --- | --- |
| 2 + 3 | 2 | 1–3 s |
| 1 000 + 1 000 | 1 000 | 10–25 s |
| 50 000 + 70 000 | 50 000 | 8–17 min |
| 99 999 + 99 999 | 99 999 | 17–35 min |

---

## 2. Katalog serwisów

Wszystkie nazwy serwisów są w kebab-case i są jednocześnie: nazwą katalogu w `services/`, nazwą usługi w Compose, nazwą w Consulu, scope'em commitów i prefiksem metryk.

| Nr | Serwis | Rola w dodawaniu | Język / technologia | Baza danych |
| --- | --- | --- | --- | --- |
| 1 | `gateway` | Jedyne wejście, routing, middleware forwardAuth | Traefik | Redis (tablica tras, provider Redis) |
| 2 | `auth` | OAuth2/OIDC, logowanie gościa | Keycloak (Java) | PostgreSQL |
| 3 | `rate-limiter` | forwardAuth: weryfikacja JWT + limit dodawań | Ruby | Redis |
| 4 | `idempotency` | Ten sam klucz `=` → to samo zadanie | TypeScript (Deno) | Valkey |
| 5 | `feature-flags` | Flaga `addition_enabled` | Unleash | PostgreSQL |
| 6 | `service-discovery` | Rejestr serwisów | Consul | wbudowany Raft |
| 7 | `config-server` | Konfiguracja pobierana przy starcie | PHP | MongoDB |
| 8 | `secrets` | Hasła do baz, AppRole per serwis | OpenBao | wbudowany Raft |
| 9 | `schema-registry` | JSON Schema każdego zdarzenia | Apicurio Registry | PostgreSQL |
| 10 | `parser` | Tekst `2+3` → AST | OCaml | SQLite (cache AST) |
| 11 | `validator` | Liczby w zakresie 0–99 999 | Rust | MariaDB |
| 12 | `operator-registry` | `+` → saga `addition`, sprawdza flagę | Crystal | PostgreSQL |
| 13 | `digit-0` | Cyfra 0: wartość i następna cyfra | C | SQLite |
| 14 | `digit-1` | Cyfra 1 | C++ | SQLite |
| 15 | `digit-2` | Cyfra 2 | Fortran | SQLite |
| 16 | `digit-3` | Cyfra 3 | Free Pascal | SQLite |
| 17 | `digit-4` | Cyfra 4 | Lua | SQLite |
| 18 | `digit-5` | Cyfra 5 | Dart | SQLite |
| 19 | `digit-6` | Cyfra 6 | Swift | SQLite |
| 20 | `digit-7` | Cyfra 7 | Gleam | SQLite |
| 21 | `digit-8` | Cyfra 8 | D | SQLite |
| 22 | `digit-9` | Cyfra 9 (następna = 0 + przeniesienie) | Racket | SQLite |
| 23 | `successor` | n → n+1 przez serwisy cyfr i carry | Haskell | CouchDB (log wywołań) |
| 24 | `carry` | Przeniesienie jedynki na wyższy rząd | Elixir | Mnesia |
| 25 | `saga-orchestrator` | Workflow dodawania, kompensacja, status zadań | Temporal + worker w Go | PostgreSQL (saga_db + outbox) |
| 26 | `consensus` | 3 repliki liczą niezależnie, Raft wybiera większość | Go + hashicorp/raft; repliki: Python, Rust, COBOL | BoltDB (log Raft) |
| 27 | `distributed-lock` | Kolejność zapisów do ledgera i numeracji faktur | etcd | wbudowany |
| 28 | `outbox-relay` | Outbox z Postgresa → Redpanda (CDC) | Debezium | PostgreSQL (offsety) |
| 29 | `dead-letter` | Ponawianie nieudanych zdarzeń, sygnał kompensacji | Perl | MongoDB |
| 30 | `ledger` | Niezmienny zapis wyników z łańcuchem hashy | Nim | immudb |
| 31 | `expression-assembler` | Kliknięcia → wyrażenie | C# (.NET) | SurrealDB |
| 32 | `commutator` | Zamienia a i b, żeby b było mniejsze | Zig | LMDB |
| 33 | `cloud-notary` | (AWS) weryfikuje łańcuch hashy, kopia wyniku | AWS Lambda (Python) + SQS | DynamoDB |
| 34 | `stopwatch` | Start przy `=`, stop przy zapisie w ledgerze, SSE | Kotlin (Ktor) | TimescaleDB |
| 35 | `billing` | Faktura PDF na 0,00 zł | Common Lisp (SBCL) + Typst | Firebird |

Repliki konsensusu (`consensus-replica-python`, `consensus-replica-rust`, `consensus-replica-cobol`) są częścią serwisu `consensus`, mieszkają w `services/consensus/replicas/`.

### Infrastruktura wspólna (nie liczy się do 35)

| Element | Technologia | Profil Compose |
| --- | --- | --- |
| Szyna zdarzeń | Redpanda + Redpanda Console | `core` |
| Temporal server + UI | Temporal (auto-setup) | `core` |
| Metryki | Prometheus | `observability` |
| Logi | Loki (+ Promtail lub OTel) | `observability` |
| Trace | Jaeger | `observability` |
| Kolektor | OpenTelemetry Collector | `observability` |
| Dashboardy | Grafana (provisioning z plików) | `observability` |
| Alerty | Alertmanager | `observability` |
| Emulator AWS | Floci (MIT) | `aws-local` |
| Mikrofrontendy | nginx per mikrofrontend | `frontend` |

### Mikrofrontendy

Powłoka: **single-spa** z import mapą. Każdy element to osobny kontener nginx.

| Element | Framework | Katalog |
| --- | --- | --- |
| Powłoka | single-spa | `frontend/shell` |
| Wyświetlacz | Elm | `frontend/display` |
| Przycisk 0 | React | `frontend/key-0` |
| Przycisk 1 | Vue | `frontend/key-1` |
| Przycisk 2 | Svelte | `frontend/key-2` |
| Przycisk 3 | Angular | `frontend/key-3` |
| Przycisk 4 | SolidJS | `frontend/key-4` |
| Przycisk 5 | Preact | `frontend/key-5` |
| Przycisk 6 | Lit | `frontend/key-6` |
| Przycisk 7 | Qwik | `frontend/key-7` |
| Przycisk 8 | Alpine.js | `frontend/key-8` |
| Przycisk 9 | Ember | `frontend/key-9` |
| `+` | htmx | `frontend/key-plus` |
| `=` | Mithril | `frontend/key-equals` |
| `C` | czysty JavaScript | `frontend/key-clear` |
| Licznik czasu | Marko | `frontend/timer` |
| Pobierz fakturę | Stencil | `frontend/invoice-button` |

Mikrofrontendy komunikują się wyłącznie przez **wspólną szynę zdarzeń przeglądarki** (`window` CustomEvent z prefiksem `aaas:`), nigdy przez bezpośrednie importy między sobą:

- `aaas:key-pressed` `{ key }` — publikuje przycisk.
- `aaas:task-started` `{ taskId }` — publikuje powłoka po odpowiedzi 202 na `=`.
- `aaas:task-finished` `{ taskId, result }` — publikuje wyświetlacz.
- `aaas:clear` — publikuje `C`.

---

## 3. Przepływ żądania „2 + 3” krok po kroku

```
[przyciski] --POST /api/v1/keys--> gateway --forwardAuth--> rate-limiter
                                      |
                                      v
                           expression-assembler --(=)--> idempotency
                                      |
                       aaas.expression.submitted.v1
                         |                       |
                         v                       v
                       parser                stopwatch (start)
           validator / commutator / operator-registry (+ feature-flags)
                         |
               aaas.addition.requested.v1
                         v
               saga-orchestrator (Temporal AdditionWorkflow)
                 |  1. resolveDigits  -> digit-N
                 |  2. b x successor  -> digit-N, carry
                 |  3. vote           -> consensus (Python, Rust, COBOL)
                 |  4. outbox row     -> outbox-relay (Debezium)
                         v
                 aaas.result.voted.v1
                         v
               ledger (distributed-lock, immudb, hash chain)
                         |
                aaas.ledger.appended.v1 --------> SQS --> cloud-notary (AWS)
                  |              |
                  v              v
          stopwatch (stop)   billing (faktura, distributed-lock)

   błąd w dowolnym kroku --> aaas.dlq.v1 --> dead-letter --> retry / sygnał kompensacji do sagi
```

Szczegółowo:

1. **Wejście.** Użytkownik loguje się w Keycloak (konto gościa jednym kliknięciem). Każde kliknięcie przycisku to `POST /api/v1/keys` z tokenem JWT. Traefik przepuszcza żądanie przez forwardAuth do `rate-limiter` (weryfikacja JWT kluczami JWKS z Keycloak + limit: 120 kliknięć/min, 10 naciśnięć `=`/min na użytkownika).
2. **Składanie wyrażenia.** `expression-assembler` zapisuje każde kliknięcie w SurrealDB i publikuje `aaas.key.pressed.v1`. Na `=` składa wyrażenie z sekwencji kliknięć sesji, wymaga nagłówka `Idempotency-Key` i pyta `idempotency`, czy to zadanie już istnieje. Jeśli nie — generuje `taskId` (UUIDv7), publikuje `aaas.expression.submitted.v1` i zwraca `202 { taskId }`.
3. **Start stopera.** `stopwatch` konsumuje `expression.submitted` i zapisuje czas startu.
4. **Rozbiór.** `parser` buduje AST, woła `validator` (zakres), `commutator` (a ≥ b), `operator-registry` (czy `+` istnieje i czy flaga `addition_enabled` jest włączona w Unleash). Publikuje `aaas.addition.requested.v1 { taskId, a, b }`.
5. **Saga.** `saga-orchestrator` konsumuje zdarzenie i startuje workflow Temporal `AdditionWorkflow(taskId, a, b)` z `workflowId = taskId` (idempotencja na poziomie Temporala).
6. **Cyfry.** Aktywność `resolveDigits` odpytuje serwisy `digit-N` dla każdej cyfry `a` i `b` („potwierdzenie wartości”).
7. **Peano.** `b` razy aktywność `successor(n)`. `successor` zwiększa cyfrę jedności: pyta `digit-d` o następną cyfrę; jeśli `d = 9`, woła `carry`, który propaguje przeniesienie w górę, odpytując kolejne serwisy cyfr. Każde wywołanie loguje się w CouchDB. **Workflow robi `continue-as-new` co 1000 iteracji**, bo historia Temporala ma limit zdarzeń. Postęp `(done, total)` jest dostępny przez Temporal Query.
8. **Konsensus.** Aktywność `vote(taskId, a, b, peanoResult)` → `consensus`. Trzy repliki liczą `a + b` niezależnie (natywnie), Raft zatwierdza wynik większości. Jeśli wynik większości ≠ wynik Peano → błąd → DLQ.
9. **Outbox.** Worker sagi zapisuje wynik i wiersz outbox w jednej transakcji w `saga_db`. Debezium (`outbox-relay`) publikuje `aaas.result.voted.v1`.
10. **Ledger.** `ledger` bierze blokadę `ledger-append` z etcd, dopisuje wpis do immudb (`hash = sha256(prevHash || taskId || a || b || result || timestamp)`), publikuje `aaas.ledger.appended.v1` i wysyła kopię do SQS.
11. **Po zapisie.** `stopwatch` zatrzymuje czas. `billing` bierze blokadę `invoice-number`, nadaje numer `FV/RRRR/MM/NNNNNN`, generuje PDF w Typst. `cloud-notary` (Lambda) sprawdza ciągłość łańcucha hashy i zapisuje kopię w DynamoDB.
12. **Wynik w UI.** Wyświetlacz odpytuje `GET /api/v1/tasks/{taskId}` co 1 s, licznik słucha SSE `GET /api/v1/tasks/{taskId}/timer`. Po `RECORDED` pokazuje wynik i odblokowuje przycisk faktury.
13. **Błędy.** Każdy konsument po wyczerpaniu lokalnych ponowień wysyła zdarzenie do `aaas.dlq.v1`. `dead-letter` ponawia je z backoffem wykładniczym (max 5 prób), a potem wysyła do sagi sygnał `compensate`. Saga przechodzi w `FAILED` i cofa to, co da się cofnąć (zwalnia blokady, oznacza zadanie w idempotency jako nieudane).

### Platforma przy starcie każdego serwisu

1. Pobierz konfigurację: `GET http://config-server:8080/config/{service}?env=local`.
2. Zaloguj się do OpenBao przez AppRole (`role_id`/`secret_id` z pliku zamontowanego przez Compose), pobierz hasło do swojej bazy.
3. Zarejestruj się w Consulu z healthcheckiem `GET /health`.
4. Zweryfikuj, że schematy zdarzeń, które produkujesz, istnieją w `schema-registry` (jeśli nie — nie startuj, `exit 1`).

Do czasu fazy 5 serwisy czytają konfigurację ze zmiennych środowiskowych. Biblioteka startowa musi mieć oba tryby (`AAAS_BOOTSTRAP=env|platform`).

---

## 4. Kontrakty

### 4.1 Publiczne API (przez `gateway`)

| Metoda | Ścieżka | Obsługuje | Opis |
| --- | --- | --- | --- |
| `POST` | `/api/v1/keys` | `expression-assembler` | Body `{ sessionId, key, seq }`. Zwraca `204`, a dla `key = "="` zwraca `202 { taskId }`. `=` wymaga nagłówka `Idempotency-Key`. |
| `GET` | `/api/v1/tasks/{taskId}` | `saga-orchestrator` | `{ taskId, status, a, b, progress: { done, total }, result? }` |
| `GET` | `/api/v1/tasks/{taskId}/timer` | `stopwatch` | SSE: `{ startedAt, elapsedMs, finishedAt? }` co 100 ms |
| `GET` | `/api/v1/invoices/{taskId}.pdf` | `billing` | PDF faktury, `404` dopóki nie wystawiona |
| `GET` | `/api/v1/ledger/verify` | `ledger` | Weryfikacja całego łańcucha hashy |
| `GET` | `/auth/*` | `auth` | Keycloak |
| `GET` | `/*` | `frontend-shell` | Frontend |

Statusy zadania: `ACCEPTED → PARSED → COUNTING → VOTING → RECORDING → RECORDED`, albo `FAILED`.

Błędy API zawsze w formacie RFC 9457 (`application/problem+json`).

### 4.2 Zdarzenia (Redpanda)

Nazwy topików: `aaas.<encja>.<czasownik-przeszły>.v<N>`. Partycjonowanie po `taskId`. Format JSON, schemat JSON Schema w `schema-registry`, pliki źródłowe w `contracts/events/`.

Koperta każdego zdarzenia:

```json
{
  "eventId": "018f3c2e-7b1a-7c3d-9f00-000000000001",
  "type": "aaas.addition.requested",
  "version": 1,
  "occurredAt": "2026-10-16T12:00:00.000Z",
  "producer": "parser",
  "taskId": "018f3c2e-7b1a-7c3d-9f00-0000000000aa",
  "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
  "payload": { "a": 3, "b": 2 }
}
```

| Topik | Producent | Konsumenci |
| --- | --- | --- |
| `aaas.key.pressed.v1` | expression-assembler | (audyt, przyszłe użycie) |
| `aaas.expression.submitted.v1` | expression-assembler | parser, stopwatch |
| `aaas.addition.requested.v1` | parser | saga-orchestrator |
| `aaas.successor.called.v1` | successor | (audyt) |
| `aaas.carry.propagated.v1` | carry | (audyt) |
| `aaas.result.voted.v1` | outbox-relay (z outboxa sagi) | ledger |
| `aaas.ledger.appended.v1` | ledger | stopwatch, billing |
| `aaas.invoice.issued.v1` | billing | (audyt) |
| `aaas.dlq.v1` | każdy konsument | dead-letter |

Zasady: zdarzenia są niezmienne; zmiana niekompatybilna = nowy topik `.v2`; każdy konsument jest idempotentny po `eventId` (tabela `processed_events` we własnej bazie).

### 4.3 gRPC

Pliki `.proto` w `contracts/proto/aaas/<serwis>/v1/`. Generowanie przez `buf generate`, lint przez `buf lint`, łamanie kompatybilności sprawdza `buf breaking` w CI.

| Serwis | Metody |
| --- | --- |
| `validator` | `Validate(ValidateRequest{a,b}) → ValidateResponse{ok, reason}` |
| `commutator` | `Normalize({a,b}) → {a,b,swapped}` |
| `operator-registry` | `Resolve({operator}) → {saga, enabled}` |
| `idempotency` | `Claim({key, taskId}) → {taskId, existing}`, `MarkFailed({key})` |
| `successor` | `Next({n}) → {n}` |
| `carry` | `Propagate({digits, position}) → {digits}` |
| `consensus` | `Vote({taskId, a, b, candidate}) → {accepted, result, votes}` |

### 4.4 Kontrakt serwisu cyfry (HTTP/JSON)

Serwisy cyfr używają **HTTP/JSON zamiast gRPC**, bo Fortran, Free Pascal, Racket i Lua nie mają dojrzałych bibliotek gRPC. Kontrakt (OpenAPI w `contracts/http/digit.yaml`):

- `GET /value` → `{ "digit": 7, "value": 7 }`
- `GET /next` → `{ "digit": 7, "next": 8, "carry": false }` (dla `digit-9`: `{ "next": 0, "carry": true }`)
- `GET /health`, `GET /metrics`

Wartość i następnik **muszą być odczytywane z własnej bazy SQLite** (seed w migracji), nie zahardkodowane w kodzie. Jeśli język nie ma sensownego serwera HTTP, dopuszczalny jest cienki wrapper (CGI przez lighttpd albo `socat`), ale **logika cyfry i dostęp do bazy muszą być w docelowym języku**. Każde takie obejście opisz w ADR. To samo dotyczy repliki COBOL.

---

## 5. Struktura repozytorium

```
.
├── CLAUDE.md
├── README.md
├── Makefile
├── docker-compose.yml              # tylko include: do plików z compose/
├── compose/
│   ├── core.yml                    # Redpanda, Temporal, bazy
│   ├── services.yml                # 35 serwisów
│   ├── frontend.yml
│   ├── observability.yml
│   └── aws-local.yml
├── .env.example
├── contracts/
│   ├── events/                     # JSON Schema zdarzeń
│   ├── proto/aaas/<serwis>/v1/     # gRPC
│   └── http/                       # OpenAPI (cyfry, publiczne API)
├── services/
│   └── <serwis>/
│       ├── Dockerfile
│       ├── README.md               # rola, API, baza, jak testować
│       ├── src/ ...
│       ├── migrations/
│       ├── tests/
│       └── docs/                   # SERVICE_CHARTER, RACI, SLO, RUNBOOK... (6.5.5)
├── frontend/<element>/
├── infra/
│   ├── traefik/  keycloak/  openbao/  consul/  grafana/  prometheus/  loki/  alertmanager/
│   └── aws/                        # OpenTofu
├── templates/service/              # szablon nowego serwisu
├── templates/docs/                 # szablony dokumentów korporacyjnych
├── CONTRIBUTING.md  CODE_OF_CONDUCT.md  SECURITY.md  CODEOWNERS
├── mkdocs.yml                      # portal dokumentacji
├── cliff.toml                      # git-cliff (changelogi)
├── scripts/                        # new-service.sh, wait-for.sh, e2e.sh, seed.sh
├── tests/
│   ├── e2e/                        # testy całego systemu
│   └── chaos/
└── docs/
    ├── PROGRESS.md                 # Current State + checklista kroków (źródło prawdy o postępie)
    ├── progress/steps/P*.md        # log (snapshot) każdego kroku, patrz 8.1
    ├── adr/NNNN-tytul.md
    ├── rfc/NNNN-tytul.md
    ├── governance/                 # RFC_PROCESS, RISK_REGISTER, DPIA, RELEASE_PROCESS, postmortem
    ├── onboarding/
    ├── releases/phase-N.md
    ├── GLOSSARY.md
    ├── architecture.md             # diagramy Mermaid
    ├── architecture/c4/
    └── site/                       # wygenerowany portal (w .gitignore)
```

---

## 6. Konwencje techniczne (obowiązują każdy serwis)

### 6.1 Wymagania na każdy serwis

- Port HTTP **8080** w kontenerze: `GET /health` (liveness + readiness, JSON `{status, checks}`), `GET /metrics` (Prometheus).
- Port gRPC **9090** w kontenerze (jeśli serwis ma gRPC).
- **Logi strukturalne JSON** na stdout: `ts`, `level`, `service`, `msg`, `taskId`, `traceId`, `spanId`.
- **OpenTelemetry**: trace propagowany przez nagłówek `traceparent` w HTTP/gRPC i pole `traceparent` w kopercie zdarzenia. Eksport OTLP do `otel-collector:4317`.
- **Graceful shutdown** na SIGTERM w ≤ 10 s.
- **Migracje bazy** uruchamiane przy starcie, wersjonowane w `migrations/`.
- **Idempotentni konsumenci** (patrz 4.2).
- **Timeouty i ponowienia** na każdym wywołaniu sieciowym (domyślnie timeout 2 s, 3 próby z jitterem), potem DLQ.
- Konfiguracja wyłącznie przez env / config-server. Zero hardkodowanych hostów i haseł.
- `README.md` serwisu: rola, kontrakty, baza, zmienne środowiskowe, jak uruchomić testy.

### 6.2 Docker / Compose

- `Dockerfile` multi-stage, finalny obraz minimalny, użytkownik nie-root, `HEALTHCHECK` w Compose (nie w Dockerfile).
- Obrazy bazowe przypięte do wersji (bez `latest`). Wszystkie obrazy muszą mieć wariant `linux/arm64` i `linux/amd64`, jeśli to możliwe.
- Każdy kontener ma `mem_limit` i `cpus`. Domyślne limity: serwisy w językach kompilowanych 64 MB, interpretowanych 128 MB, JVM 512 MB, bazy 256 MB. Odstępstwa uzasadnij w komentarzu.
- Sieci: `public` (tylko gateway i frontend), `services`, `data`. Bazy są wyłącznie w `data`, a każdy serwis podłącza się tylko do swojej bazy.
- `depends_on` z `condition: service_healthy`.
- Nazwy wolumenów: `<serwis>-data`.
- Profile Compose: `core`, `services`, `frontend`, `observability`, `aws-local`. `make up` uruchamia wszystkie poza `aws-local`.

Porty wystawione na hosta (tylko te):

| Port | Co |
| --- | --- |
| 80 | gateway (frontend + API + /auth) |
| 3001 | Grafana |
| 8082 | Redpanda Console |
| 8233 | Temporal UI |
| 8500 | Consul UI |
| 4242 | Unleash UI |
| 16686 | Jaeger UI |
| 8200 | OpenBao UI |
| 4566 | Floci (profil `aws-local`) |

### 6.3 Kod

- **Wszystko, co trafia do repozytorium, jest po angielsku**, bez wyjątków: kod, identyfikatory, komentarze w kodzie, docstringi, commity, nazwy gałęzi i tagów, README, cała dokumentacja w `docs/` (ADR, RFC, governance, runbooki, changelogi, release notes), `docs/PROGRESS.md` i logi kroków, komunikaty logów i błędów, opisy PR. Jedynym plikiem po polsku jest ten `CLAUDE.md` (instrukcja dla Claude). Z użytkownikiem Claude rozmawia po polsku.
- Każdy język używa swojego standardowego formatera i lintera (`gofmt`, `rustfmt`/`clippy`, `ocamlformat`, `mix format`, `dotnet format`, `ktlint`, `rubocop`, `php-cs-fixer`, `black`/`ruff`, `zig fmt`, `deno fmt`, itd.). `make lint` odpala je wszystkie.
- Testy jednostkowe w każdym serwisie, uruchamiane w kontenerze (`make test-<serwis>`).
- Żadnych sekretów w repo. `.env` jest w `.gitignore`, w repo jest tylko `.env.example`.

### 6.4 Testy

| Poziom | Gdzie | Co |
| --- | --- | --- |
| Jednostkowe | `services/<serwis>/tests` | logika serwisu |
| Kontraktowe | `contracts/` + CI | `buf lint/breaking`, walidacja JSON Schema przykładów, OpenAPI lint |
| E2E | `tests/e2e` | pełny przepływ przez gateway: `2+3=5`, `0+0=0`, `9+1=10`, `99999+1=100000`, przemienność, idempotencja `=` |
| Chaos | `tests/chaos` | ubicie serwisu w trakcie dodawania, wynik nadal poprawny |
| Wydajność | `tests/load` | k6, pomiar czasu na wywołanie successora |

`make e2e` musi przechodzić po zakończeniu każdego kroku, który dotyka przepływu.

### 6.5 Dokumentacja korporacyjna (obowiązkowa, bez wyjątków)

AaaS jest dokumentowany jak system krytyczny dla korporacji z listy Fortune 500. Wszystko, co istnieje, ma dokumentację: każdy plik, moduł, typ, funkcja, stała, endpoint, zdarzenie, tabela, kolumna, kontener, zmienna środowiskowa i decyzja. Ton jest formalny, korporacyjny i śmiertelnie poważny.

**Jedna zasada ponad wszystko: dokumentacja musi być prawdziwa.** Korporacyjny styl, ale treść zgodna z kodem. Docstring opisujący coś, czego funkcja nie robi, to błąd tej samej wagi co błąd w kodzie.

#### 6.5.1 Fikcyjna struktura organizacyjna

Wszystkie dokumenty odwołują się do zespołów. Każdy zespół to w praktyce właściciel repozytorium (`@aaas-owner` w CODEOWNERS), ale w dokumentacji występują osobno.

| Zespół | Obszar | Serwisy |
| --- | --- | --- |
| Arithmetic Excellence Center (AEC) | Liczenie | parser, validator, operator-registry, commutator, digit-0…9, successor, carry |
| Transaction Integrity Office (TIO) | Spójność i niezawodność | saga-orchestrator, consensus, distributed-lock, outbox-relay, dead-letter, ledger |
| Platform Enablement Guild (PEG) | Platforma | gateway, service-discovery, config-server, secrets, schema-registry |
| Trust & Identity Board (TIB) | Bezpieczeństwo | auth, rate-limiter, idempotency, feature-flags |
| Customer Experience Tribe (CXT) | Frontend i czas | expression-assembler, stopwatch, wszystkie mikrofrontendy |
| Revenue Operations Unit (ROU) | Przychody (0,00 zł) | billing |
| Cloud Governance Committee (CGC) | AWS | cloud-notary, `infra/aws` |
| Observability Steering Group (OSG) | Monitoring | stos obserwowalności |

#### 6.5.2 Nagłówek każdego pliku źródłowego

Każdy plik z kodem, konfiguracją, migracją, Dockerfile i plik Compose zaczyna się od nagłówka w składni komentarza danego języka:

```
SPDX-License-Identifier: MIT
Copyright (c) 2026 AaaS Contributors

Component:       successor
Module:          Successor.Core
Owning Team:     Arithmetic Excellence Center (AEC)
Classification:  INTERNAL
Purpose:         Computes the successor of a natural number by orchestrating
                 digit services and the carry service.
Related Docs:    services/successor/docs/SERVICE_CHARTER.md, ADR-0007
```

Dockerfile dodatkowo ma etykiety OCI: `org.opencontainers.image.title`, `.description`, `.version`, `.source`, `.licenses`, `.vendor` („AaaS Contributors”) i własną `com.aaas.owning-team`.

#### 6.5.3 Docstringi: wymagane pola

Każdy moduł, typ, funkcja, metoda i stała (publiczne **i prywatne**) ma docstring z polami:

| Pole | Treść |
| --- | --- |
| Summary | Jedno zdanie, co robi |
| Description | Szczegóły zachowania, przypadki brzegowe |
| Business Justification | Dlaczego to istnieje z perspektywy „biznesu” AaaS |
| Parameters | Każdy parametr: typ, znaczenie, dozwolony zakres |
| Returns | Typ i znaczenie |
| Errors / Throws | Każdy możliwy błąd i kiedy występuje |
| Side Effects | I/O, zapisy do bazy, publikowane zdarzenia, wywołania sieciowe; „None” jeśli brak |
| Complexity | Czasowa i pamięciowa (O-notacja) |
| Thread Safety | Czy bezpieczne współbieżnie |
| Owner | Zespół z 6.5.1 |
| Since | Wersja serwisu, w której się pojawiło |
| Example | Przynajmniej jeden przykład użycia (gdzie język wspiera doctesty, uruchamiany w testach) |
| See Also | Powiązane funkcje, kontrakty, ADR |

Przykład (Go):

```go
// Next computes the successor of n.
//
// Description:
//   Increments the least significant digit of n by querying the digit
//   service responsible for that digit. When the digit service reports a
//   carry, the carry service is invoked to propagate it to higher positions.
//
// Business Justification:
//   Enables Peano-compliant addition, which is a core value proposition of
//   AaaS and a key differentiator against native arithmetic.
//
// Parameters:
//   - ctx: request context carrying deadline and trace information.
//   - n:   natural number in the range [0, 199997].
//
// Returns:
//   - uint32: n + 1.
//
// Errors:
//   - ErrDigitUnavailable: a digit service did not respond within the timeout.
//   - ErrCarryFailed: the carry service returned an error.
//
// Side Effects:
//   Performs 1..6 HTTP calls to digit services and 0..1 gRPC call to carry.
//   Appends one entry to the CouchDB call log. Publishes aaas.successor.called.v1.
//
// Complexity: O(d) time and O(d) memory, where d is the number of digits of n.
// Thread Safety: safe for concurrent use.
// Owner: Arithmetic Excellence Center (AEC)
// Since: successor v0.2.0
//
// Example:
//   next, err := Next(ctx, 199) // next == 200
//
// See Also: carry.Propagate, contracts/http/digit.yaml, ADR-0007.
func Next(ctx context.Context, n uint32) (uint32, error) {
```

Format docstringów per język (używaj natywnego narzędzia, pola z tabeli wyżej w jego składni):

| Język | Format | Narzędzie generujące |
| --- | --- | --- |
| Go | doc comments | `go doc` / pkgsite |
| Rust | `///`, `//!` | rustdoc |
| Haskell | Haddock | haddock |
| OCaml | `(** *)` | odoc |
| Elixir, Gleam | `@moduledoc`/`@doc`, `///` | ExDoc, gleam docs |
| C# | XML doc comments | DocFX |
| Kotlin | KDoc | Dokka |
| Ruby | YARD | yard |
| PHP | PHPDoc | phpDocumentor |
| Python | Google style | pdoc |
| TypeScript, JavaScript | TSDoc / JSDoc | TypeDoc / JSDoc |
| Nim, Crystal, Zig, D, Dart, Swift | natywne doc comments | `nim doc`, `crystal docs`, `zig -femit-docs`, ddoc, dartdoc, DocC |
| C, C++ | Doxygen | Doxygen |
| Fortran | FORD | FORD |
| Free Pascal | PasDoc | PasDoc |
| Lua | LDoc | LDoc |
| Racket | Scribble | scribble |
| Perl | POD | pod2html |
| Common Lisp | docstringi + nagłówki sekcji | własny skrypt eksportu |
| COBOL | blok komentarzy w IDENTIFICATION DIVISION + nagłówek każdego paragrafu | własny skrypt eksportu |
| Elm, Marko, Stencil, pozostałe frontendy | natywne / JSDoc | elm docs, TypeDoc |
| SQL (migracje) | nagłówek pliku + `COMMENT ON TABLE/COLUMN` dla każdej tabeli i kolumny | schemaspy (dla Postgresa) |

#### 6.5.4 Egzekwowanie: 100% pokrycia

`make doc-coverage` musi pokazywać 100% dla każdego serwisu. Narzędzia:

| Język | Wymuszenie |
| --- | --- |
| Rust | `#![deny(missing_docs)]`, `clippy::missing_docs_in_private_items` |
| Python | `interrogate --fail-under 100` |
| Go | `revive` z regułą `exported` + własny check prywatnych |
| C# | `CS1591` jako błąd |
| Kotlin | detekt `UndocumentedPublic*` |
| TypeScript/JS | `eslint-plugin-jsdoc` (require-jsdoc wszędzie) |
| Ruby | `yard stats --list-undoc` = 0 |
| PHP | phpcs z regułami komentarzy |
| Elixir | `doctor` |
| Haskell | raport pokrycia haddocka = 100% |
| Pozostałe | `scripts/doc-check.sh`: nagłówek pliku + komentarz przed każdą definicją najwyższego poziomu |

#### 6.5.5 Dokumenty każdego serwisu

Katalog `services/<serwis>/docs/` (dla mikrofrontendów `frontend/<element>/docs/`) zawiera:

| Plik | Zawartość |
| --- | --- |
| `SERVICE_CHARTER.md` | Misja, wartość biznesowa, interesariusze, zakres i poza zakresem, KPI |
| `RACI.md` | Macierz RACI dla zmian, wdrożeń, incydentów, migracji |
| `SLO.md` | SLI, SLO (np. 99,9% poprawnych odpowiedzi), budżet błędów, okno pomiaru |
| `RUNBOOK.md` | Każdy alert serwisu: znaczenie, diagnoza krok po kroku, naprawa, eskalacja |
| `THREAT_MODEL.md` | STRIDE: zagrożenia, mitygacje, ryzyko rezydualne |
| `DATA_CLASSIFICATION.md` | Jakie dane przechowuje, klasyfikacja (PUBLIC/INTERNAL/CONFIDENTIAL), retencja |
| `DEPENDENCIES.md` | Zależności upstream i downstream, kontrakty, skutki awarii każdej z nich |
| `CAPACITY.md` | Zmierzone zużycie RAM/CPU, limity, uzasadnienie |
| `API.md` | Opis wszystkich endpointów i zdarzeń (generowany, nie edytuj ręcznie) |
| `CHANGELOG.md` | Format Keep a Changelog, wersjonowanie SemVer per serwis |

Szablony wszystkich dokumentów są w `templates/docs/` i `scripts/new-service.sh` kopiuje je przy tworzeniu serwisu.

#### 6.5.6 Dokumenty repozytorium

| Plik | Zawartość |
| --- | --- |
| `CONTRIBUTING.md` | Proces zmian, kroki, commity, review |
| `CODE_OF_CONDUCT.md` | Kodeks postępowania (Contributor Covenant) |
| `SECURITY.md` | Zgłaszanie podatności |
| `CODEOWNERS` | Każdy katalog przypisany do zespołu (w praktyce `@aaas-owner`) |
| `.github/pull_request_template.md` | Checklista z Definition of Done |
| `.github/ISSUE_TEMPLATE/` | Bug, feature request (zawsze odrzucany, patrz sekcja 1), incydent |
| `docs/governance/RFC_PROCESS.md` | Proces RFC dla zmian obejmujących więcej niż jeden serwis (`docs/rfc/NNNN-tytul.md`) |
| `docs/governance/RISK_REGISTER.md` | Rejestr ryzyk: prawdopodobieństwo, wpływ, właściciel, mitygacja |
| `docs/governance/DPIA.md` | Ocena skutków dla ochrony danych (RODO): przetwarzane liczby i identyfikatory sesji |
| `docs/governance/RELEASE_PROCESS.md` | Wersjonowanie, tagi `<serwis>/vX.Y.Z`, release notes |
| `docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md` | Szablon postmortem bez szukania winnych |
| `docs/onboarding/ONBOARDING.md` | Pierwszy dzień nowego członka zespołu: od `git clone` do `2+3=5` |
| `docs/architecture/c4/` | Diagramy C4: kontekst, kontenery, komponenty (Structurizr DSL lub Mermaid) |
| `docs/GLOSSARY.md` | Pełny słownik (rozszerzenie sekcji 11) |

#### 6.5.7 Portal dokumentacji

`make docs` generuje dokumentację API każdego serwisu jego natywnym narzędziem i składa wszystko w jeden portal **MkDocs Material** w `docs/site/`, serwowany lokalnie przez `make docs-serve` na porcie 8000. Portal ma: stronę główną z mapą serwisów, katalog serwisów z linkami do ich dokumentów, katalog zdarzeń (generowany z JSON Schema), katalog API (OpenAPI i proto), ADR, RFC, rejestr ryzyk i changelogi.

#### 6.5.8 Changelog i release notes

- `CHANGELOG.md` każdego serwisu jest generowany z commitów przez **git-cliff** (scope commita = serwis), a potem uzupełniany ręcznie o sekcję „Business Impact”.
- Każde zamknięcie fazy kończy się release notes w `docs/releases/phase-N.md` w tonie korporacyjnego komunikatu („We are thrilled to announce…”), ale z prawdziwą listą zmian.

---

## 7. Git: commity, gałęzie, PR

### 7.1 Conventional Commits

Format:

```
<type>(<scope>): <opis w trybie rozkazującym, małą literą, bez kropki>

<opcjonalne ciało: co i dlaczego, nie jak>

Step: P<faza>.<krok>
Refs: ADR-NNNN (jeśli dotyczy)
BREAKING CHANGE: <opis> (jeśli dotyczy)
```

Typy:

| Typ | Kiedy |
| --- | --- |
| `feat` | nowa funkcjonalność serwisu lub nowy serwis |
| `fix` | poprawka błędu |
| `refactor` | zmiana kodu bez zmiany zachowania |
| `perf` | wydajność |
| `test` | tylko testy |
| `docs` | tylko dokumentacja |
| `build` | Dockerfile, zależności, buildy |
| `ci` | GitHub Actions |
| `chore` | porządki, konfiguracja narzędzi |
| `contract` | zmiany w `contracts/` (proto, schematy, OpenAPI) |
| `infra` | Compose, Traefik, Keycloak, OpenBao, OpenTofu itd. |

Scope: nazwa serwisu (`successor`, `digit-7`), elementu frontendu (`frontend-key-3`) albo obszaru (`compose`, `contracts`, `observability`, `aws`, `repo`).

Przykłady:

```
feat(successor): compute n+1 by querying digit services
contract(contracts): add aaas.addition.requested.v1 schema
infra(compose): add redpanda with healthcheck and console
fix(carry): propagate carry past the highest digit
test(e2e): cover 99999+1 carry chain
```

Zasady:

- Jeden commit = jedna logiczna zmiana. Krok z planu kończy się co najmniej jednym commitem z trailerem `Step:`.
- Commit nie może psuć `make up` ani `make e2e` (jeśli krok dotyka przepływu).
- `commitlint` w pre-commit i w CI.

### 7.2 Gałęzie i PR

- `main` jest zawsze zielony.
- Gałąź na krok: `step/P<faza>.<krok>-<krótki-opis>`, np. `step/P2.13-successor-uses-digits`.
- PR na krok, tytuł jak commit, opis: co zrobiono, jak przetestowano, link do kroku w `docs/PROGRESS.md`.
- Commity checkpointów (`chore(progress): checkpoint ...`) mogą zawierać niedokończony kod, ale tylko na gałęzi kroku, nigdy na `main`.
- Merge przez squash, gdy krok ma dużo commitów roboczych. Po merge'u tag kroku `step/P<faza>.<krok>`, a gdy faza się kończy, także tag fazy: `phase-1-done`, `phase-2-done` itd. Szczegóły w sekcji 8.1.

### 7.3 ADR

Każda decyzja architektoniczna, której nie ma w tym pliku (np. wrapper CGI dla Fortrana, wybór biblioteki Raft, zmiana limitów pamięci), dostaje plik `docs/adr/NNNN-krotki-tytul.md`: kontekst, decyzja, konsekwencje. Jeśli ADR zmienia coś w tym pliku, zaktualizuj też CLAUDE.md.

---

## 8. Jak Claude ma pracować w tym repo

1. **Na początku sesji** wykonaj protokół startu z sekcji 8.1. Nie zaczynaj żadnej pracy przed nim.
2. **Rób jeden krok naraz**, chyba że użytkownik wyraźnie każe inaczej. Nie przeskakuj kroków, nie łącz faz.
3. **Przed krokiem** sprawdź jego zależności (kolumna „Wymaga”). Jeśli czegoś brakuje, zatrzymaj się i powiedz co.
4. **W trakcie kroku** trzymaj się kontraktów z sekcji 4. Zmiana kontraktu to osobny commit `contract(...)`.
5. **Na koniec kroku** spełnij Definition of Done (sekcja 9.1) i wykonaj protokół zamknięcia kroku z sekcji 8.1. Dopiero wtedy krok jest wykonany.
6. **Gdy coś nie działa w wybranym języku** (brak biblioteki, problem z ARM), nie zmieniaj języka na własną rękę. Zastosuj dozwolone obejście (wrapper, sidecar), opisz w ADR, a jeśli się nie da — zapytaj użytkownika.
7. **Tymczasowe skróty** (np. pętla Peano w ledgerze w fazie 1) oznacz w kodzie `// TEMPORARY(P3.3): <opis>` i usuń w kroku, który je zastępuje. `make lint` wyświetla listę pozostałych `TEMPORARY`.
8. **Nigdy** nie twórz zasobów w prawdziwym AWS bez wyraźnej zgody użytkownika w bieżącej rozmowie. Domyślnie wszystko idzie na Floci.
9. **Nigdy** nie dodawaj funkcji widocznych dla użytkownika spoza zakresu (sekcja 1).
10. Pilnuj RAM-u: po dodaniu serwisu sprawdź `docker stats` i zapisz zużycie w `docs/CAPACITY.md` serwisu.
11. **Każdy krok musi się zmieścić w jednej sesji.** Jeśli krok okazuje się za duży, przed rozpoczęciem podziel go na podkroki (`P2.13a`, `P2.13b`…), dopisz je do `docs/PROGRESS.md` i commitnij podział.
12. **Dokumentuj w trakcie, nie na końcu.** Kod bez docstringa, plik bez nagłówka albo serwis bez kompletu dokumentów z 6.5.5 to krok niezakończony. Dokumentacja ma być korporacyjna w tonie, ale prawdziwa w treści.

### 8.1 Stan pracy, snapshoty i sesje

Cel: użytkownik może zamknąć sesję po każdym kroku z pewnością, że krok jest zapisany, a nowa sesja Claude bez pytania wie, na jakim etapie jest projekt i co robić dalej. **Jedynym źródłem prawdy o postępie jest repozytorium**, nigdy pamięć poprzedniej rozmowy.

#### Pliki stanu

| Plik | Rola |
| --- | --- |
| `docs/PROGRESS.md` | Blok „Current State” na górze + pełna checklista wszystkich kroków ze statusami |
| `docs/progress/steps/P<faza>.<krok>.md` | Log kroku (snapshot): co zrobiono, jak zweryfikowano, commity, decyzje, co dalej |
| tag git `step/P<faza>.<krok>` | Snapshot repozytorium po zamknięciu kroku (da się do niego wrócić) |

Statusy kroku: `TODO`, `IN_PROGRESS`, `DONE`, `BLOCKED`. W danej chwili najwyżej jeden krok może być `IN_PROGRESS`.

Szablon bloku na górze `docs/PROGRESS.md`:

```markdown
# Progress

## Current State
| Field | Value |
| --- | --- |
| Current phase | Phase 1 — End-to-end skeleton |
| Last completed step | P1.3 — Event envelope and first JSON Schemas |
| Last completed at | 2026-10-20 18:42 CEST |
| Snapshot tag | step/P1.3 |
| Step in progress | none |
| Next step | P1.4 — expression-assembler (C#, SurrealDB) |
| Blockers | none |
| Milestones reached | — |

## Steps
| ID | Step | Status | Completed | Snapshot | Log |
| --- | --- | --- | --- | --- | --- |
| P0.1 | Repository initialization | DONE | 2026-10-17 | step/P0.1 | [log](progress/steps/P0.1.md) |
| ... | ... | ... | ... | ... | ... |
| P1.4 | expression-assembler (C#, SurrealDB) | TODO | | | |
```

Szablon logu kroku `docs/progress/steps/P1.4.md`:

```markdown
# P1.4 — expression-assembler (C#, SurrealDB)

| Field | Value |
| --- | --- |
| Status | DONE |
| Started | 2026-10-21 10:05 CEST |
| Completed | 2026-10-21 13:40 CEST |
| Branch | step/P1.4-expression-assembler |
| Commits | a1b2c3d, d4e5f6a |
| Snapshot tag | step/P1.4 |
| Depends on | P1.1, P1.2, P1.3 |

## Goal
What this step had to deliver (copied from CLAUDE.md, section 9.3).

## What Was Done
Concrete list of changes: services, files, contracts, configuration.

## Verification
Every command that proves the Definition of Done, with its result:
- `make build-expression-assembler` — passed
- `make test-expression-assembler` — 14 tests passed
- `make e2e` — not applicable yet (flow incomplete until P1.9)
- `make doc-coverage` — 100%

## Decisions
Decisions made during the step, with links to ADRs.

## Temporary Shortcuts
`TEMPORARY(...)` markers introduced, and the step that removes them.

## Notes for the Next Session
Anything the next session must know (gotchas, environment quirks, follow-ups).

## Checkpoints
(Filled only if the step was interrupted mid-way; see "Interrupting a step".)
```

#### Protokół startu sesji (zawsze, zanim cokolwiek zrobisz)

1. Przeczytaj `CLAUDE.md` i blok „Current State” w `docs/PROGRESS.md`.
2. Sprawdź repozytorium: `git status`, `git branch --show-current`, `git log --oneline -10`, `git tag --list 'step/*' --sort=-creatordate | head -5`.
3. Porównaj stan pliku z repo. Ostatni krok `DONE` musi mieć tag `step/...` i commit z trailerem `Step:` na `main`. Jeśli coś się nie zgadza, nie zgaduj: opisz rozbieżność użytkownikowi i zapytaj.
4. Ustal sytuację:
   - **Jest krok `IN_PROGRESS`** → przeczytaj jego log, szczególnie sekcję „Checkpoints”, przełącz się na jego gałąź i kontynuuj od „Next actions” z ostatniego checkpointu.
   - **Brak kroku w toku, czyste drzewo** → następny krok to „Next step” z „Current State”.
   - **Brak kroku w toku, ale brudne drzewo albo niezacommitowane zmiany** → nie ruszaj ich, pokaż użytkownikowi `git status` i zapytaj, co z nimi zrobić.
5. Opcjonalnie uruchom `make status` (skrót: wypisuje „Current State”, krok w toku i wynik `make up` + healthchecków).
6. Powiedz użytkownikowi w 2–3 zdaniach: na jakim etapie jest projekt, jaki krok jest następny (lub w toku) i co zamierzasz zrobić.

#### Protokół rozpoczęcia kroku

1. Upewnij się, że zależności kroku (kolumna „Wymaga”) mają status `DONE`.
2. Utwórz gałąź `step/P<faza>.<krok>-<krótki-opis>` z aktualnego `main`.
3. Ustaw krok na `IN_PROGRESS` w `docs/PROGRESS.md`, uzupełnij „Current State”, utwórz log kroku z sekcjami „Goal” i „Started”.
4. Commit: `chore(progress): start P1.4` z trailerem `Step: P1.4`.

#### Protokół zamknięcia kroku

Krok jest wykonany **dopiero wtedy**, gdy wszystkie punkty są spełnione:

1. Definition of Done (9.1) spełnione, a każda komenda weryfikacyjna wpisana z wynikiem do sekcji „Verification” logu.
2. Log kroku uzupełniony w całości, status `DONE`.
3. `docs/PROGRESS.md`: status `DONE`, data, tag, link do logu; „Current State” wskazuje następny krok; jeśli to koniec fazy, zaktualizowane „Milestones reached” i dodane release notes.
4. Commit: `chore(progress): complete P1.4` z trailerem `Step: P1.4`.
5. Merge gałęzi kroku do `main` (squash albo fast-forward; lokalnie, bez wymogu PR na GitHubie, jeśli użytkownik pracuje sam).
6. Tag na `main`: `git tag -a step/P1.4 -m "P1.4: expression-assembler"`. Jeśli faza się kończy, dodatkowo `phase-1-done`.
7. Drzewo robocze czyste (`git status` bez zmian), a jeśli jest zdalne repo, `git push --follow-tags`.
8. Wiadomość do użytkownika (po polsku), dokładnie w tym kształcie:

```
✅ Krok P1.4 zamknięty (snapshot: step/P1.4, commit a1b2c3d).
Następny krok: P1.5 — parser (OCaml, SQLite).
Możesz bezpiecznie zamknąć sesję.
```

Jeśli którykolwiek punkt się nie udał, krok **nie jest** zamknięty: zostaje `IN_PROGRESS`, a Claude mówi, czego brakuje.

#### Przerwanie kroku w połowie

Jeśli użytkownik chce skończyć sesję w trakcie kroku (albo kończy się kontekst):

1. Commitnij bieżącą pracę na gałęzi kroku: `chore(progress): checkpoint P1.4 (2/3)` (kod może być niedokończony, ale nie może psuć `main`, bo jest tylko na gałęzi).
2. Dopisz do logu kroku sekcję „Checkpoints” z wpisem: data, co jest gotowe, co nie działa, **Next actions** jako konkretna lista od czego zacząć.
3. Zostaw krok jako `IN_PROGRESS`, a w „Current State” wpisz „Step in progress: P1.4 (checkpoint 2)”.
4. Wiadomość do użytkownika:

```
⏸️ Krok P1.4 przerwany i zapisany (checkpoint 2 na gałęzi step/P1.4-expression-assembler).
Następna sesja zacznie od: <pierwsza pozycja z Next actions>.
Możesz bezpiecznie zamknąć sesję.
```

Nigdy nie zostawiaj niezacommitowanych zmian na koniec sesji.

#### Powrót do snapshotu

Jeśli krok trzeba cofnąć, użytkownik może wrócić do stanu po dowolnym kroku: `git checkout step/P1.3` (podgląd) albo nowa gałąź z tagu. Cofnięcie zamkniętego kroku robi się zawsze nowym krokiem lub ADR, nigdy przez przepisanie historii `main`.

---

## 9. Plan pracy

### 9.1 Definition of Done (każdy krok)

- [ ] Kod zbudowany: `make build` (albo `make build-<serwis>`) przechodzi.
- [ ] Testy jednostkowe serwisu przechodzą.
- [ ] `make up` startuje wszystko, co powinno działać na tym etapie, a healthchecki są zielone.
- [ ] `make e2e` przechodzi (jeśli krok dotyka przepływu dodawania).
- [ ] `make lint` przechodzi.
- [ ] README serwisu i ewentualne ADR są aktualne.
- [ ] `make doc-coverage` pokazuje 100% dla zmienionych serwisów (nagłówki plików, docstringi, `COMMENT ON` w migracjach).
- [ ] Komplet dokumentów z 6.5.5 dla nowego serwisu istnieje i jest wypełniony prawdziwą treścią; dla zmienionego serwisu zaktualizowane `CHANGELOG.md`, `API.md`, `DEPENDENCIES.md`, `RUNBOOK.md` (jeśli doszedł alert), `CAPACITY.md` (jeśli zmienił się RAM).
- [ ] `make docs` buduje portal bez ostrzeżeń.
- [ ] Commit(y) zgodne z sekcją 7 z trailerem `Step:`.
- [ ] Wszystko w repo po angielsku (kod, komentarze, docstringi, dokumentacja, commity).
- [ ] Protokół zamknięcia kroku z 8.1 wykonany w całości: log kroku, `docs/PROGRESS.md`, merge do `main`, tag `step/...`, czyste drzewo, komunikat do użytkownika.

### 9.2 Kamienie milowe

| Kamień | Po fazie | Co działa |
| --- | --- | --- |
| M1 | 1 | `2+3=5` przechodzi przez gateway, frontend pokazuje wynik |
| M2 | 2 | Prawdziwe Peano na serwisach cyfr z przeniesieniami |
| M3 | 3 | Saga, outbox, DLQ, ledger z łańcuchem hashy, odporność na padnięcie serwisu |
| M4 | 4 | Konsensus trzech replik |
| M5 | 6 | Pełna platforma i bezpieczeństwo |
| M6 | 8 | Wszystkie mikrofrontendy, licznik czasu |
| M7 | 10 | Faktury, AWS, komplet 35 serwisów |

### 9.3 Kroki

Format: `ID | Krok | Wymaga | Rezultat`.

#### Faza 0 — Fundament repozytorium

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P0.1 | Inicjalizacja repo: `.gitignore`, `.editorconfig`, `README.md`, `CLAUDE.md`, `docs/PROGRESS.md` (blok „Current State” + wszystkie kroki z tej sekcji ze statusem `TODO`), `docs/progress/steps/` z szablonem logu, `docs/adr/0001-record-architecture-decisions.md`; pierwszy krok zamknięty pełnym protokołem z 8.1 (tag `step/P0.1`) | — | Repo z systemem śledzenia postępu |
| P0.2 | `Makefile`: `up`, `down`, `ps`, `logs`, `build`, `build-%`, `test`, `test-%`, `e2e`, `lint`, `fmt`, `new-service`, `clean`, `status` (wypisuje „Current State”, krok w toku, ostatnie tagi `step/*` i stan kontenerów) | P0.1 | Wspólne komendy |
| P0.3 | Szkielet Compose: `docker-compose.yml` z `include`, pliki w `compose/`, sieci `public`/`services`/`data`, profile, `.env.example` | P0.2 | `make up` startuje pusty projekt |
| P0.4 | Szablon serwisu `templates/service/` i `scripts/new-service.sh <nazwa> <język>` generujący katalog, Dockerfile, README, healthcheck, wpis w Compose | P0.3 | Nowy serwis w 1 komendzie |
| P0.5 | Pre-commit: commitlint, hadolint, yamllint, shellcheck, sprawdzanie końców linii | P0.1 | Hooki działają |
| P0.6 | GitHub Actions: lint, build zmienionych serwisów (matrix po katalogach), testy, commitlint na PR | P0.5 | CI zielone |
| P0.7 | Szablony dokumentów w `templates/docs/` (wszystkie z 6.5.5), szablon nagłówka pliku per język, `new-service.sh` je kopiuje | P0.4 | Szablony |
| P0.8 | Dokumenty repozytorium z 6.5.6: CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CODEOWNERS, szablony PR i issue, governance, ONBOARDING, GLOSSARY, pierwszy wpis w RISK_REGISTER | P0.7 | Ład korporacyjny |
| P0.9 | `scripts/doc-check.sh` i `make doc-coverage` (z narzędziami z 6.5.4 dodawanymi wraz z językami), uruchamiane w CI | P0.6 | Egzekwowanie dokumentacji |
| P0.10 | Portal MkDocs Material (`mkdocs.yml`, `make docs`, `make docs-serve`), git-cliff (`cliff.toml`), C4: diagram kontekstu | P0.8 | Portal dokumentacji |

#### Faza 1 — Szkielet end-to-end (M1)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P1.1 | Redpanda + Redpanda Console w `compose/core.yml`, skrypt tworzący topiki z sekcji 4.2 | P0.3 | Topiki istnieją |
| P1.2 | `gateway`: Traefik z konfiguracją plikową (provider Redis dopiero w P5.4), routing `/api` i `/` | P0.3 | Gateway na porcie 80 |
| P1.3 | Koperta zdarzeń i JSON Schema dla `expression.submitted`, `addition.requested`, `result.voted`, `ledger.appended` w `contracts/events/` + walidacja przykładów w CI | P0.6 | Pierwsze kontrakty |
| P1.4 | `expression-assembler` (C#, SurrealDB): `POST /api/v1/keys`, składanie wyrażenia, publikacja zdarzeń, `202 {taskId}` | P1.1, P1.2, P1.3 | Kliknięcia trafiają do systemu |
| P1.5 | `parser` (OCaml, SQLite): konsumuje `expression.submitted`, buduje AST, publikuje `addition.requested` (bez walidatora i commutatora) | P1.4 | Wyrażenie rozebrane |
| P1.6 | `successor` (Haskell, CouchDB): `Next(n) = n+1` liczone natywnie, `// TEMPORARY(P2.13)` | P0.4 | Successor odpowiada |
| P1.7 | `ledger` (Nim, immudb): konsumuje `addition.requested`, woła successor `b` razy (`// TEMPORARY(P3.3)`), zapisuje wynik z hashem, `GET /api/v1/tasks/{id}` (`// TEMPORARY(P3.3)`, potem przejmie saga) | P1.5, P1.6 | Wynik zapisany |
| P1.8 | Tymczasowy frontend: `frontend/shell` z jedną stroną w czystym JS (klawiatura + wyświetlacz), `// TEMPORARY(P8.x)` | P1.4, P1.7 | Da się kliknąć 2+3= |
| P1.9 | `tests/e2e` (np. Playwright albo skrypt HTTP) z przypadkiem `2+3=5`, `make e2e` | P1.8 | **M1** |

#### Faza 2 — Cyfry, przeniesienia, rozbiór (M2)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P2.1 | `contracts/proto/` + `buf.yaml`, `buf.gen.yaml`, generowanie kodu dla Go, Rust, Haskell, OCaml, Elixir, C#, Crystal, Zig, Python; CI `buf lint` i `buf breaking` | P0.6 | Kontrakty gRPC |
| P2.2 | Kontrakt cyfry `contracts/http/digit.yaml` + test kontraktowy wspólny dla wszystkich cyfr (`tests/contract/digit.sh`) | P0.6 | Kontrakt cyfry |
| P2.3 | `digit-0` (C, SQLite) jako implementacja referencyjna | P2.2 | Cyfra 0 |
| P2.4 | `digit-1` (C++) | P2.3 | Cyfra 1 |
| P2.5 | `digit-2` (Fortran; dozwolony wrapper HTTP, ADR) | P2.3 | Cyfra 2 |
| P2.6 | `digit-3` (Free Pascal) | P2.3 | Cyfra 3 |
| P2.7 | `digit-4` (Lua) | P2.3 | Cyfra 4 |
| P2.8 | `digit-5` (Dart) | P2.3 | Cyfra 5 |
| P2.9 | `digit-6` (Swift) | P2.3 | Cyfra 6 |
| P2.10 | `digit-7` (Gleam) | P2.3 | Cyfra 7 |
| P2.11 | `digit-8` (D) | P2.3 | Cyfra 8 |
| P2.12 | `digit-9` (Racket), `next = 0`, `carry = true` | P2.3 | Komplet cyfr |
| P2.13 | `carry` (Elixir, Mnesia) + `successor` liczy n+1 przez serwisy cyfr i carry; usuń `TEMPORARY(P2.13)` | P2.1, P2.12 | Prawdziwe Peano |
| P2.14 | `validator` (Rust, MariaDB): zakres 0–99 999 | P2.1 | Walidacja |
| P2.15 | `commutator` (Zig, LMDB): a ≥ b | P2.1 | Mniej wywołań |
| P2.16 | `operator-registry` (Crystal, PostgreSQL): `+` → `addition` | P2.1 | Katalog operacji |
| P2.17 | `parser` woła validator, commutator, operator-registry | P2.14–P2.16 | Pełny rozbiór |
| P2.18 | E2E: `0+0`, `9+1`, `99+1`, `99999+1`, `3+5 == 5+3`, wartości poza zakresem → błąd | P2.17 | **M2** |

#### Faza 3 — Saga i niezawodność (M3)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P3.1 | `schema-registry` (Apicurio, PostgreSQL): rejestracja wszystkich schematów z `contracts/events/` przy starcie, producenci walidują przed wysłaniem | P1.3 | Rejestr schematów |
| P3.2 | Temporal server + UI + PostgreSQL w `compose/core.yml` | P0.3 | Temporal działa |
| P3.3 | `saga-orchestrator` (Go): `AdditionWorkflow`, aktywności `resolveDigits`, `successor`, continue-as-new co 1000, Query z postępem, `GET /api/v1/tasks/{id}`; usuń `TEMPORARY(P3.3)` z ledgera | P3.2, P2.18 | Saga liczy |
| P3.4 | Outbox w `saga_db` + `outbox-relay` (Debezium, outbox event router) publikuje `result.voted`; ledger konsumuje `result.voted` zamiast `addition.requested` | P3.3 | Gwarancja dostarczenia |
| P3.5 | `distributed-lock` (etcd) + ledger bierze blokadę `ledger-append` | P3.4 | Kolejność wpisów |
| P3.6 | `dead-letter` (Perl, MongoDB): `aaas.dlq.v1`, backoff, max 5 prób, sygnał `compensate` do sagi; wszyscy konsumenci wysyłają do DLQ | P3.3 | Ponowienia i kompensacja |
| P3.7 | `ledger`: `GET /api/v1/ledger/verify`, test na zmanipulowany wpis | P3.5 | Weryfikacja łańcucha |
| P3.8 | `tests/chaos`: ubicie `successor`, `carry` i `digit-5` w trakcie dodawania 500+500, wynik nadal 1000 | P3.6 | **M3** |

#### Faza 4 — Konsensus (M4)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P4.1 | `consensus` (Go + hashicorp/raft, BoltDB): 3 węzły, API `Vote` | P2.1 | Klaster Raft |
| P4.2 | Replika Python | P4.1 | 1/3 |
| P4.3 | Replika Rust | P4.1 | 2/3 |
| P4.4 | Replika COBOL (GnuCOBOL; dozwolony wrapper, ADR) | P4.1 | 3/3 |
| P4.5 | Saga woła `vote`; niezgodność z Peano → DLQ i `FAILED` | P4.2–P4.4, P3.6 | Głosowanie w przepływie |
| P4.6 | Wstrzykiwanie błędu (`FAULT_INJECT=off-by-one` w jednej replice): większość wygrywa; dwie błędne → `FAILED` | P4.5 | **M4** |

#### Faza 5 — Platforma

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P5.1 | `service-discovery` (Consul) + rejestracja wszystkich istniejących serwisów (biblioteka startowa per język albo sidecar, ADR) | P4.6 | Rejestr serwisów |
| P5.2 | `config-server` (PHP, MongoDB) + `AAAS_BOOTSTRAP=platform` w serwisach | P5.1 | Centralna konfiguracja |
| P5.3 | `secrets` (OpenBao): AppRole per serwis, hasła baz przeniesione z `.env` | P5.2 | Brak haseł w env |
| P5.4 | `gateway` przechodzi na provider Redis (trasy w Redisie, seed przy starcie) | P5.1 | Dynamiczny routing |

#### Faza 6 — Bezpieczeństwo i krawędź (M5)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P6.1 | `auth` (Keycloak, PostgreSQL): realm `aaas`, klient `frontend`, logowanie gościa, eksport realmu do `infra/keycloak/` | P5.3 | Logowanie |
| P6.2 | `rate-limiter` (Ruby, Redis): forwardAuth w Traefiku, weryfikacja JWT (JWKS), limity z sekcji 3 | P6.1 | Ochrona API |
| P6.3 | `idempotency` (Deno, Valkey): `Claim`/`MarkFailed`, użycie w expression-assembler | P6.2 | Idempotentny `=` |
| P6.4 | `feature-flags` (Unleash, PostgreSQL): flaga `addition_enabled`, sprawdzanie w operator-registry | P5.2 | Wyłącznik dodawania |
| P6.5 | Frontend: przepływ logowania, token w żądaniach; E2E z logowaniem gościa | P6.1–P6.4 | **M5** |

#### Faza 7 — Obserwowalność

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P7.1 | OTel Collector, Prometheus, Loki, Jaeger, Grafana z provisioningiem (`compose/observability.yml`) | P0.3 | Stos monitoringu |
| P7.2 | Instrumentacja wszystkich serwisów: trace przez HTTP, gRPC i zdarzenia | P7.1 | Jeden trace na dodawanie |
| P7.3 | Dashboardy: „Życie jednego dodawania”, „Successor/s”, per serwis (RAM, błędy, opóźnienia) | P7.2 | Dashboardy |
| P7.4 | Alertmanager: serwis down, DLQ rośnie, zadanie > 40 min, RAM hosta > 90% | P7.3 | Alerty |

#### Faza 8 — Mikrofrontendy (M6)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P8.1 | `frontend/shell` (single-spa): import mapa, układ kalkulatora, szyna `aaas:*`, logowanie z P6.5 | P6.5 | Powłoka |
| P8.2 | `frontend/display` (Elm): wyrażenie, status, wynik, polling `/tasks/{id}` | P8.1 | Wyświetlacz |
| P8.3 | `frontend/key-0` (React) | P8.1 | Przycisk |
| P8.4 | `frontend/key-1` (Vue) | P8.1 | Przycisk |
| P8.5 | `frontend/key-2` (Svelte) | P8.1 | Przycisk |
| P8.6 | `frontend/key-3` (Angular) | P8.1 | Przycisk |
| P8.7 | `frontend/key-4` (SolidJS) | P8.1 | Przycisk |
| P8.8 | `frontend/key-5` (Preact) | P8.1 | Przycisk |
| P8.9 | `frontend/key-6` (Lit) | P8.1 | Przycisk |
| P8.10 | `frontend/key-7` (Qwik) | P8.1 | Przycisk |
| P8.11 | `frontend/key-8` (Alpine.js) | P8.1 | Przycisk |
| P8.12 | `frontend/key-9` (Ember) | P8.1 | Przycisk |
| P8.13 | `frontend/key-plus` (htmx) | P8.1 | Przycisk |
| P8.14 | `frontend/key-equals` (Mithril): generuje `Idempotency-Key` | P8.1 | Przycisk |
| P8.15 | `frontend/key-clear` (czysty JS); usuń tymczasowy frontend z P1.8 | P8.3–P8.14 | Klawiatura kompletna |
| P8.16 | `stopwatch` (Kotlin/Ktor, TimescaleDB): start/stop z zdarzeń, SSE | P3.4 | Czas oficjalny |
| P8.17 | `frontend/timer` (Marko): licznik z SSE | P8.16 | **M6** |

#### Faza 9 — Faktury

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P9.1 | `billing` (Common Lisp/SBCL, Firebird): konsumuje `ledger.appended`, numeracja z blokadą `invoice-number`, idempotentna | P3.5 | Numery faktur |
| P9.2 | Szablon Typst: fikcyjny sprzedawca bez NIP, kwota 0,00 zł, wyraźny dopisek „Dokument humorystyczny, nie jest fakturą VAT”, `GET /api/v1/invoices/{taskId}.pdf` | P9.1 | PDF |
| P9.3 | `frontend/invoice-button` (Stencil) | P9.2, P8.1 | Pobieranie faktury |

#### Faza 10 — AWS (M7)

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P10.1 | Floci w profilu `aws-local`, zmienna `AWS_ENDPOINT_URL` w serwisach | P0.3 | Lokalny AWS |
| P10.2 | `infra/aws/` (OpenTofu): SQS, Lambda (poza VPC, reserved concurrency 1), DynamoDB (on-demand), IAM minimalne, CloudWatch retention 1 dzień, AWS Budgets alert 1 USD; `tofu apply` domyślnie na Floci | P10.1 | IaC |
| P10.3 | `cloud-notary` (Python Lambda): weryfikacja łańcucha, zapis do DynamoDB, testy na Floci | P10.2 | Notariusz |
| P10.4 | `ledger` wysyła wpis do SQS po zapisie (endpoint z konfiguracji) | P10.3 | Integracja |
| P10.5 | Wdrożenie na prawdziwe konto AWS **tylko po wyraźnej zgodzie użytkownika**: checklista z sekcji 10 | P10.4 | **M7** |

#### Faza 11 — Utwardzenie

| ID | Krok | Wymaga | Rezultat |
| --- | --- | --- | --- |
| P11.1 | k6: pomiar czasu wywołania successora, aktualizacja tabeli czasów w CLAUDE.md i README | M7 | Prawdziwe czasy |
| P11.2 | Audyt RAM: tabela zużycia per kontener w `docs/architecture.md`, korekta `mem_limit` | M7 | Mieści się w 16–32 GB |
| P11.3 | `docs/architecture.md`: diagramy Mermaid (przepływ, sieci, zdarzenia), linki do dashboardów | M7 | Dokumentacja |
| P11.4 | Audyt dokumentacji: 100% pokrycia we wszystkich serwisach, komplet dokumentów, diagramy C4 kontenerów i komponentów, katalog zdarzeń i API w portalu, przegląd RISK_REGISTER i DPIA | M7 | Dokumentacja klasy enterprise |
| P11.5 | Usunięcie wszystkich `TEMPORARY`, przegląd ADR, release notes całego projektu, `phase-11-done` | P11.1–P11.4 | Projekt kompletny |

#### Faza 12 — Publiczny dostęp (ODŁOŻONE)

Nie zaczynaj tej fazy, dopóki użytkownik o nią nie poprosi. Wstępny plan na później: Cloudflare Tunnel z komputera właściciela, logowanie gościa, ostrzejsze limity dla gości, globalna kolejka dużych dodawań, panele administracyjne za Cloudflare Access.

---

## 10. AWS — zasady bezpieczeństwa kosztów

- Używane usługi: **tylko** Lambda, SQS, DynamoDB (i CloudWatch Logs tworzone automatycznie). Wszystkie w limitach Always Free.
- Zakazane: EC2, RDS, NAT Gateway, VPC dla Lambdy, ELB, cokolwiek z opłatą godzinową.
- Lambda: reserved concurrency 1, timeout 10 s, pamięć 128 MB.
- CloudWatch Logs: retencja 1 dzień.
- AWS Budgets: alert przy 1 USD, plus alerty Free Tier w ustawieniach rozliczeń.
- Konto: istniejące konto użytkownika. Przed pierwszym `tofu apply` na prawdziwym AWS sprawdź z użytkownikiem w Billing, że nic na koncie nie nalicza opłat.
- Domyślny cel IaC i testów to Floci. Prawdziwe AWS tylko po wyraźnej zgodzie w bieżącej rozmowie.

---

## 11. Słownik

| Termin | Znaczenie |
| --- | --- |
| Peano | Dodawanie jako wielokrotne branie następnika: a + b = S(S(…S(a))) b razy |
| Saga | Długa transakcja rozpisana na kroki z kompensacją przy błędzie (tu: workflow Temporala) |
| Outbox | Wzorzec: zapis zdarzenia w tej samej transakcji co dane, publikacja przez CDC |
| DLQ | Dead Letter Queue, kolejka nieudanych zdarzeń |
| Continue-as-new | Mechanizm Temporala restartujący workflow z nową historią, żeby nie przekroczyć limitu zdarzeń |
| forwardAuth | Middleware Traefika, który pyta zewnętrzny serwis, czy przepuścić żądanie |
| ADR | Architecture Decision Record, krótki dokument decyzji |
| Krok | Pozycja z sekcji 9.3, identyfikator `P<faza>.<krok>` |
