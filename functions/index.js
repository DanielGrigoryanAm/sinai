const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const {logger} = require('firebase-functions');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getStorage} = require('firebase-admin/storage');
const {getAuth} = require('firebase-admin/auth');

initializeApp();

// Error codes FCM returns for tokens that will never work again.
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

const MAX_BODY_LENGTH = 200;

/** Cuts long text for a notification body. */
function shorten(text) {
  return text.length > MAX_BODY_LENGTH ?
    `${text.slice(0, MAX_BODY_LENGTH)}…` :
    text;
}

/** What a message is, for notifications: its text, or Photo / Voice. */
function describeMessage(message) {
  return String(message.text || '') ||
    (message.imageUrl ? '📷 Photo' : '') ||
    (message.audioUrl ? '🎤 Voice message' : '');
}

/**
 * Sends a push to every device of the given users and removes tokens FCM
 * reports as dead.
 *
 * Device tokens are read from `users/{uid}.fcmTokens`, which the app writes
 * on start. [tag] groups pushes on Android: a newer one with the same tag
 * replaces the older one.
 */
async function sendToUsers(userIds, {title, body, data, tag}) {
  if (userIds.length === 0) return;
  const db = getFirestore();

  const userSnaps = await db.getAll(
      ...userIds.map((uid) => db.collection('users').doc(uid)),
  );

  // Remember which user each token belongs to, to clean up dead ones.
  const tokenOwners = new Map();
  for (const snap of userSnaps) {
    for (const token of snap.data()?.fcmTokens || []) {
      tokenOwners.set(token, snap.id);
    }
  }
  const tokens = [...tokenOwners.keys()];
  if (tokens.length === 0) return;

  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {title, body},
    data,
    android: {
      priority: 'high',
      notification: {channelId: 'messages', tag},
    },
  });

  const cleanups = [];
  response.responses.forEach((result, index) => {
    if (result.success) return;
    const token = tokens[index];
    if (DEAD_TOKEN_CODES.has(result.error?.code)) {
      cleanups.push(
          db.collection('users').doc(tokenOwners.get(token)).update({
            fcmTokens: FieldValue.arrayRemove(token),
          }),
      );
    } else {
      logger.warn('Push failed', {tag, code: result.error?.code});
    }
  });
  await Promise.all(cleanups);

  logger.info('Pushes sent', {
    tag,
    sent: response.successCount,
    failed: response.failureCount,
  });
}

/**
 * Sends a push notification to every other participant of a chat when a
 * message is added to it.
 */
exports.notifyNewMessage = onDocumentCreated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const message = event.data?.data();
      if (!message) return;

      const {chatId} = event.params;
      const db = getFirestore();

      const chatSnap = await db.collection('chats').doc(chatId).get();
      if (!chatSnap.exists) return;
      const chat = chatSnap.data();

      const recipientIds = (chat.participantIds || [])
          .filter((uid) => uid !== message.senderId);

      const chatName = (chat.name || '').trim();
      const senderName = (message.senderName || '').trim() || 'Someone';
      const body = shorten(describeMessage(message));

      await sendToUsers(recipientIds, {
        // Named chats show "Chat name" / "Sender: text"; unnamed ones
        // show the sender as the title.
        title: chatName || senderName,
        body: chatName ? `${senderName}: ${body}` : body,
        // Read by the app to open the right chat when the push is tapped.
        data: {chatCode: chatId, chatName},
        tag: chatId,
      });
    },
);

/**
 * Cleans up after a chat is deleted by its owner: removes the photos and
 * voice messages stored under `chats/{chatId}/` in Cloud Storage, and any
 * messages the app did not manage to delete itself.
 *
 * Leaving a chat does not delete its document, so this never runs for it.
 */
exports.cleanUpDeletedChat = onDocumentDeleted(
    'chats/{chatId}',
    async (event) => {
      const {chatId} = event.params;

      // The trailing slash keeps "ABC" from also matching "ABCD".
      await getStorage().bucket().deleteFiles({prefix: `chats/${chatId}/`});

      await getFirestore().recursiveDelete(
          getFirestore().collection('chats').doc(chatId).collection('messages'),
      );

      logger.info('Deleted chat cleaned up', {chatId});
    },
);

/**
 * Turns a Firebase Storage download URL into the object's path in the
 * bucket, e.g. `chats/ABC123/images/1700000000000_uid.jpg`.
 */
function storagePathFromUrl(url) {
  if (typeof url !== 'string') return null;
  const match = /\/o\/([^?]+)/.exec(url);
  return match ? decodeURIComponent(match[1]) : null;
}

/**
 * Removes the photo or voice file of a message that was deleted, so files
 * of deleted messages do not pile up in Cloud Storage.
 */
exports.cleanUpDeletedMessage = onDocumentDeleted(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const message = event.data?.data();
      if (!message) return;

      const {chatId} = event.params;
      const paths = [message.imageUrl, message.audioUrl]
          .map(storagePathFromUrl)
          // Only ever touch this chat's own files.
          .filter((path) => path && path.startsWith(`chats/${chatId}/`));

      // When the whole chat is deleted its files are already gone, hence
      // ignoreNotFound.
      await Promise.all(paths.map((path) =>
        getStorage().bucket().file(path).delete({ignoreNotFound: true}),
      ));
    },
);

// Reactions saved before they were emoji, by their old id.
const LEGACY_REACTIONS = {
  love: '❤️',
  like: '👍',
  laugh: '😂',
  sad: '😢',
  fire: '🔥',
  dislike: '👎',
};

/**
 * Tells the author of a message when someone reacts to it. Only new or
 * changed reactions notify; removing one, editing the text or reacting to
 * your own message does not.
 */
exports.notifyReaction = onDocumentUpdated(
    'chats/{chatId}/messages/{messageId}',
    async (event) => {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after) return;

      const oldReactions = before.reactions || {};
      const newReactions = after.reactions || {};
      const reactorIds = Object.keys(newReactions).filter((uid) =>
        uid !== after.senderId &&
        typeof newReactions[uid] === 'string' &&
        newReactions[uid] !== oldReactions[uid],
      );
      if (reactorIds.length === 0) return;

      const {chatId, messageId} = event.params;
      const chatSnap = await getFirestore().collection('chats').doc(chatId)
          .get();
      if (!chatSnap.exists) return;
      const chatName = (chatSnap.data().name || '').trim();

      // Normally one reaction per update.
      for (const uid of reactorIds) {
        let reactorName = 'Someone';
        try {
          const user = await getAuth().getUser(uid);
          reactorName = (user.displayName || '').trim() || reactorName;
        } catch (_) {
          // An unknown user still gets a reaction notification.
        }

        const reaction = newReactions[uid];
        const emoji = LEGACY_REACTIONS[reaction] || reaction;
        const quoted = shorten(describeMessage(after));

        await sendToUsers([after.senderId], {
          title: chatName || reactorName,
          body: `${reactorName} reacted ${emoji} to: ${quoted}`,
          data: {chatCode: chatId, chatName},
          // One notification per message, updated if reactions keep coming.
          tag: `reaction-${messageId}`,
        });
      }
    },
);

const GAME_NAMES = {ttt: 'tic-tac-toe', chess: 'chess', checkers: 'checkers'};

/** 'w', 'b', 'x' or 'o': the side to move in [game]. */
function sideToMove(game) {
  if (game.type === 'chess') return String(game.fen || '').split(' ')[1];
  return game.turn;
}

/** The player of [side] in [game], or null while nobody has taken it. */
function playerOf(game, side) {
  if (side === 'w') return game.white || null;
  if (side === 'b') return game.black || null;
  if (side === 'x') return game.x || null;
  if (side === 'o') return game.o || null;
  return null;
}

/**
 * Tells the other members when someone starts a mini game in the chat,
 * and the next player when it's their turn. Finished games tell everyone
 * how they ended.
 */
exports.notifyGame = onDocumentUpdated(
    'chats/{chatId}',
    async (event) => {
      const before = event.data?.before.data()?.game || {};
      const after = event.data?.after.data()?.game;
      if (!after || !after.by || !after.at) return;
      // Only writes that start a game or make a move carry a new time.
      if (before.at && after.at.isEqual?.(before.at)) return;

      const {chatId} = event.params;
      const chat = event.data.after.data();
      const chatName = (chat.name || '').trim();
      const others = (chat.participantIds || [])
          .filter((uid) => uid !== after.by);
      if (others.length === 0) return;

      let actorName = 'Someone';
      try {
        const user = await getAuth().getUser(after.by);
        actorName = (user.displayName || '').trim() || actorName;
      } catch (_) {
        // An unknown player still gets a notification.
      }
      const gameName = GAME_NAMES[after.type || 'ttt'] || 'a game';

      let recipients = others;
      let body;
      if (after.event === 'start') {
        body = `${actorName} invites you to play ${gameName}`;
      } else {
        const result = after.result ?? after.winner;
        if (result === 'draw') {
          body = `Your ${gameName} game with ${actorName} ended in a draw`;
        } else if (result) {
          body = `${actorName} won the ${gameName} game`;
        } else {
          // The player to move, or everyone while that side is still free.
          const next = playerOf(after, sideToMove(after));
          if (next) recipients = [next].filter((uid) => uid !== after.by);
          body = `${actorName} made a move in ${gameName}. Your turn!`;
        }
      }
      if (recipients.length === 0) return;

      await sendToUsers(recipients, {
        title: chatName || actorName,
        body,
        data: {chatCode: chatId, chatName},
        // One game notification per chat, replaced by the next one.
        tag: `game-${chatId}`,
      });
    },
);
