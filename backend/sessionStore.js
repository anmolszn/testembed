const sessions = new Map(); // token → { phoneNumber, vmn, status, expiresAt }
const EXPIRY_MS = 60 * 1000; // 60 seconds

function createSession(token, phoneNumber, vmn) {
  sessions.set(token, {
    phoneNumber,
    vmn,
    status: 'pending',
    expiresAt: Date.now() + EXPIRY_MS,
  });
}

function getSession(token) {
  const session = sessions.get(token);
  if (!session) return null;
  if (Date.now() > session.expiresAt) {
    sessions.delete(token);
    return { status: 'expired' };
  }
  return session;
}

function verifySession(token) {
  const session = sessions.get(token);
  if (session) session.status = 'verified';
}

// Clean up expired sessions every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [token, session] of sessions.entries()) {
    if (now > session.expiresAt) sessions.delete(token);
  }
}, 5 * 60 * 1000);

module.exports = { createSession, getSession, verifySession };
