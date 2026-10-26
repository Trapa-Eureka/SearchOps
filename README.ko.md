# SearchOps — Search Intelligence & API Monitoring

[English](README.md) · **한국어**

> **상태: Stage 2 (도메인 모델, 키워드 CRUD) 완료: 스키마, 검증, `/api/v1/keywords`가 구현되고 테스트됐습니다. SerpApi 검색은 아직 구현되지 않았습니다.**
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
| 1 | API 응답의 **정상·오류·빈 결과**를 각각 처리했는가? | `organic_results` 누락/빈 배열 처리, HTTP 200이어도 본문의 오류 페이로드를 감지, 인증·쿼터·레이트리밋·일시적 네트워크·타임아웃·잘못된 요청·스키마 이상으로 오류 분류, 각각 픽스처 테스트 | Stage 3 | [ ] |
| 2 | 검색 API가 **느리거나 실패해도** 서비스가 정상 동작하는가? | 연결/읽기 타임아웃, 일시적 오류만 지수 백오프+지터로 제한 재시도(`Retry-After` 존중), 최종 실패 시 마지막 성공 스냅샷을 **stale 표시**로 유지, 인증/잘못된 요청은 재시도 안 함 | Stage 4 | [ ] |
| 3 | 검색 요청 **중복을 방지**하고 **사용량을 관리**하는가? | 정규화 쿼리+엔진+로케일+설정+시간창 **핑거프린트**로 멱등 잡 및 동시 중복 실행 방지, 캐시 TTL과 `cache_hit` 기록, 일일 요청 예산·동시성 제한 (한도는 계정/공식 문서에서 확인, 하드코딩 금지) | Stage 4 | [ ] |
| 4 | 검색 결과의 **순위 변화를 정확하게** 계산하는가? | 호스트명 정규화 후 대상 도메인 매칭(정확/서브도메인 규칙 정의·테스트), 순위 부재는 `NULL`("조회 범위 내 없음", 0 아님), 검색 설정이 같은 스냅샷끼리만 비교, 작은 숫자 = 더 좋은 순위 | Stage 3 | [ ] |
| 5 | **RSpec** 등으로 핵심 로직을 테스트했는가? | 정규화기, 도메인 매칭, 순위 delta, 핑거프린트, 플랜 검증기, 예산 규칙 단위 테스트 + 요청/통합 테스트 + 프로바이더 어댑터(정상/빈/4xx/429/5xx/타임아웃/깨진 JSON) + Laya 어댑터(미지원 의도, 프롬프트 인젝션, 타임아웃, 비활성) | 전 단계, Stage 7 | [ ] |
| 6 | 검색 **실행 시간과 오류 원인**을 로그로 확인할 수 있는가? | `SearchRun`에 시작/종료·업스트림 지연·오류 분류·캐시 출처 저장, 구조화 로그, p50/p95·성공/실패·오류 분류별 건수·캐시 적중률·업스트림 호출 수 집계(`/api/v1/metrics/summary`). 검색어·비밀값은 로그에서 최소화 | Stage 4 | [ ] |
| 7 | **Laya 없이도** 핵심 흐름이 동작하는가? | `LAYA_ENABLED=false`에서 키워드 등록 → 검색 → 스냅샷 → 비교 → 스케줄 점검 전부 동작. 자연어는 안전한 폴백(명확화 요청)만 반환 | Stage 5 | [ ] |
| 8 | 자연어 계획이 **검증·확인** 후에만 실행되는가? | 알려진 필드만 허용(화이트리스트), 낮은 신뢰도/무효/불가 시 임의 검색 금지, 비용이 큰 검색은 사용자 확인 후 실행 | Stage 5 | [ ] |

## 범위

**MVP에 포함**: 키워드 CRUD, Google organic 검색(SerpApi), 정규화·스냅샷 저장, 순위 이력, 스케줄 점검(Active Job), 캐시/재시도/예산, 메트릭, Laya 의도 분류(선택), Next.js 대시보드.

**MVP 제외(non-goals)**: Jev, 멀티 에이전트, 자율 브라우징, 프록시/CAPTCHA 우회, 자체 스크래퍼, 대규모 크롤링, 결제, 멀티 테넌트 RBAC. 또한 검색 결과에 대한 근거 없는 LLM 서술, "전역 순위" 주장(순위는 *특정 쿼리·위치·기기·스냅샷 시점*의 값)은 하지 않습니다.

## 기술 스택 (설치 버전 확인 후 확정)

- Backend: Ruby, Rails(API mode), Active Record, PostgreSQL, RSpec(또는 Minitest 중 하나로 통일)
- Jobs: Active Job (로컬은 호환 어댑터 → 운영은 Solid Queue 또는 Sidekiq 중 하나)
- 검색: SerpApi (공식 Ruby 클라이언트 호환 확인 시 사용, 아니면 명시적 타임아웃의 얇은 HTTPS 어댑터)
- Frontend: Next.js, React, TypeScript, Tailwind
- 의도 분류(선택): Laya — `LayaClassifier` 인터페이스 뒤에 어댑터로 격리 (조사 결과는 [docs/discovery.md](docs/discovery.md))

## 진행 단계

각 단계가 끝나면 요약과 커밋 메시지를 제시하고, 사용자 확인 후에만 다음 단계로 진행합니다.

| Stage | 내용 | 상태 |
|-------|------|------|
| 0 | Discovery & baseline (`docs/discovery.md`) | 완료 |
| 1 | Ruby/Rails 기초, Rails API 스캐폴드, `/health` | 완료 |
| 2 | 도메인 모델, REST API (Keyword CRUD) | 완료 — 확인 대기 |
| 3 | SerpApi 연동, 정규화, 순위 추적 | 대기 |
| 4 | 스케줄 잡, 캐시, 복원력, 메트릭 | 대기 |
| 5 | Laya 사전 분류기 연동 | 대기 |
| 6 | Next.js 대시보드 | 대기 |
| 7 | 테스트 · 비교 실험(A/B/C) · 벤치마크 | 대기 |
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
bin/rails server              # 이후: curl localhost:3000/health
```

`GET /health`는 `200 {"status":"ok","database":"up"}`를 반환하고, DB에 연결할 수 없으면 `503 {"status":"degraded","database":"down"}`을 반환합니다(내부 오류 내용은 응답에 노출하지 않고 로그에 오류 클래스만 남깁니다). Rails 기본 `GET /up`도 그대로 있습니다.

## API

Stage 2에서 `/api/v1/keywords` 키워드 CRUD(검증, 정규화, 페이지네이션, 공통 JSON 오류 형식)를 제공합니다. 전체 계약, 데이터 모델, 알려진 제한은 [docs/api-contract.md](docs/api-contract.md)(영어)를 참고하세요. 아직 인증이 없으므로 로컬에서만 실행하세요.

## 설정

실제 값은 `backend/.env`에만 두고 커밋하지 않습니다. `backend/.env.example`에는 자리표시자만 있습니다. 검색 관련 변수는 Stage 3~5에서 사용하기 전까지는 자리표시자입니다.

```dotenv
SERPAPI_API_KEY=replace_me
LAYA_ENABLED=false
SEARCH_MAX_REQUESTS_PER_DAY=5
SEARCH_CACHE_TTL_SECONDS=3600
SEARCH_MAX_KEYWORDS=50
```

개발/테스트 환경은 `config/database.yml`을 통해 로컬 PostgreSQL(`searchops_development`, `searchops_test`)을 사용합니다. `DATABASE_URL`은 선택적 덮어쓰기용입니다.

> 검색 로직 테스트 결과, 벤치마크, 스크린샷은 **실제로 검증된 뒤에** 이 문서에 추가합니다.
