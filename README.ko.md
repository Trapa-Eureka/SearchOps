# SearchOps — Search Intelligence & API Monitoring

[English](README.md) · **한국어**

> **상태: Stage 7 (테스트 · 비교 실험(A/B/C) · 벤치마크) 완료: 백엔드 spec 863개(라인 95.9%, 분기 91.3% 커버; 엔드투엔드 여정 15개 포함), 프런트엔드 테스트 358개, 그리고 시드가 고정된 가짜 공급자 위에서 구조화 검색·Laya 경유 자연어·Laya 장애 상황을 비교했습니다(SerpApi는 한 번도 호출하지 않았습니다). 새로 쓴 보류 문장 80개에서 Laya 의도 정확도는 **71%**(한국어 47%)이고, 확신해서 낸 답 다섯 중 하나는 틀리며, 자연어는 과업당 약 85 ms를 더하면서 폼으로 못 하는 과업을 해내지는 못합니다. Laya가 응답 없이 멈추면 문장마다 4초가 듭니다. 자세한 내용: [docs/benchmarks.md](docs/benchmarks.md), [docs/intent-eval.md](docs/intent-eval.md). `job_search`는 이해하지만 아직 실행할 수 없습니다(`google_jobs` 엔진 없음).**
> 아래 체크리스트는 이 프로젝트가 **끝났을 때 "예"라고 답할 수 있어야 하는 기준**이며, 구현된 항목에만 `[x]`를 표시합니다.

SearchOps는 [SerpApi](https://serpapi.com)로 키워드 검색을 실행하고, 결과를 스냅샷으로 저장해 **대상 도메인의 순위 변화**를 추적하며, **API 호출의 지연·오류·캐시·사용량**을 관찰하는 웹 애플리케이션입니다. Ruby/Rails를 학습하면서 운영 관점(안정성, 관측성, 테스트)을 갖춘 서비스를 만드는 것이 목적입니다.

자연어 요청(예: "필리핀에서 원격 React 채용공고 중 지난주 이후 새 공고만")은 선택 기능인 [Laya](https://github.com/NandhaKishorM/laya)로 **의도만 분류**해 검증된 검색 계획(SearchPlan)으로 바꾸고, 실행은 항상 Rails가 맡습니다. **Laya 없이도 핵심 검색 흐름은 100% 동작해야 합니다.**

> SerpApi 및 Laya와 제휴·보증 관계가 없는 개인 학습 프로젝트입니다.

## 핵심 원칙

1. **결정적(deterministic) 경로 우선** — 구조화 검색, 스케줄 점검, 이력 조회는 Laya를 거치지 않습니다 (`LAYA_ENABLED=false`에서도 전부 동작).
2. **Laya 출력은 신뢰하지 않는 입력** — 제안(proposal)일 뿐이며, Rails가 intent/engine/locale/query/한도를 서버에서 재검증합니다.
3. **근거 없는 주장 금지** — 저장된 스냅샷과 SerpApi 응답에 있는 필드만 보여줍니다. 과거 데이터가 없으면 "기준(baseline) 스냅샷만 생성 가능"이라고 말합니다.
4. **비밀값은 서버에만** — API 키는 환경변수로만 다루며 git, 프런트 번들, 로그, 픽스처, README에 넣지 않습니다.
5. **검증된 사실만** — SerpApi 응답 필드와 Laya 인터페이스는 공식 문서/실제 소스로 확인한 것만 사용합니다. 확인 못 한 것은 가정으로 표시하고 mock으로 테스트합니다.

## 아키텍처 (목표)

```text
Next.js + TypeScript + Tailwind dashboard
      |
      |-- 구조화 키워드 / 스케줄 요청 -------------> Rails REST API
      |
      `-- 자연어 요청 --> Rails endpoint --> Laya adapter (분류만)
                                               |
                                               v
                                       검증된 SearchPlan
                                               |
                                               v
                                    Rails Search Orchestrator
                                      |         |         |
                                      v         v         v
                                   DB/cache  Active Job  SerpApi
                                      \         |         /
                                       v        v        v
                                     정규화된 스냅샷 → 이력 · 메트릭 · UI
```

보안 경계: 프런트는 Rails하고만 통신하고, 외부 호출은 Rails만 수행합니다. 백그라운드 잡은 Laya를 우회합니다.

## 품질 체크리스트 (완료 기준)

| # | 질문 | 계획된 접근 | 관련 단계 | 상태 |
|---|------|-------------|-----------|------|
| 1 | API 응답의 **정상·오류·빈 결과**를 각각 처리했는가? | `organic_results` 누락/빈 배열 처리, HTTP 200이어도 본문의 오류 페이로드를 감지, 인증·쿼터·레이트리밋·일시적 네트워크·타임아웃·잘못된 요청·스키마 이상으로 오류 분류, 각각 픽스처 테스트 | Stage 3 | [x] |
| 2 | 검색 API가 **느리거나 실패해도** 서비스가 정상 동작하는가? | 연결/읽기 타임아웃, 일시적 오류만 지수 백오프+지터로 제한 재시도(`Retry-After` 존중), 최종 실패 시 마지막 성공 스냅샷을 **stale 표시**로 유지, 인증/잘못된 요청은 재시도 안 함 | Stage 4 | [x] |
| 3 | 검색 요청 **중복을 방지**하고 **사용량을 관리**하는가? | 정규화 쿼리+엔진+로케일+위치 **핑거프린트**로 멱등 잡 및 동시 중복 실행 방지(시간창은 핑거프린트가 아니라 캐시 TTL로 적용), 캐시 TTL과 `cache_hit` 기록, 일일 요청 예산·동시성 제한 (한도는 계정/공식 문서에서 확인, 하드코딩 금지) | Stage 4 | [x] |
| 4 | 검색 결과의 **순위 변화를 정확하게** 계산하는가? | 호스트명 정규화 후 대상 도메인 매칭(정확/서브도메인 규칙 정의·테스트), 순위 부재는 `NULL`("조회 범위 내 없음", 0 아님), 검색 설정이 같은 스냅샷끼리만 비교, 작은 숫자 = 더 좋은 순위 | Stage 3 | [x] |
| 5 | **RSpec** 등으로 핵심 로직을 테스트했는가? | 정규화기, 도메인 매칭, 순위 delta, 핑거프린트, 플랜 검증기, 예산 규칙 단위 테스트 + 요청/통합 테스트 + 프로바이더 어댑터(정상/빈/4xx/429/5xx/타임아웃/깨진 JSON) + Laya 어댑터(미지원 의도, 프롬프트 인젝션, 타임아웃, 비활성) | 전 단계, Stage 7 | [x] |
| 6 | 검색 **실행 시간과 오류 원인**을 로그로 확인할 수 있는가? | `SearchRun`에 시작/종료·업스트림 지연·오류 분류·캐시 출처 저장, 구조화 로그, p50/p95·성공/실패·오류 분류별 건수·캐시 적중률·업스트림 호출 수 집계(`/api/v1/metrics/summary`). 검색어·문장·비밀값은 로그에서 제외(요청 파라미터와 SQL 값 필터링, `spec/requests/logging_spec.rb`) | Stage 4 | [x] |
| 7 | **Laya 없이도** 핵심 흐름이 동작하는가? | `LAYA_ENABLED=false`에서 키워드 등록 → 검색 → 스냅샷 → 비교 → 스케줄 점검 전부 동작. 자연어는 안전한 폴백(명확화 요청)만 반환 | Stage 5 | [x] |
| 8 | 자연어 계획이 **검증·확인** 후에만 실행되는가? | 알려진 필드만 허용(화이트리스트), 낮은 신뢰도/무효/불가 시 임의 검색 금지, 비용이 큰 검색은 사용자 확인 후 실행 | Stage 5 | [x] |

## 범위

**MVP에 포함**: 키워드 CRUD, Google organic 검색(SerpApi), 정규화·스냅샷 저장, 순위 이력, 스케줄 점검(Active Job), 캐시/재시도/예산, 메트릭, Laya 의도 분류(선택), Next.js 대시보드.

**MVP 제외(non-goals)**: Jev, 멀티 에이전트, 자율 브라우징, 프록시/CAPTCHA 우회, 자체 스크래퍼, 대규모 크롤링, 결제, 멀티 테넌트 RBAC. 또한 검색 결과에 대한 근거 없는 LLM 서술, "전역 순위" 주장(순위는 *특정 쿼리·위치·기기·스냅샷 시점*의 값)은 하지 않습니다.

## 기술 스택 (설치 버전 확인 후 확정)

- Backend: Ruby, Rails(API mode), Active Record, PostgreSQL, RSpec(또는 Minitest 중 하나로 통일)
- Jobs: Solid Queue 기반 Active Job (같은 PostgreSQL에 저장, Redis 불필요), 스케줄 점검은 반복 작업(recurring)으로 실행
- 검색: SerpApi (공식 Ruby 클라이언트 호환 확인 시 사용, 아니면 명시적 타임아웃의 얇은 HTTPS 어댑터)
- Frontend: Next.js(App Router), React, TypeScript, Tailwind, 데이터 조회는 SWR, 테스트는 Vitest + Testing Library + axe-core. 같은 출처의 `/api` 프록시로 Rails하고만 통신하므로 CORS 설정이 필요 없고 브라우저에 인증 정보가 없습니다
- 의도 분류(선택): 로컬 `laya-serve`로 실행하는 Laya(`multilingual` 체크포인트), `Intent::LayaClassifier` 뒤에 격리. 계약과 검증 내용: [docs/laya-contract.md](docs/laya-contract.md), 측정한 정확도: [docs/intent-eval.md](docs/intent-eval.md) (영어)

## 진행 단계

각 단계가 끝나면 요약과 커밋 메시지를 제시하고, 사용자 확인 후에만 다음 단계로 진행합니다.

| Stage | 내용 | 상태 |
|-------|------|------|
| 0 | Discovery & baseline (`docs/discovery.md`) | 완료 |
| 1 | Ruby/Rails 기초, Rails API 스캐폴드, `/health` | 완료 |
| 2 | 도메인 모델, REST API (Keyword CRUD) | 완료 |
| 3 | SerpApi 연동, 정규화, 순위 추적 | 완료 |
| 4 | 스케줄 잡, 캐시, 복원력, 메트릭 | 완료 |
| 5 | Laya 사전 분류기 연동 | 완료 |
| 6 | Next.js 대시보드 | 완료 |
| 7 | 테스트 · 비교 실험(A/B/C) · 벤치마크 | 완료 — 확인 대기 |
| 8 | 배포 · 운영 | 대기 |

## 로컬 실행 (macOS, Homebrew Ruby 4.0.3, Rails 8.1.4, PostgreSQL 16에서 검증)

```bash
brew services start postgresql@16
gem install rails
# Homebrew Ruby의 gem 실행 파일은 기본적으로 PATH에 없습니다:
export PATH="$(gem env gemdir)/bin:$PATH"

cd backend
cp .env.example .env          # 자리표시자만 있음. 실제 값은 git에서 제외된 .env에만 둡니다
bundle install
bin/rails db:create db:migrate

bundle exec rspec             # 테스트
bundle exec rubocop           # 린트
bin/rails server              # API + 백그라운드 워커 (개발 환경에서는 Solid Queue가 Puma 안에서 실행됨)
                              # 이후: curl localhost:3000/health
```

`GET /health`는 `200 {"status":"ok","database":"up"}`를 반환하고, DB에 연결할 수 없으면 `503 {"status":"degraded","database":"down"}`을 반환합니다(내부 오류 내용은 응답에 노출하지 않고 로그에 오류 클래스만 남깁니다). Rails 기본 `GET /up`도 그대로 있습니다.

## 테스트와 벤치마크

```bash
cd backend
bundle exec rspec                       # 863개, 약 14초. spec/e2e(API를 통한 전체 여정) 포함
COVERAGE=1 bundle exec rspec            # 라인·분기 커버리지는 coverage/index.html
cd ../frontend && pnpm test             # 358개 테스트

# A/B/C 비교: scripts/laya-serve.sh 실행과, 이름이 *_bench인 임시 DB가 필요합니다(모드 사이에 모든 행을 지웁니다)
createdb searchops_bench
DATABASE_URL=postgresql:///searchops_bench RAILS_ENV=development bin/rails db:migrate
DATABASE_URL=postgresql:///searchops_bench RAILS_ENV=development bin/rails searchops:benchmark
```

비교는 순위 확인 과업 20개(와 그 밖의 문장 60개)를 실제 Rails 스택에서 세 가지 방식으로 실행합니다: 키워드 폼(A), Laya를 거친 문장과 확인 단계(B), Laya 장애(C). 검색 공급자는 지연과 실패를 가정한 시드 고정 가짜이므로, SerpApi가 아니라 앱이 더하는 부분을 측정합니다. 결과를 요약하면, 자연어는 폼으로 못 하는 과업을 해내지 못했고 과업당 약 85 ms를 더했으며 폼보다 더 많은 글자를 입력하게 했습니다. 계획을 읽지 않고 확인하면 과업 20개당 호출 약 5회가 잘못된 시장에 쓰였고(신중한 사람의 호출 위에 약 5분의 1), Laya가 응답 없이 멈추면 문장마다 4초가 듭니다. 전체 방법, 표, 한계는 [docs/benchmarks.md](docs/benchmarks.md)(영어)를 참고하세요.

설계를 고정한 뒤 새로 쓴 보류 문장 80개에서 의도 정확도는 71%(한국어 47%, 일본어 43%)이고 확신해서 낸 답의 20%가 틀렸습니다. 튜닝에 쓴 이전 테스트 분할의 77%와 대비됩니다. 자세한 내용과 발견한 실패는 [docs/intent-eval.md](docs/intent-eval.md)(영어)를 참고하세요.

## 대시보드

```bash
cd frontend
cp .env.example .env.local    # API_BASE_URL=http://127.0.0.1:3000 (서버 측 전용, 브라우저로 전송되지 않음)
pnpm install
pnpm dev                      # http://localhost:3001 — 먼저 Rails 서버(3000번 포트)를 실행하세요

pnpm test                     # 358개 테스트 (axe 접근성·색 대비 검사 포함)
pnpm typecheck && pnpm lint
pnpm build && pnpm start
```

화면: **개요**(성공률, 중앙값·p95 지연, 캐시 적중률, 예산 같은 핵심 수치, 처리 결과별 누적 막대로 본 시간대별 요청 차트, 순위·최근 검색 띠·p95 지연이 있는 추적 키워드(오래된 데이터 우선)), **키워드**(같은 표에 생성·일시중지·지금 검색 동작), **키워드 상세**(키워드 간 전환 띠, 순위 차트와 표, 검색 실행 목록, 대상 도메인을 강조한 저장된 결과), **API 상태**(모든 핵심 수치, 요청 차트, 요청 타임라인, 원인별 실패, 재시도, 큐·워커 상태, 오래된 키워드, 상태별 개수가 붙은 필터 가능한 기록), **플래너**(문장, 제안된 계획, 수정 후 확인 또는 되묻기). 사이드바에는 오래된 데이터의 키워드 수와 최근 24시간 실패한 검색 수가 표시됩니다. UI는 영어와 한국어를 지원합니다.

알아둘 동작: **순위 숫자가 작을수록 좋으며** 차트에도 그렇게 표시합니다. 찾지 못한 순위는 별도의 "찾을 수 없음" 영역에 그리고 0위로 표시하지 않습니다. 오래된(stale) 데이터에는 마지막 정상 결과의 시각을 붙입니다. 캐시 적중은 데이터가 처음 수집된 시각을 보여줍니다. 상태는 색만으로 구분하지 않고 항상 글자와 기호로 표시합니다. 모든 숫자는 Rails API에서 가져오며, 데이터가 없으면 지어낸 값 대신 대시(—)와 설명을 보여줍니다. 차트의 각 결과는 색뿐 아니라 무늬로도 구분하며, 같은 수치를 스크린 리더용 표로도 제공합니다. 대시보드를 위해 `GET /api/v1/options`(허용 값과 한도), `GET /api/v1/searches`(키워드 전체의 최근 실행과 상태별 개수), `GET /api/v1/metrics/summary`의 시계열, 각 키워드의 `activity` 요약을 추가했습니다. 아직 인증이 없으므로 로컬에서만 실행하세요.

## API

`/api/v1/keywords` 키워드 CRUD, 비동기 검색(`POST/GET /api/v1/keywords/:id/searches`), 순위 이력(`GET /api/v1/keywords/:id/rank_history`), 메트릭(`GET /api/v1/metrics/summary`), 대시보드용 `GET /api/v1/options`·`GET /api/v1/searches`를 검증, 페이지네이션, 공통 JSON 오류 형식과 함께 제공합니다. 선택 기능인 자연어 계획은 `POST /api/v1/intent/plan`, `POST /api/v1/intent/plan/:id/confirm`입니다. 전체 계약, 실패 매핑, 재시도·캐시·예산 규칙, 알려진 제한은 [docs/api-contract.md](docs/api-contract.md)(영어)를 참고하세요.

검색은 요청 안에서 SerpApi를 호출하지 않습니다. 요청을 큐에 넣으면 워커가 호출을 수행하고, 클라이언트는 실행(run)을 조회해서 결과를 확인합니다.

```bash
curl -s -X POST localhost:3000/api/v1/keywords/1/searches    # 202 {"meta":{"outcome":"enqueued"},"data":{"id":7,"status":"queued",...}}
curl -s localhost:3000/api/v1/keywords/1/searches/7          # 몇 초 뒤: "status":"succeeded" (또는 "failed" + error_category)
curl -s -X POST localhost:3000/api/v1/keywords/1/searches    # TTL 안에 다시: 200 {"meta":{"outcome":"cache_hit"},...}, SerpApi 호출 없음
curl -s -X POST "localhost:3000/api/v1/keywords/1/searches?refresh=true"   # 캐시 무시
curl -s localhost:3000/api/v1/metrics/summary                # p50/p95, 오류 분류, 캐시 적중률, 예산, 큐 상태
bin/rails searchops:serpapi_quota                            # SerpApi 플랜과 남은 검색 횟수 (무료 Account API)
```

실제 검색을 하려면 `backend/.env`의 `SERPAPI_API_KEY`에 SerpApi 키를 넣고 서버를 재시작하세요. 실제 SerpApi 호출은 `SEARCH_MAX_REQUESTS_PER_DAY`로 집계되며(재시도 포함) 캐시 적중은 무료입니다. 스케줄(`daily`/`weekly`) 키워드는 서버 또는 `bin/jobs`가 실행 중일 때 반복 작업이 자동으로 검색합니다. 아직 인증이 없으므로 로컬에서만 실행하세요.

### 자연어 계획 (선택, Laya 필요)

Laya는 문장의 의도만 분류합니다. 세부 값 추출, 닫힌 필드 집합에 대한 검증, 확인 후 실행은 Rails가 합니다. Laya가 꺼져 있거나(기본값) 죽어 있으면 구조화 입력 폴백으로 응답하고, 나머지 API는 영향을 받지 않습니다.

```bash
scripts/laya-setup.sh          # 최초 1회: tools/laya에 격리된 Python 환경, laya==0.4.15 (체크포인트가 이미 캐시에 있으면 재사용, 없으면 약 1.45GB 다운로드)
scripts/laya-serve.sh          # 별도 터미널에서: http://127.0.0.1:8765, multilingual 체크포인트
# backend/.env: LAYA_ENABLED=true   (이후 Rails 서버 재시작)

curl -s -X POST localhost:3000/api/v1/intent/plan -H 'Content-Type: application/json' \
  -d '{"text":"example.com이 '"'"'react 개발자'"'"'로 구글 한국에서 몇 위인지 지난주와 비교해서 확인해줘"}'
# 201 {"data":{"id":12,"status":"ready","next_step":"confirm","plan":{"intent":"organic_rank_tracking",...},...}}
curl -s -X POST localhost:3000/api/v1/intent/plan/12/confirm    # 키워드를 만들고 검색 1건을 큐에 넣음 (예산·캐시 적용)
LAYA_ENABLED=true bin/rails "searchops:intent_eval[dev]"        # 라벨된 문장으로 정확도 리포트
```

기대할 점: 프로젝트의 대표 예시 문장(한국어 채용공고 검색)은 실제 모델이 `unsupported` 0.56으로 판단해서 계획이 아니라, 국가·검색어·플래그가 미리 채워진 되묻기로 끝납니다. 채용공고 검색은 아직 확인(실행)할 수 없습니다.

## 설정

실제 값은 `backend/.env`에만 두고 커밋하지 않습니다. `backend/.env.example`에는 자리표시자만 있습니다. 검색 관련 변수는 Stage 3~5에서 사용하기 전까지는 자리표시자입니다.

```dotenv
SERPAPI_API_KEY=replace_me
LAYA_ENABLED=false            # 선택 기능인 자연어 계획. 핵심 흐름은 필요로 하지 않음
SEARCH_MAX_REQUESTS_PER_DAY=5
SEARCH_CACHE_TTL_SECONDS=3600
SEARCH_MAX_CONCURRENCY=2
SEARCH_MAX_KEYWORDS=50
LAYA_URL=http://127.0.0.1:8765
LAYA_MIN_CONFIDENCE=0.7
INTENT_RETENTION_DAYS=30
```

개발/테스트 환경은 `config/database.yml`을 통해 로컬 PostgreSQL(`searchops_development`, `searchops_test`)을 사용합니다. `DATABASE_URL`은 선택적 덮어쓰기용입니다.

> 검색 로직 테스트 결과, 벤치마크, 스크린샷은 **실제로 검증된 뒤에** 이 문서에 추가합니다.
