import 'package:flutter/foundation.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';

/// What the message field is composing besides plain text: a reply to a
/// message or an edit of one. At most one of the two at a time.
class ComposerController extends ChangeNotifier {
  ChatMessage? _replyTo;
  ChatMessage? _editing;

  ChatMessage? get replyTo => _replyTo;
  ChatMessage? get editing => _editing;

  void reply(ChatMessage message) {
    _replyTo = message;
    _editing = null;
    notifyListeners();
  }

  void edit(ChatMessage message) {
    _editing = message;
    _replyTo = null;
    notifyListeners();
  }

  void clear() {
    if (_replyTo == null && _editing == null) return;
    _replyTo = null;
    _editing = null;
    notifyListeners();
  }
}
