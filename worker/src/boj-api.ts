/**
 * 日銀 時系列統計データ検索サイト API クライアント
 * 仕様変更時はこのファイルのみ修正すればよい構成。
 *
 * API Docs: https://www.stat-search.boj.or.jp/info/api_manual.pdf
 * Base URL: https://www.stat-search.boj.or.jp/api/v1/
 */

const BASE_URL = 'https://www.stat-search.boj.or.jp/api/v1';

// ── 系列定義 ──────────────────────────────────────
// db名（小文字）と系列コード（DB名を含まない）のペア

export const SERIES = {
  // 貸出約定平均金利（ir04）
  LENDING_NEW_TOTAL_DOMESTIC: { db: 'ir04', code: 'DLLR2CIDBNL1', label: '新規/総合/国内銀行' },
  LENDING_NEW_SHORT_DOMESTIC: { db: 'ir04', code: 'DLLR2CIDBNL2', label: '新規/短期/国内銀行' },
  LENDING_NEW_LONG_DOMESTIC:  { db: 'ir04', code: 'DLLR2CIDBNL3', label: '新規/長期/国内銀行' },
  LENDING_NEW_TOTAL_CITY:     { db: 'ir04', code: 'DLLR2CICBNL1', label: '新規/総合/都市銀行' },
  LENDING_NEW_TOTAL_REGIONAL: { db: 'ir04', code: 'DLLR2CIRBNL1', label: '新規/総合/地方銀行' },
  LENDING_NEW_TOTAL_SHINKIN:  { db: 'ir04', code: 'DLLR2CICR35',  label: '新規/総合/信用金庫' },
  LENDING_STOCK_TOTAL:        { db: 'ir04', code: 'DLLR2CIDBST1', label: 'ストック/総合/国内銀行' },
  LENDING_STOCK_SHORT:        { db: 'ir04', code: 'DLLR2CIDBST2', label: 'ストック/短期/国内銀行' },
  LENDING_STOCK_LONG:         { db: 'ir04', code: 'DLLR2CIDBST3', label: 'ストック/長期/国内銀行' },

  // 基準割引率（ir01）
  BASE_RATE: { db: 'ir01', code: 'MADR1M', label: '基準割引率および基準貸付利率' },

  // 無担保コールレート O/N（fm02）
  CALL_RATE_ON_AVG:  { db: 'fm02', code: 'STRACLUCON', label: '無担保コールレート O/N 月平均' },
  CALL_RATE_ON_END:  { db: 'fm02', code: 'STRECLUCON', label: '無担保コールレート O/N 月末' },

  // 短期プライムレート相当（ir03 - 貸出金利 総合）
  PRIME_RATE_TOTAL:  { db: 'ir03', code: 'DLDRK_DLDR442DB', label: '貸出金利 総合' },
} as const;

export type SeriesKey = keyof typeof SERIES;

// ── レスポンス型 ──────────────────────────────────

interface BojResultSet {
  SERIES_CODE: string;
  NAME_OF_TIME_SERIES_J: string;
  UNIT_J: string;
  FREQUENCY: string;
  CATEGORY_J: string;
  LAST_UPDATE: number;
  VALUES: {
    SURVEY_DATES: number[];
    VALUES: (number | null)[];
  };
}

interface BojApiResponse {
  STATUS: number;
  MESSAGEID: string;
  MESSAGE: string;
  DATE: string;
  PARAMETER?: Record<string, string>;
  NEXTPOSITION?: string | null;
  RESULTSET?: BojResultSet[];
}

// ── 整形済み出力型 ──────────────────────────────────

export interface RateDataPoint {
  date: string;       // "2026-02" 形式
  value: number | null;
}

export interface RateSeries {
  key: string;
  label: string;
  unit: string;
  frequency: string;
  lastUpdate: string;
  data: RateDataPoint[];
}

// ── API呼び出し ──────────────────────────────────

function formatDate(yyyymm: number): string {
  const s = String(yyyymm);
  return s.length === 6 ? `${s.slice(0, 4)}-${s.slice(4, 6)}` : s;
}

export async function fetchSeries(
  seriesKey: SeriesKey,
  startDate?: string,   // "202301" 形式
  endDate?: string,
): Promise<RateSeries> {
  const def = SERIES[seriesKey];

  const params = new URLSearchParams({
    format: 'json',
    lang: 'jp',
    db: def.db,
    code: def.code,
  });
  if (startDate) params.set('startDate', startDate);
  if (endDate)   params.set('endDate', endDate);

  const url = `${BASE_URL}/getDataCode?${params.toString()}`;

  const resp = await fetch(url, {
    headers: { 'Accept-Encoding': 'gzip' },
    signal: AbortSignal.timeout(15_000),
  });

  if (!resp.ok) {
    throw new Error(`BOJ API HTTP ${resp.status}`);
  }

  const json = (await resp.json()) as BojApiResponse;

  if (json.STATUS !== 200 || !json.RESULTSET?.length) {
    throw new Error(`BOJ API error: ${json.MESSAGE} (${json.MESSAGEID})`);
  }

  const rs = json.RESULTSET[0];
  const data: RateDataPoint[] = rs.VALUES.SURVEY_DATES.map((d, i) => ({
    date: formatDate(d),
    value: rs.VALUES.VALUES[i],
  }));

  return {
    key: seriesKey,
    label: def.label,
    unit: rs.UNIT_J,
    frequency: rs.FREQUENCY,
    lastUpdate: String(rs.LAST_UPDATE),
    data,
  };
}

/**
 * 複数系列を同一DBから一括取得（コンマ区切り）
 */
export async function fetchMultipleSeries(
  seriesKeys: SeriesKey[],
  startDate?: string,
  endDate?: string,
): Promise<RateSeries[]> {
  // DB ごとにグルーピング
  const grouped = new Map<string, SeriesKey[]>();
  for (const key of seriesKeys) {
    const db = SERIES[key].db;
    const arr = grouped.get(db) ?? [];
    arr.push(key);
    grouped.set(db, arr);
  }

  const results: RateSeries[] = [];

  for (const [db, keys] of grouped) {
    const codes = keys.map(k => SERIES[k].code).join(',');
    const params = new URLSearchParams({
      format: 'json',
      lang: 'jp',
      db,
      code: codes,
    });
    if (startDate) params.set('startDate', startDate);
    if (endDate)   params.set('endDate', endDate);

    const url = `${BASE_URL}/getDataCode?${params.toString()}`;
    const resp = await fetch(url, {
      headers: { 'Accept-Encoding': 'gzip' },
      signal: AbortSignal.timeout(15_000),
    });

    if (!resp.ok) continue;

    const json = (await resp.json()) as BojApiResponse;
    if (json.STATUS !== 200 || !json.RESULTSET) continue;

    for (const rs of json.RESULTSET) {
      const matchKey = keys.find(k => SERIES[k].code === rs.SERIES_CODE);
      if (!matchKey) continue;

      const data: RateDataPoint[] = rs.VALUES.SURVEY_DATES.map((d, i) => ({
        date: formatDate(d),
        value: rs.VALUES.VALUES[i],
      }));

      results.push({
        key: matchKey,
        label: SERIES[matchKey].label,
        unit: rs.UNIT_J,
        frequency: rs.FREQUENCY,
        lastUpdate: String(rs.LAST_UPDATE),
        data,
      });
    }
  }

  return results;
}
