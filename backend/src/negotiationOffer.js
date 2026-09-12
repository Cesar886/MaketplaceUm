'use strict';

const PREFIX = '__UM_NEGOTIATION_V1__:';

function encodeNegotiationOffer({ productId, productTitle, listPrice, amount, senderRole, replyToOfferId = null }) {
  const payload = {
    kind: 'proposal',
    productId,
    productTitle,
    listPrice,
    amount,
    senderRole,
    replyToOfferId
  };
  return PREFIX + Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
}

function parseNegotiationOffer(text) {
  if (typeof text !== 'string' || !text.startsWith(PREFIX)) return null;
  try {
    const payload = JSON.parse(Buffer.from(text.slice(PREFIX.length), 'base64url').toString('utf8'));
    if (payload?.kind !== 'proposal' || typeof payload.productId !== 'string'
      || typeof payload.productTitle !== 'string' || !Number.isFinite(payload.listPrice)
      || !Number.isFinite(payload.amount) || !['buyer', 'seller'].includes(payload.senderRole)) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}

module.exports = { PREFIX, encodeNegotiationOffer, parseNegotiationOffer };
