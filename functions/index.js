const {
  onDocumentCreated,
  onDocumentDeleted,
} = require('firebase-functions/v2/firestore');
const {logger} = require('firebase-functions');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getStorage} = require('firebase-admin/storage');

initializeApp();

// Error codes FCM returns for tokens that will never work again.
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

const MAX_BODY_LENGTH = 200;

/**
 * Sends a push notification to every other participant of a chat when a
 * message is added to it.
 *
 * Device tokens are read from `users/{uid}.fcmTokens`, which the app writes
 * on start. Tokens FCM reports as dead are removed from that list.
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
      if (recipientIds.length === 0) return;

      const userSnaps = await db.getAll(
          ...recipientIds.map((uid) => db.collection('users').doc(uid)),
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

      const chatName = (chat.name || '').trim();
      const senderName = (message.senderName || '').trim() || 'Someone';
      // Picture and voice messages have no text of their own.
      const text = String(message.text || '') ||
        (message.imageUrl ? '📷 Photo' : '') ||
        (message.audioUrl ? '🎤 Voice message' : '');
      const body = text.length > MAX_BODY_LENGTH ?
        `${text.slice(0, MAX_BODY_LENGTH)}…` :
        text;

      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: {
          // Named chats show "Chat name" / "Sender: text"; unnamed ones
          // show the sender as the title.
          title: chatName || senderName,
          body: chatName ? `${senderName}: ${body}` : body,
        },
        // Read by the app to open the right chat when the push is tapped.
        data: {chatCode: chatId, chatName},
        android: {
          priority: 'high',
          notification: {channelId: 'messages', tag: chatId},
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
          logger.warn('Push failed', {chatId, code: result.error?.code});
        }
      });
      await Promise.all(cleanups);

      logger.info('Pushes sent', {
        chatId,
        sent: response.successCount,
        failed: response.failureCount,
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
