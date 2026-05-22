import { Hono } from 'hono';
import { cors } from 'hono/cors';
import {
  SERIES,
  fetchMultipleSeries,
  fetchSeries,
  type SeriesKey,
  type RateSeries,
} from './boj-api';

type Bindings = {
  CACHE: KVNamespace;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use('*', cors());

// ── ヘルパー ────────────────────────────────

/** KVキャッシュ付きデータ取得。TTL秒間はKVから返す */
async function cachedFetch(
  kv: KVNamespace,
  cacheKey: string,
  ttlSeconds: number,
  fetcher: () => Promise<unknown>,
): Promise<unknown> {
  // キャッシュ読み取り
  const cached = await kv.get(cacheKey, 'json');
  if (cached !== null) return cached;

  // 日銀APIから取得
  try {
    const data = await fetcher();
    // キャッシュ書き込み（TTL付き）
    await kv.put(cacheKey, JSON.stringify(data), { expirationTtl: ttlSeconds });
    return data;
  } catch (err) {
    // フォールバック：期限切れキャッシュがあればそれを返す（KVのTTL切れ後はnull）
    throw err;
  }
}

// 直近24ヶ月の開始日を算出
function startDate24MonthsAgo(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth() + 1; // 1-12
  const startY = m <= 12 ? y - 2 : y - 1;
  const startM = m;
  return `${startY}${String(startM).padStart(2, '0')}`;
}

// ── エンドポイント ──────────────────────────────

app.get('/', (c) => {
  return c.json({
    name: '借入金利モニター API',
    version: '0.2.0',
    endpoints: [
      'GET /api/rates/latest    … 主要金利の最新値一式',
      'GET /api/rates/history   … 時系列データ（?key=SERIES_KEY&months=24）',
      'GET /api/series          … 利用可能な系列キー一覧',
    ],
  });
});

/**
 * GET /api/rates/latest
 * 主要金利の最新値一式（24時間キャッシュ）
 */
app.get('/api/rates/latest', async (c) => {
  const CACHE_KEY = 'rates:latest';
  const TTL = 60 * 60 * 6; // 6時間

  const coreKeys: SeriesKey[] = [
    'LENDING_NEW_TOTAL_DOMESTIC',
    'LENDING_NEW_SHORT_DOMESTIC',
    'LENDING_NEW_LONG_DOMESTIC',
    'LENDING_NEW_TOTAL_CITY',
    'LENDING_NEW_TOTAL_REGIONAL',
    'LENDING_NEW_TOTAL_SHINKIN',
    'LENDING_STOCK_TOTAL',
    'LENDING_STOCK_SHORT',
    'LENDING_STOCK_LONG',
    'BASE_RATE',
    'CALL_RATE_ON_AVG',
    'PRIME_RATE_TOTAL',
  ];

  try {
    const data = await cachedFetch(c.env.CACHE, CACHE_KEY, TTL, async () => {
      const start = startDate24MonthsAgo();
      const series = await fetchMultipleSeries(coreKeys, start);

      // 各系列の最新値を抽出
      return series.map((s) => {
        const latest = s.data.filter(d => d.value !== null).at(-1);
        const prev = s.data.filter(d => d.value !== null).at(-2);
        return {
          key: s.key,
          label: s.label,
          unit: s.unit,
          lastUpdate: s.lastUpdate,
          latest: latest ? { date: latest.date, value: latest.value } : null,
          previous: prev ? { date: prev.date, value: prev.value } : null,
          change: latest && prev && latest.value !== null && prev.value !== null
            ? Math.round((latest.value - prev.value) * 1000) / 1000
            : null,
        };
      });
    });

    return c.json({ status: 'ok', data });
  } catch (err) {
    return c.json(
      { status: 'error', message: err instanceof Error ? err.message : 'Unknown error' },
      502,
    );
  }
});

/**
 * GET /api/rates/history?key=SERIES_KEY&months=24
 * 特定系列の時系列データ
 */
app.get('/api/rates/history', async (c) => {
  const key = c.req.query('key') as SeriesKey | undefined;
  const months = parseInt(c.req.query('months') ?? '24', 10);

  if (!key || !(key in SERIES)) {
    return c.json(
      { status: 'error', message: `Invalid key. Available: ${Object.keys(SERIES).join(', ')}` },
      400,
    );
  }

  const CACHE_KEY = `history:${key}:${months}`;
  const TTL = 60 * 60 * 6; // 6時間

  try {
    const data = await cachedFetch(c.env.CACHE, CACHE_KEY, TTL, async () => {
      const now = new Date();
      const startY = now.getFullYear() - Math.ceil(months / 12);
      const startM = now.getMonth() + 1;
      const start = `${startY}${String(startM).padStart(2, '0')}`;
      return await fetchSeries(key, start);
    });

    return c.json({ status: 'ok', data });
  } catch (err) {
    return c.json(
      { status: 'error', message: err instanceof Error ? err.message : 'Unknown error' },
      502,
    );
  }
});

/**
 * GET /api/series
 * 利用可能な系列キー一覧
 */
app.get('/api/series', (c) => {
  const list = Object.entries(SERIES).map(([key, def]) => ({
    key,
    db: def.db,
    code: def.code,
    label: def.label,
  }));
  return c.json({ status: 'ok', data: list });
});

export default app;
