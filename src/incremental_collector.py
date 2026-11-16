import os
import time
import tempfile
import threading
import requests
import pandas as pd
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from google.cloud import bigquery
from concurrent.futures import ThreadPoolExecutor, as_completed
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

PROJECT_ID = "project-c73b2fff-7ef3-4ce1-9a3"
DATASET_ID = "apt_dataset"
TARGET_TABLE = f"{PROJECT_ID}.{DATASET_ID}.transaction_raw"
STAGING_TABLE = f"{PROJECT_ID}.{DATASET_ID}.transaction_staging"
API_KEY = os.environ.get("DEAL_API_KEY")

NUM_OF_ROWS = 1000
MAX_WORKERS = 10
STOP_EVENT = threading.Event()  # 한도 초과 시 전체 중단 신호

# transaction_raw 컬럼 순서 (스키마와 동일)
COLUMNS = ["lawdCd", "regionName", "aptNm", "dealAmount", "excluUseAr", "floor",
           "dealYear", "dealMonth", "dealDay", "buildYear", "umdNm"]


class QuotaExceeded(Exception):
    pass


def get_recent_deal_ymd_list():
    """최근 3개월(YYYYMM)"""
    curr = datetime.today()
    ymd_list = []
    for _ in range(3):
        ymd_list.append(curr.strftime("%Y%m"))
        curr = curr.replace(day=1) - timedelta(days=1)
    return sorted(set(ymd_list))


def load_sigungu_codes():
    """법정동코드 파일에서 시군구 5자리 코드 + 지역명 추출"""
    file_path = "법정동코드 전체자료.txt"
    if not os.path.exists(file_path) and os.path.exists(f"src/{file_path}"):
        file_path = f"src/{file_path}"

    df = pd.read_csv(file_path, encoding="cp949", sep="\t", dtype=str)
    df = df[df["폐지여부"] == "존재"].copy()
    df = df[df["법정동코드"].str[5:] == "00000"]
    df = df[df["법정동코드"].str[2:5] != "000"].copy()
    df["lawd_cd"] = df["법정동코드"].str[:5]
    df["regionName"] = df["법정동명"].str.strip()
    result = (df[["lawd_cd", "regionName"]]
              .drop_duplicates("lawd_cd").reset_index(drop=True))
    print(f"✅ 시군구 코드 {len(result)}개 로드")
    return result


def create_requests_session():
    """429는 재시도하지 않음 (재시도도 호출 횟수를 소모하므로)"""
    session = requests.Session()
    retry = Retry(total=2, backoff_factor=1,
                  status_forcelist=[500, 502, 503, 504],
                  raise_on_status=False)
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def request_page(session, lawd_cd, deal_ymd, page_no):
    if STOP_EVENT.is_set():
        raise QuotaExceeded("다른 스레드에서 한도 초과 감지 - 중단")

    time.sleep(0.3)
    url = (
        "https://apis.data.go.kr/1613000/RTMSDataSvcAptTrade/getRTMSDataSvcAptTrade"
        f"?serviceKey={API_KEY}&LAWD_CD={lawd_cd}&DEAL_YMD={deal_ymd}"
        f"&numOfRows={NUM_OF_ROWS}&pageNo={page_no}"
    )
    response = session.get(url, timeout=15)

    if response.status_code == 429 or "LIMITED_NUMBER" in response.text:
        STOP_EVENT.set()
        raise QuotaExceeded("API 일일 한도 초과")
    if response.status_code != 200:
        raise RuntimeError(f"HTTP {response.status_code} ({lawd_cd}, {deal_ymd})")

    root = ET.fromstring(response.content)
    result_code = root.findtext(".//resultCode")
    if result_code not in (None, "00", "000"):
        raise RuntimeError(f"API 오류 {result_code}: {root.findtext('.//resultMsg')} ({lawd_cd}, {deal_ymd})")
    return root


def fetch_apt_trade_data(session, lawd_cd, deal_ymd):
    """한 지역·한 달의 모든 페이지 수집. 실패 시 예외 발생"""
    records = []
    page_no = 1
    while True:
        root = request_page(session, lawd_cd, deal_ymd, page_no)
        for item in root.findall(".//item"):
            records.append({
                "lawdCd": lawd_cd,
                "aptNm": (item.findtext("aptNm") or "").strip(),
                "dealAmount": (item.findtext("dealAmount") or "").strip(),
                "excluUseAr": item.findtext("excluUseAr"),
                "floor": item.findtext("floor"),
                "dealYear": item.findtext("dealYear"),
                "dealMonth": item.findtext("dealMonth"),
                "dealDay": item.findtext("dealDay"),
                "buildYear": item.findtext("buildYear"),
                "umdNm": (item.findtext("umdNm") or "").strip(),
            })
        total_count = int(root.findtext(".//totalCount") or 0)
        if page_no * NUM_OF_ROWS >= total_count:
            break
        page_no += 1
    return records


def transform(df, region_map):
    """regionName 매핑 + 문자열 → 숫자 타입 변환 + 컬럼 순서 고정"""
    df["regionName"] = df["lawdCd"].astype(str).str.zfill(5).map(region_map)
    df["dealAmount"] = pd.to_numeric(df["dealAmount"].str.replace(",", ""), errors="coerce")
    df["excluUseAr"] = pd.to_numeric(df["excluUseAr"], errors="coerce")
    for col in ["lawdCd", "floor", "dealYear", "dealMonth", "dealDay", "buildYear", "dealAmount"]:
        df[col] = pd.to_numeric(df[col], errors="coerce").astype("Int64")
    return df[COLUMNS]


def setup_credentials():
    if "GCP_SA_KEY" in os.environ:
        key_file = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".json")
        key_file.write(os.environ["GCP_SA_KEY"])
        key_file.close()
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = key_file.name
    else:
        key_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if not key_path or not os.path.exists(key_path):
            raise SystemExit("GCP_SA_KEY 또는 GOOGLE_APPLICATION_CREDENTIALS(키 파일 경로) 환경 변수를 설정하세요")


def main():
    print("🚀 매매 실거래가 증분 수집 시작")
    setup_credentials()
    client = bigquery.Client(project=PROJECT_ID)

    df_sigungu = load_sigungu_codes()
    region_map = dict(zip(df_sigungu["lawd_cd"], df_sigungu["regionName"]))
    target_ymds = get_recent_deal_ymd_list()
    tasks = [(cd, ymd) for cd in df_sigungu["lawd_cd"] for ymd in target_ymds]
    print(f"대상: {len(df_sigungu)}개 지역 × {len(target_ymds)}개월 = {len(tasks)}건 {target_ymds}")

    session = create_requests_session()
    all_data, failed = [], []

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_task = {executor.submit(fetch_apt_trade_data, session, cd, ymd): (cd, ymd)
                          for cd, ymd in tasks}
        done = 0
        for future in as_completed(future_to_task):
            done += 1
            try:
                all_data.extend(future.result())
            except Exception as e:
                failed.append((future_to_task[future], str(e)))
            if done % 100 == 0 or done == len(tasks):
                print(f"진행: [{done}/{len(tasks)}] 누적 {len(all_data):,}행, 실패 {len(failed)}건")

    # 실패가 하나라도 있으면 기존 데이터를 건드리지 않고 종료 → Actions 실패 표시
    if failed:
        print("❌ 실패 샘플:", failed[:5])
        raise SystemExit(f"수집 실패 {len(failed)}건 - 기존 데이터 보존을 위해 중단")
    if not all_data:
        raise SystemExit("수집 결과 0건 - 비정상으로 판단하여 중단")

    df = transform(pd.DataFrame(all_data), region_map)
    print(f"regionName 누락: {df['regionName'].isna().sum()}건")

    # 1) staging 테이블에 먼저 적재 (여기서 실패해도 본 테이블은 안전)
    job = client.load_table_from_dataframe(
        df, STAGING_TABLE,
        job_config=bigquery.LoadJobConfig(write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE),
    )
    job.result()
    print(f"📥 staging 적재 완료: {len(df):,}행")

    # 2) 삭제 + 삽입을 하나의 트랜잭션으로 (실패 시 자동 롤백)
    ymd_list = ", ".join(target_ymds)
    cols = ", ".join(COLUMNS)
    sql = f"""
    BEGIN TRANSACTION;
    DELETE FROM `{TARGET_TABLE}`
    WHERE dealYear * 100 + dealMonth IN ({ymd_list});
    INSERT INTO `{TARGET_TABLE}` ({cols})
    SELECT {cols} FROM `{STAGING_TABLE}`;
    COMMIT TRANSACTION;
    """
    client.query(sql).result()
    print(f"🎉 본 테이블 반영 완료: {len(df):,}건 (대상 연월 {target_ymds})")


if __name__ == "__main__":
    main()