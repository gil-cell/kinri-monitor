import { Hono } from 'hono';
import { cors } from 'hono/cors';
import {
  SERIES,
  fetchMultipleSeries,
  fetchSeries,
  type SeriesKey,
} from './boj-api';
import {
  calcEqualPayment,
  calcEqualPrincipal,
  diagnoseDeviation,
  simulateRateIncrease,
  type LoanCondition,
} from './calc';
import { sendPushToAll, type APNsConfig, type APNsPayload } from './apns';

type Bindings = {
  CACHE: KVNamespace;
  APNS_KEY: string;      // .p8 秘密鍵（wrangler secret で設定）
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_BUNDLE_ID: string;
  APNS_PRODUCTION: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use('*', cors());

// ── ヘルパー ────────────────────────────────

async function cachedFetch(
  kv: KVNamespace, cacheKey: string, ttlSeconds: number,
  fetcher: () => Promise<unknown>,
): Promise<unknown> {
  const cached = await kv.get(cacheKey, 'json');
  if (cached !== null) return cached;
  const data = await fetcher();
  await kv.put(cacheKey, JSON.stringify(data), { expirationTtl: ttlSeconds });
  return data;
}

function startDate24MonthsAgo(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth() + 1;
  const startY = m <= 12 ? y - 2 : y - 1;
  return `${startY}${String(m).padStart(2, '0')}`;
}

function getAPNsConfig(env: Bindings): APNsConfig {
  return {
    teamId: env.APNS_TEAM_ID,
    keyId: env.APNS_KEY_ID,
    privateKey: env.APNS_KEY,
    bundleId: env.APNS_BUNDLE_ID,
    production: env.APNS_PRODUCTION === 'true',
  };
}

// ── エンドポイント ──────────────────────────────

app.get('/', (c) => {
  return c.json({
    name: '借入金利モニター API',
    version: '0.3.0',
    endpoints: [
      'GET  /api/rates/latest',
      'GET  /api/rates/history?key=...&months=24',
      'GET  /api/series',
      'POST /api/calc/repayment',
      'POST /api/calc/deviation',
      'POST /api/calc/simulation',
      'POST /api/device/register',
      'POST /api/device/alerts',
    ],
  });
});

// ── 金利データ ──────────────────────────────

const CORE_KEYS: SeriesKey[] = [
  'LENDING_NEW_TOTAL_DOMESTIC', 'LENDING_NEW_SHORT_DOMESTIC', 'LENDING_NEW_LONG_DOMESTIC',
  'LENDING_NEW_TOTAL_CITY', 'LENDING_NEW_TOTAL_REGIONAL', 'LENDING_NEW_TOTAL_SHINKIN',
  'LENDING_STOCK_TOTAL', 'LENDING_STOCK_SHORT', 'LENDING_STOCK_LONG',
  'BASE_RATE', 'CALL_RATE_ON_AVG', 'PRIME_RATE_TOTAL',
];

app.get('/api/rates/latest', async (c) => {
  const TTL = 60 * 60 * 6;
  try {
    const data = await cachedFetch(c.env.CACHE, 'rates:latest', TTL, async () => {
      const start = startDate24MonthsAgo();
      const series = await fetchMultipleSeries(CORE_KEYS, start);
      return series.map((s) => {
        const latest = s.data.filter(d => d.value !== null).at(-1);
        const prev = s.data.filter(d => d.value !== null).at(-2);
        return {
          key: s.key, label: s.label, unit: s.unit, lastUpdate: s.lastUpdate,
          latest: latest ? { date: latest.date, value: latest.value } : null,
          previous: prev ? { date: prev.date, value: prev.value } : null,
          change: latest && prev && latest.value !== null && prev.value !== null
            ? Math.round((latest.value - prev.value) * 1000) / 1000 : null,
        };
      });
    });
    return c.json({ status: 'ok', data });
  } catch (err) {
    return c.json({ status: 'error', message: err instanceof Error ? err.message : 'Unknown' }, 502);
  }
});

app.get('/api/rates/history', async (c) => {
  const key = c.req.query('key') as SeriesKey | undefined;
  const months = parseInt(c.req.query('months') ?? '24', 10);
  if (!key || !(key in SERIES)) {
    return c.json({ status: 'error', message: `Invalid key` }, 400);
  }
  const TTL = 60 * 60 * 6;
  try {
    const data = await cachedFetch(c.env.CACHE, `history:${key}:${months}`, TTL, async () => {
      const now = new Date();
      const startY = now.getFullYear() - Math.ceil(months / 12);
      const start = `${startY}${String(now.getMonth() + 1).padStart(2, '0')}`;
      return await fetchSeries(key, start);
    });
    return c.json({ status: 'ok', data });
  } catch (err) {
    return c.json({ status: 'error', message: err instanceof Error ? err.message : 'Unknown' }, 502);
  }
});

app.get('/api/series', (c) => {
  const list = Object.entries(SERIES).map(([key, def]) => ({ key, db: def.db, code: def.code, label: def.label }));
  return c.json({ status: 'ok', data: list });
});

// ── 計算 ──────────────────────────────

app.post('/api/calc/repayment', async (c) => {
  const body = await c.req.json<LoanCondition>();
  return c.json({ status: 'ok', data: { equalPayment: calcEqualPayment(body), equalPrincipal: calcEqualPrincipal(body) } });
});

app.post('/api/calc/deviation', async (c) => {
  const body = await c.req.json<{ userRate: number; marketRate: number; principal: number; termYears: number }>();
  return c.json({ status: 'ok', data: diagnoseDeviation(body.userRate, body.marketRate, body.principal, body.termYears) });
});

app.post('/api/calc/simulation', async (c) => {
  const body = await c.req.json<LoanCondition & { increases?: number[] }>();
  return c.json({ status: 'ok', data: simulateRateIncrease(body, body.increases) });
});

// ── デバイストークン登録 ──────────────────────────

/**
 * POST /api/device/register
 * Body: { device_token: string, alert_rules: [{ series_key, direction, threshold }] }
 */
app.post('/api/device/register', async (c) => {
  const body = await c.req.json<{
    device_token: string;
    alert_rules?: { series_key: string; direction: string; threshold: number }[];
  }>();

  if (!body.device_token) {
    return c.json({ status: 'error', message: 'device_token required' }, 400);
  }

  // KV にデバイス情報を保存（キー: device:{token}）
  const deviceData = {
    token: body.device_token,
    alert_rules: body.alert_rules || [],
    updated_at: new Date().toISOString(),
  };
  await c.env.CACHE.put(`device:${body.device_token}`, JSON.stringify(deviceData));

  // デバイストークン一覧にも追加
  const tokensJson = await c.env.CACHE.get('device_tokens', 'json') as string[] | null;
  const tokens = new Set(tokensJson || []);
  tokens.add(body.device_token);
  await c.env.CACHE.put('device_tokens', JSON.stringify([...tokens]));

  return c.json({ status: 'ok', message: 'registered' });
});

/**
 * POST /api/device/alerts
 * デバイスのアラートルールを更新
 * Body: { device_token, alert_rules: [{ series_key, direction, threshold }] }
 */
app.post('/api/device/alerts', async (c) => {
  const body = await c.req.json<{
    device_token: string;
    alert_rules: { series_key: string; direction: string; threshold: number }[];
  }>();

  const existing = await c.env.CACHE.get(`device:${body.device_token}`, 'json') as Record<string, unknown> | null;
  if (!existing) {
    return c.json({ status: 'error', message: 'device not registered' }, 404);
  }

  existing.alert_rules = body.alert_rules;
  existing.updated_at = new Date().toISOString();
  await c.env.CACHE.put(`device:${body.device_token}`, JSON.stringify(existing));

  return c.json({ status: 'ok', message: 'alerts updated' });
});

// ── Cron ハンドラー（金利チェック→Push通知）──────────

async function handleCron(env: Bindings) {
  console.log('[Cron] Rate check started');

  // 最新金利を取得（キャッシュをバイパス）
  const start = startDate24MonthsAgo();
  const series = await fetchMultipleSeries(CORE_KEYS, start);

  const latestRates = new Map<string, number>();
  for (const s of series) {
    const latest = s.data.filter(d => d.value !== null).at(-1);
    if (latest?.value != null) {
      latestRates.set(s.key, latest.value);
    }
  }

  // キャッシュも更新
  const cacheData = series.map((s) => {
    const latest = s.data.filter(d => d.value !== null).at(-1);
    const prev = s.data.filter(d => d.value !== null).at(-2);
    return {
      key: s.key, label: s.label, unit: s.unit, lastUpdate: s.lastUpdate,
      latest: latest ? { date: latest.date, value: latest.value } : null,
      previous: prev ? { date: prev.date, value: prev.value } : null,
      change: latest && prev && latest.value !== null && prev.value !== null
        ? Math.round((latest.value - prev.value) * 1000) / 1000 : null,
    };
  });
  await env.CACHE.put('rates:latest', JSON.stringify(cacheData), { expirationTtl: 60 * 60 * 6 });

  // 全デバイスを取得してアラート判定
  const tokensJson = await env.CACHE.get('device_tokens', 'json') as string[] | null;
  if (!tokensJson || tokensJson.length === 0) {
    console.log('[Cron] No registered devices');
    return;
  }

  const apnsConfig = getAPNsConfig(env);
  let totalSent = 0;

  for (const token of tokensJson) {
    const deviceJson = await env.CACHE.get(`device:${token}`, 'json') as {
      alert_rules?: { series_key: string; direction: string; threshold: number }[];
    } | null;

    if (!deviceJson?.alert_rules) continue;

    for (const rule of deviceJson.alert_rules) {
      const value = latestRates.get(rule.series_key);
      if (value === undefined) continue;

      const triggered = rule.direction === 'above' ? value >= rule.threshold : value <= rule.threshold;
      if (!triggered) continue;

      // 同日重複チェック
      const today = new Date().toISOString().slice(0, 10);
      const dedupKey = `sent:${token}:${rule.series_key}:${today}`;
      if (await env.CACHE.get(dedupKey)) continue;

      const seriesLabel = cacheData.find(r => r.key === rule.series_key)?.label || rule.series_key;
      const dirText = rule.direction === 'above' ? '以上' : '以下';

      const payload: APNsPayload = {
        title: `金利アラート：${seriesLabel}`,
        body: `${seriesLabel}が${value.toFixed(3)}%になりました（閾値${rule.threshold.toFixed(2)}%${dirText}）`,
        category: 'RATE_ALERT',
        data: { series_key: rule.series_key, value: String(value) },
      };

      const result = await sendPushToAll([token], payload, apnsConfig);
      if (result.sent > 0) {
        await env.CACHE.put(dedupKey, '1', { expirationTtl: 86400 });
        totalSent++;
      }
    }
  }

  console.log(`[Cron] Sent ${totalSent} notifications`);
}

// ── Export ──────────────────────────────

export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: Bindings, ctx: ExecutionContext) {
    ctx.waitUntil(handleCron(env));
  },
};
