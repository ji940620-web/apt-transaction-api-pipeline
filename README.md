# 아파트 실거래가 데이터 파이프라인

> 국토교통부 아파트 매매·전월세 실거래가 API를 GitHub Actions로 매주 증분 수집해 BigQuery에 적재하고,
> SQL 뷰·마트로 정제·집계해 Looker Studio 대시보드로 제공하는 엔드투엔드 파이프라인입니다.

- 📊 **대시보드**: [Looker Studio](https://datastudio.google.com/reporting/406c0bd6-f216-4dd5-b817-d774245937bf)
- 📝 **프로젝트 정리 (Notion)**: [분석 과정과 의사결정 기록](https://torpid-feet-180.notion.site/41a578f0feb6806d8db4d5514f8f8021?source=copy_link)
- 📐 **지표 정의**: [docs/metrics.md](docs/metrics.md) · 🔎 **분석 기록**: [docs/findings_log.md](docs/findings_log.md)

| 항목 | 내용 |
|---|---|
| 데이터 | 전국 시군구 아파트 매매 약 98만 건, 전월세 약 197만 건 (2025-01 이후, 2025-01은 수집 시작월이라 일부만 포함) |
| 기준 | 2026-11-16 수집분 |
| 수집 주기 | 매주 월요일 03:00 매매 / 03:30 전월세 (KST), 최근 3개월 재수집 |
| 스택 | Python (requests, pandas) · GitHub Actions · BigQuery SQL · Looker Studio |

## 아키텍처

```
공공데이터포털 API (RTMSDataSvcAptTrade / RTMSDataSvcAptRent)
        │  src/incremental_collector*.py  ← GitHub Actions cron (주 1회)
        ▼
  transaction_staging / rent_staging     WRITE_TRUNCATE
        │  BEGIN TRANSACTION: 대상 연월 DELETE → INSERT → COMMIT
        ▼
  transaction_raw / rent_raw             원천 테이블 (API 컬럼 그대로)
        │  sql/views
        ▼
  v_sales · v_rents → v_sales_clean      정제 계층
        │
        ├──▶ m_region_monthly · m_sido_monthly · m_sido_pace · m_complex_ratio   집계 마트
        └──▶ lk_deals                    Looker Studio용 거래 단위 테이블
                                          ▼
                                   Looker Studio 대시보드
```

### 증분 수집 설계

- **최근 3개월 재수집**: 실거래 신고 기한이 계약 후 30일이라 지난달 데이터도 계속 늘어납니다. 매주 최근 3개월을 통째로 다시 받아 교체합니다.
- **staging → 트랜잭션 교체**: staging에 먼저 적재하고, 본 테이블의 대상 연월 DELETE + INSERT를 한 트랜잭션으로 묶어 중간 실패 시 자동 롤백됩니다.
- **실패 시 적재 중단**: 요청 1건이라도 실패하거나 결과가 0건이면 기존 데이터를 건드리지 않고 Actions를 실패로 종료합니다.
- **API 한도 보호**: 429 / `LIMITED_NUMBER` 감지 시 모든 스레드를 즉시 중단 (429는 재시도하지 않음 — 재시도도 호출 횟수를 소모).
- **스키마 변화 감지**: 전월세 `deposit` NULL 비율이 1%를 넘으면 응답 필드명 변경으로 보고 적재를 막습니다.

## 데이터 계층

| 계층 | 객체 | 역할 |
|---|---|---|
| Raw | `transaction_raw`, `rent_raw` | API 응답을 타입만 맞춰 저장 |
| Staging (정제) | `v_sales`, `v_rents` | snake_case 컬럼명, 이상값(금액·면적 ≤ 0) 제거, 진행 중인 당월 제외, `complex_key`·평당가 파생 |
| | `v_sales_clean` | 일괄 거래 표시 컬럼 `is_bulk` 추가 (삭제하지 않음) |
| Mart | `m_region_monthly` | 시군구 × 월 매매·전세 중위값, 전세가율, 표본 충분 여부 |
| | `m_sido_monthly` | 시도 × 월 거래량(전체/일괄 제외), 중위가, 중위 평당가 |
| | `m_sido_pace` | 월초/중순/월말 일평균 거래 건수 (신고 지연 점검) |
| | `m_complex_ratio` | 단지 × 면적대 전세가율 (최근 3개월) |
| Serving | `lk_deals` | 매매·전세·월세 통합, 1행 = 1거래. 중위값은 미리 집계하면 지역끼리 다시 합칠 수 없어 거래 단위로 두고 Looker에서 `MEDIAN()` 계산 |

## 데이터 품질

### 1. 신고 지연 (잠정치)
최근 약 3개월은 신고가 덜 들어온 잠정치입니다. 월 안의 구간별 일평균(`m_sido_pace`)으로 확인합니다.

- 신고가 끝난 월: 서울 월말/월초 비율 약 **0.88** (2026년 6-8월)
- 2026-10 (11/10 스냅샷 기준): **0.48** → 11/11 재수집 후 0.64 → 11/16 재수집 후 **0.85**
- 서울 10월 건수 (11/10 → 11/16): 2,640 → 3,555 (**+34.7%**). 구간별로 1-10일 +5.6%, 11-20일 +36.1%, 21일-말일 **+88.4%**로, 최근 날짜일수록 크게 늘어나는 신고 지연의 전형적 패턴

### 2. 일괄 거래 (`is_bulk`)
2026-10-08 동대문구 한 단지에서 같은 가격으로 313건이 하루에 신고되어, 동대문구 10월 중위가가
**24,488만원(포함) vs 94,000만원(제외)** 으로 3.8배 왜곡되었습니다.

- 규칙: 같은 단지 + 같은 날짜 + 같은 가격이 10건 이상 → `is_bulk = TRUE`
- 규모: 매매 980,460건 중 4,679건(0.5%, 11/16 기준)
- 원본은 삭제하지 않고 플래그만 달아, 지표마다 포함/제외를 선택할 수 있게 했습니다.

### 3. 스냅샷 검증
뷰는 재수집하면 결과가 바뀌므로, 재수집 전 일자별 건수를 `snap_daily_YYYYMMDD` 테이블로 고정하고
재수집 후 같은 쿼리로 전후를 비교합니다 ([sql/checks/snapshot_daily.sql](sql/checks/snapshot_daily.sql)).

### 4. 전세가율 왜곡
지역 중위값끼리 나눈 전세가율은 매매·전세의 거래 구성이 달라 **11.5%가 100%를 초과** (403/3,500행, 최대 1,226%)했습니다.
같은 단지·면적대끼리 매칭하면 100% 초과 비율이 **0.9%** (49/5,460, 최대 140.1%)로 낮아집니다 (집계 단위가 달라 직접 비교는 아니며, 위 수치는 모두 11/5 수집 기준).
대시보드는 `lk_deals`의 `complex_area_key`로, 분석 마트는 `m_complex_ratio`로 같은 방식의 매칭을 합니다.

## 폴더 구조

```
.
├── .github/workflows/
│   ├── trade_pipeline.yml         매매 수집 (cron + 수동 실행)
│   └── rent_pipeline.yml          전월세 수집
├── src/
│   ├── incremental_collector.py       매매 수집기
│   └── incremental_collector_rent.py  전월세 수집기
├── sql/
│   ├── views/                     v_* 정제 뷰, m_* 집계 마트
│   ├── tables/                    lk_deals (수집 후 재실행 필요)
│   └── checks/                    검증·스냅샷 쿼리
├── docs/
│   ├── metrics.md                 지표 정의
│   └── findings_log.md            분석 기록
└── 법정동코드 전체자료.txt          시군구 코드 원본 (수집기 입력, cp949·탭 구분)
```

## 실행 방법

GitHub 저장소 **Settings → Secrets and variables → Actions**에 등록:

| Secret | 내용 |
|---|---|
| `DEAL_API_KEY` | 공공데이터포털 서비스 키 (아파트 매매·전월세 실거래가 API 활용 신청) |
| `GCP_SA_KEY` | BigQuery 쓰기 권한이 있는 서비스 계정 키 JSON |

로컬 실행:

```bash
pip install pandas requests google-cloud-bigquery db-dtypes pyarrow
export DEAL_API_KEY=...
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service_account.json
python src/incremental_collector.py
python src/incremental_collector_rent.py
```

다른 GCP 프로젝트에서 쓰려면 스크립트의 `PROJECT_ID`를 바꾸고 `sql/views` → `sql/tables` 순서로 실행합니다.

## 한계와 향후 계획

**한계**
- 중위값은 `APPROX_QUANTILES` 기반 근사값입니다.
- 일괄 거래 기준(10건)은 경험적 임의값이며 민감도 검증 전입니다.
- `m_region_monthly`와 `m_complex_ratio`는 `v_sales`를 읽어 일괄 거래를 구분하지 않고 집계합니다. `lk_deals`(`is_bulk` 컬럼)와 `m_sido_monthly`(전체/일괄 제외 컬럼)는 구분해서 제공하고, `m_sido_pace`는 일괄 거래를 제외합니다.
- 거래 해제·취소 여부 컬럼을 수집하지 않아 해제 거래 포함 여부를 확인하지 못했습니다.
- `lk_deals`는 테이블이라 수집 후 수동으로 다시 실행해야 최신이 됩니다.
- SQL 객체의 의존 관계와 테스트가 코드로 관리되지 않습니다.

**향후 계획**
- **dbt 전환**: `v_*` → staging, `m_*`·`lk_deals` → marts 모델로 옮기고 `ref()`로 의존성 관리,
  `not_null`·`unique`·`accepted_values` 테스트와 문서(lineage) 자동 생성
- **예약 쿼리 / 오케스트레이션**: 수집 완료 후 `lk_deals` 갱신을 BigQuery 예약 쿼리(또는 Actions 후속 job)로 자동화
- 해제 거래 컬럼 수집, 일괄 거래 기준값 민감도 분석

## 데이터 출처

- 국토교통부 아파트 매매 / 전월세 실거래가 자료 (공공데이터포털, data.go.kr)
- 행정표준코드관리시스템 법정동코드

원본 CSV, 분석 노트북, 인증 키는 저장소에 포함하지 않습니다.
