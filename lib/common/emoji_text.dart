import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The system's colour emoji font. Named outright: otherwise the app's
/// text font answers first for the few emoji it has as plain black
/// symbols, such as the heart.
String get emojiFontFamily =>
    defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? 'Apple Color Emoji'
        : 'Noto Color Emoji';

/// A style for emoji alone.
TextStyle get emojiStyle => TextStyle(fontFamily: emojiFontFamily);

final _emoji = RegExp(
  // The analyzer reads this without the unicode flag; it runs fine.
  // ignore: valid_regexps
  r'(?:\p{Extended_Pictographic}|\p{Regional_Indicator})'
  r'(?:\uFE0F|\p{Emoji_Modifier}|\u20E3|\u200D'
  r'(?:\p{Extended_Pictographic}|\p{Regional_Indicator})'
  r'|\p{Regional_Indicator})*',
  unicode: true,
);

/// [text] as spans, its emoji in the colour emoji font.
List<InlineSpan> emojiSpans(String text, {TextStyle? style}) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _emoji.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: style));
    }
    spans.add(TextSpan(
      text: m.group(0),
      style: (style ?? const TextStyle()).merge(emojiStyle),
    ));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
  }
  return spans;
}
