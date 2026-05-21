import { Hono } from 'hono';
import { cors } from 'hono/cors';

type Bindings = {
  CACHE: KVNamespace;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use('*', cors());

app.get('/', (c) => {
  return c.json({
    name: '借入金利モニター API',
    version: '0.1.0',
    endpoints: [
      'GET /api/rates/latest',
      'GET /api/rates/history?series=...&from=...&to=...',
      'GET /api/environment',
    ],
  });
});

// Phase 1 で実装予定
app.get('/api/rates/latest', (c) => {
  return c.json({ message: 'Phase 1 で実装予定' }, 501);
});

app.get('/api/rates/history', (c) => {
  return c.json({ message: 'Phase 1 で実装予定' }, 501);
});

app.get('/api/environment', (c) => {
  return c.json({ message: 'Phase 1 で実装予定' }, 501);
});

export default app;
