import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { pinoHttp } from 'pino-http';
import { config } from './config.js';
import { logger } from './logger.js';
import { pool } from './db.js';
import { redis } from './redis.js';
import { errorHandler, notFoundHandler } from './lib/errors.js';
import { sdkRouter } from './routes/sdk.js';
import { serverRouter } from './routes/v1.js';
import { meHandler, portalAuthRouter } from './routes/portal/auth.js';
import { requireUser } from './middleware/portalAuth.js';
import { onboardingRouter } from './routes/portal/onboarding.js';
import { appsRouter } from './routes/portal/apps.js';
import { reportsRouter } from './routes/portal/reports.js';
import { teamRouter } from './routes/portal/team.js';
import { adminRouter } from './routes/admin.js';
import { polmasRouter } from './routes/polmas.js';
import { partnerRouter } from './routes/partner.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet({ contentSecurityPolicy: false, crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(
    pinoHttp({
      logger,
      autoLogging: { ignore: (req) => req.url === '/healthz' },
      // jangan pernah log access_token (SSE) atau query berisi PII
      serializers: {
        req: (req) => ({ id: req.id, method: req.method, url: String(req.url).split('?')[0], remoteAddress: req.remoteAddress }),
      },
    }),
  );
  app.use(express.json({ limit: '64kb' }));

  app.get('/healthz', async (_req, res) => {
    const db = await pool.query('SELECT 1').then(() => true, () => false);
    const r = redis.status === 'ready';
    // Redis turun tidak menghentikan SOS API (rate limit fail-open), jadi tetap 200 bila DB sehat.
    res.status(db ? 200 : 503).json({ ok: db, db, redis: r });
  });

  // CORS: SDK memakai CORS dinamis per app (di sdkRouter). Portal/admin hanya dari origin yang dikonfigurasi.
  app.use('/v1/sdk', sdkRouter);
  // Aplikasi Polmas Keamanan (token pks_…); dipasang sebelum /v1 supaya tidak lewat auth secret key.
  app.use('/v1/pk', cors({ origin: false }), polmasRouter);
  // /v1/partner = alias yang lewat proxy produksi (sos.tip2.co hanya meneruskan /v1, /portal, /admin ke API).
  // Wajib sebelum app.use('/v1') karena router /v1 memasang secretKeyAuth untuk semua path di bawahnya.
  app.use(['/partner/v1', '/v1/partner'], cors({ origin: false }), partnerRouter);
  app.use('/v1', cors({ origin: false }), serverRouter);

  const portalCors = cors({ origin: config.portalOrigins, credentials: false, maxAge: 600 });
  app.use('/portal/auth', portalCors, portalAuthRouter);
  app.use('/portal/onboarding', portalCors, onboardingRouter);
  app.use('/portal/apps', portalCors, appsRouter);
  app.use('/portal/reports', portalCors, reportsRouter);
  app.use('/portal/team', portalCors, teamRouter);
  // app.use (bukan app.get) supaya preflight OPTIONS dari browser juga dijawab CORS.
  app.use('/portal/me', portalCors);
  app.get('/portal/me', requireUser, meHandler);
  app.use('/admin', portalCors, adminRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
