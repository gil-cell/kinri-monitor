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

// ── Legal Pages（App Store審査必須）──────────────────

app.get('/privacy', (c) => {
  return c.html(`<!DOCTYPE html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>プライバシーポリシー - 借入金利モニター</title><style>body{font-family:-apple-system,sans-serif;max-width:700px;margin:0 auto;padding:20px;line-height:1.8;color:#333}h1{font-size:1.4em}h2{font-size:1.1em;margin-top:2em}p{margin:0.8em 0}</style></head><body>
<h1>プライバシーポリシー</h1>
<p>借入金利モニター（以下「本アプリ」）は、ユーザーのプライバシーを尊重し保護することに努めます。本ポリシーでは、本アプリにおける情報の取り扱いについて説明します。</p>

<h2>1. 収集する情報</h2>
<p><strong>端末内に保存されるデータ：</strong>借入条件、ポートフォリオ情報、アラート設定等のユーザーが入力したデータは端末内（UserDefaults）にのみ保存され、当社サーバーには送信されません。</p>
<p><strong>プッシュ通知用データ：</strong>プッシュ通知機能を利用する場合、デバイストークンおよび金利アラート設定（監視する指標と閾値）がサーバーに送信・保存されます。これは通知配信のためにのみ使用されます。</p>
<p><strong>広告関連データ：</strong>本アプリはGoogle AdMobを使用しており、広告の配信・最適化のためにデバイス識別子、IPアドレス、利用データが収集される場合があります。詳細は<a href="https://policies.google.com/privacy">Googleのプライバシーポリシー</a>をご参照ください。</p>

<h2>2. 情報の利用目的</h2>
<p>収集した情報は以下の目的にのみ利用します：</p>
<ul>
<li>金利アラートのプッシュ通知配信</li>
<li>返済リマインダーの通知配信</li>
<li>広告の表示（無料版ユーザーのみ）</li>
</ul>

<h2>3. 第三者への提供</h2>
<p>収集した情報は、法令に基づく場合を除き、第三者に提供することはありません。ただし、広告配信のためにGoogle AdMobがデータを収集する場合があります。</p>

<h2>4. データの保管</h2>
<p>プッシュ通知用のデバイストークンとアラート設定は、Cloudflare Workers KV上に暗号化された通信を通じて保管されます。ユーザーがアプリを削除した場合、端末内のデータはすべて消去されます。</p>

<h2>5. サブスクリプション</h2>
<p>本アプリはオプションの自動更新サブスクリプション（Proプラン）を提供しています。お支払いはApple IDアカウントに請求されます。サブスクリプションは現在の期間終了の24時間前までにキャンセルしない限り自動的に更新されます。管理・キャンセルはApple IDの設定から行えます。</p>

<h2>6. お問い合わせ</h2>
<p>プライバシーに関するお問い合わせは、以下までご連絡ください。</p>
<p>Email: kinritilyusyou@outlook.jp</p>
<p>最終更新日：2026年5月27日</p>
</body></html>`);
});

app.get('/terms', (c) => {
  return c.html(`<!DOCTYPE html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>利用規約 - 借入金利モニター</title><style>body{font-family:-apple-system,sans-serif;max-width:700px;margin:0 auto;padding:20px;line-height:1.8;color:#333}h1{font-size:1.4em}h2{font-size:1.1em;margin-top:2em}p{margin:0.8em 0}</style></head><body>
<h1>利用規約</h1>
<p>本利用規約は、借入金利モニター（以下「本アプリ」）の利用条件を定めるものです。</p>

<h2>1. サービス内容</h2>
<p>本アプリは、日本銀行が公開する時系列統計データを利用し、金利動向の参考情報を提供するアプリケーションです。</p>

<h2>2. 免責事項</h2>
<p>本アプリは投資助言、金融アドバイス、または金融商品の推奨を行うものではありません。表示されるデータの正確性、完全性、最新性を保証するものではなく、本アプリの利用により生じた損害について開発者は一切の責任を負いません。重要な財務判断を行う際は、必ず専門家にご相談ください。</p>

<h2>3. サブスクリプション</h2>
<p>本アプリは自動更新サブスクリプション「Proプラン」を提供します。</p>
<ul>
<li>月額プラン：¥300/月</li>
<li>年額プラン：¥2,500/年（初回1ヶ月無料体験付き）</li>
</ul>
<p>お支払いはApple IDアカウントに請求されます。サブスクリプションは現在の期間終了の24時間前までにキャンセルしない限り自動更新されます。Apple IDのアカウント設定からいつでも管理・キャンセルできます。無料体験期間中にキャンセルした場合、課金は発生しません。</p>

<h2>4. 変更</h2>
<p>本規約は予告なく変更される場合があります。変更後のアプリ利用をもって新規約に同意したものとみなします。</p>

<p>最終更新日：2026年5月27日</p>
</body></html>`);
});

// ── Export ──────────────────────────────

export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: Bindings, ctx: ExecutionContext) {
    ctx.waitUntil(handleCron(env));
  },
};
