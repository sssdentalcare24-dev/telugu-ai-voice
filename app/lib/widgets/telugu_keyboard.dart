import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// On-screen Telugu keyboard that types into any [TextEditingController].
///
/// Works on Android and the web even when the device has no Telugu keyboard
/// installed. (Gboard's Telugu layout works too, through the normal text field.)
class TeluguKeyboard extends StatefulWidget {
  const TeluguKeyboard({super.key, required this.controller, this.onClose});

  final TextEditingController controller;
  final VoidCallback? onClose;

  static const List<String> vowels = [
    'అ', 'ఆ', 'ఇ', 'ఈ', 'ఉ', 'ఊ', 'ఋ', 'ౠ', 'ఎ', 'ఏ', 'ఐ', 'ఒ', 'ఓ', 'ఔ', 'అం', 'అః', //
  ];

  static const List<String> consonants = [
    'క', 'ఖ', 'గ', 'ఘ', 'ఙ', 'చ', 'ఛ', 'జ', 'ఝ', 'ఞ', 'ట', 'ఠ', 'డ', 'ఢ', 'ణ', //
    'త', 'థ', 'ద', 'ధ', 'న', 'ప', 'ఫ', 'బ', 'భ', 'మ', 'య', 'ర', 'ల', 'వ', 'శ', //
    'ష', 'స', 'హ', 'ళ', 'క్ష', 'ఱ', //
  ];

  /// Vowel signs (గుణింతాలు) and other combining marks.
  static const List<String> signs = [
    'ా', 'ి', 'ీ', 'ు', 'ూ', 'ృ', 'ౄ', 'ె', //
    'ే', 'ై', 'ొ', 'ో', 'ౌ', 'ం', 'ః', 'ఁ', //
    '్', '‌', //
  ];

  static const List<String> numbersAndPunctuation = [
    '౦', '౧', '౨', '౩', '౪', '౫', '౬', '౭', '౮', '౯', //
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', //
    '.', ',', '?', '!', '।', '-', '"', "'", '(', ')', //
  ];

  @override
  State<TeluguKeyboard> createState() => _TeluguKeyboardState();
}

class _TeluguKeyboardState extends State<TeluguKeyboard> {
  int _page = 0;

  static const _pages = <(String, String)>[
    ('అచ్చులు', 'Vowels'),
    ('హల్లులు', 'Consonants'),
    ('గుణింతాలు', 'Signs'),
    ('౧౨౩ ?!', 'Numbers'),
  ];

  List<String> get _keys => switch (_page) {
        0 => TeluguKeyboard.vowels,
        1 => TeluguKeyboard.consonants,
        2 => TeluguKeyboard.signs,
        _ => TeluguKeyboard.numbersAndPunctuation,
      };

  TextSelection _selection() {
    final value = widget.controller.value;
    final sel = value.selection;
    if (!sel.isValid) return TextSelection.collapsed(offset: value.text.length);
    return sel;
  }

  void _insert(String s) {
    final text = widget.controller.text;
    final sel = _selection();
    final newText = text.replaceRange(sel.start, sel.end, s);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + s.length),
    );
  }

  /// Deletes one code point (so a vowel sign can be removed on its own).
  void _backspace() {
    final text = widget.controller.text;
    final sel = _selection();
    if (!sel.isCollapsed) {
      widget.controller.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    if (sel.start == 0) return;
    var start = sel.start - 1;
    final unit = text.codeUnitAt(start);
    if (unit >= 0xDC00 && unit <= 0xDFFF && start > 0) start -= 1; // surrogate pair
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, sel.start, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }

  String _label(String key) {
    if (key == '‌') return 'ZWNJ';
    // Show combining marks on a dotted circle, like printed Telugu primers.
    final rune = key.runes.first;
    final isMark = (rune >= 0x0C00 && rune <= 0x0C03) || (rune >= 0x0C3E && rune <= 0x0C56);
    return isMark ? '◌$key' : key;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(_pages[i].$1),
                            tooltip: _pages[i].$2,
                            selected: _page == i,
                            onSelected: (_) => setState(() => _page = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Close Telugu keyboard',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.keyboard_hide_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final key in _keys)
                _Key(
                  label: _label(key),
                  semantic: key,
                  onTap: () => _insert(key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _insert(' '),
                  icon: const Icon(Icons.space_bar_rounded),
                  label: const Text('Space'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _insert('\n'),
                icon: const Icon(Icons.keyboard_return_rounded),
                label: const Text('Enter'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Backspace',
                onPressed: _backspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.semantic, required this.onTap});

  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 46, minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.teluguFont,
                fontFamilyFallback: const [AppTheme.latinFont],
                fontSize: label.length > 3 ? 13 : 20,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
