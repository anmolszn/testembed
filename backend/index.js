const express = require('express');
const crypto = require('crypto');
const { createSession, getSession, verifySession } = require('./sessionStore');
const { normalizeIndianNumber } = require('./phoneUtils');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Set your Virtual Mobile Number (VMN) here or via environment variable
const VMN = process.env.VMN || 'XXXXXXXXXX';
const PORT = process.env.PORT || 3000;

// POST /auth/start — Flutter calls this after user picks a SIM
app.post('/auth/start', (req, res) => {
  const { phoneNumber } = req.body;
  if (!phoneNumber) return res.status(400).json({ error: 'phoneNumber required' });

  const token = crypto.randomBytes(8).toString('hex').toUpperCase();
  const normalized = normalizeIndianNumber(phoneNumber);
  createSession(token, normalized, VMN);

  console.log(`[start] phone=${normalized} token=${token}`);
  res.json({ token, vmn: VMN });
});

// GET /auth/status?token=XYZ — Flutter polls this every 2s
app.get('/auth/status', (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).json({ error: 'token required' });

  const session = getSession(token);
  if (!session) return res.json({ status: 'expired' });

  res.json({ status: session.status });
});

// POST /sms/webhook — Your VMN provider calls this when SMS arrives
// Supports Twilio (From/Body) and generic (from/message) formats
app.post('/sms/webhook', (req, res) => {
  const from = req.body.From || req.body.from || '';
  const body = req.body.Body || req.body.message || '';

  console.log(`[webhook] from=${from} body=${body}`);

  const match = body.match(/VERIFY_([A-F0-9]{16})/i);
  if (!match) return res.sendStatus(200);

  const token = match[1].toUpperCase();
  const senderNorm = normalizeIndianNumber(from);
  const session = getSession(token);

  if (session && session.status === 'pending' && session.phoneNumber === senderNorm) {
    verifySession(token);
    console.log(`[webhook] verified token=${token} phone=${senderNorm}`);
  }

  res.sendStatus(200);
});

app.listen(PORT, () => {
  console.log(`SIM binding backend running on http://localhost:${PORT}`);
  console.log(`VMN: ${VMN}`);
  console.log(`Expose with: npx ngrok http ${PORT}`);
});
