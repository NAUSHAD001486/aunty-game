/**
 * Same-origin proxy: Flutter web → this API → Telegram sendPhoto.
 * Token MUST be set in Vercel env (never expose a revoked token in git).
 *
 * POST JSON: { caption, fileName, photoBase64 }
 */
const FormData = require('form-data');

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function mimeForFileName(fileName) {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

module.exports = async function handler(req, res) {
  setCors(res);

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ ok: false, error: 'method_not_allowed' });
  }

  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID || '2143800994';

  if (!botToken) {
    console.error('[telegram-send-photo] TELEGRAM_BOT_TOKEN env missing');
    return res.status(500).json({
      ok: false,
      error: 'server_misconfigured',
      hint: 'Set TELEGRAM_BOT_TOKEN in Vercel project settings',
    });
  }

  try {
    let body = req.body;
    if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch (_) {
        return res.status(400).json({ ok: false, error: 'invalid_json' });
      }
    }
    if (!body || typeof body !== 'object') {
      return res.status(400).json({ ok: false, error: 'missing_body' });
    }

    const caption = (body.caption || '').toString();
    const fileName = (body.fileName || 'winner_claim.jpg').toString();
    const photoBase64 = (body.photoBase64 || '').toString();

    if (!photoBase64) {
      return res.status(400).json({ ok: false, error: 'photoBase64_required' });
    }

    const buffer = Buffer.from(photoBase64, 'base64');
    if (buffer.length < 32) {
      return res.status(400).json({ ok: false, error: 'photo_too_small' });
    }
    if (buffer.length > 4_000_000) {
      return res.status(413).json({ ok: false, error: 'photo_too_large' });
    }

    const form = new FormData();
    form.append('chat_id', chatId);
    form.append('caption', caption);
    form.append('photo', buffer, {
      filename: fileName,
      contentType: mimeForFileName(fileName),
    });

    const tgRes = await fetch(
      `https://api.telegram.org/bot${botToken}/sendPhoto`,
      {
        method: 'POST',
        // @ts-ignore — form-data stream for Node fetch
        body: form,
        headers: form.getHeaders(),
      },
    );

    const tgText = await tgRes.text();
    let tgJson;
    try {
      tgJson = JSON.parse(tgText);
    } catch (_) {
      tgJson = { ok: false, description: tgText };
    }

    if (!tgRes.ok || tgJson.ok === false) {
      console.error(
        '[telegram-send-photo] Telegram error',
        tgRes.status,
        tgText,
      );
      return res.status(502).json({
        ok: false,
        error: 'telegram_failed',
        telegram: tgJson,
      });
    }

    return res.status(200).json({ ok: true });
  } catch (e) {
    console.error('[telegram-send-photo] handler error', e);
    return res.status(500).json({
      ok: false,
      error: e?.message || 'internal_error',
    });
  }
};
