/**
 * Normalize an Indian phone number to 10 digits.
 * Handles: +91XXXXXXXXXX, 91XXXXXXXXXX, 0XXXXXXXXXX, XXXXXXXXXX
 */
function normalizeIndianNumber(raw) {
  let num = String(raw).replace(/\D/g, '');
  if (num.startsWith('91') && num.length === 12) num = num.slice(2);
  if (num.startsWith('0') && num.length === 11) num = num.slice(1);
  return num.slice(-10);
}

module.exports = { normalizeIndianNumber };
