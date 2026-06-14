import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/colors.dart';
import '../../../services/markdown_helpers.dart';

class OhtliAlertBlockEditor extends StatefulWidget {
  final AlertData alertData;
  final Function(String) onChanged;
  final bool isDark;

  const OhtliAlertBlockEditor({
    super.key,
    required this.alertData,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<OhtliAlertBlockEditor> createState() => _OhtliAlertBlockEditorState();
}

class _OhtliAlertBlockEditorState extends State<OhtliAlertBlockEditor> {
  late AlertType _currentType;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _currentType = widget.alertData.type;
    _controller = TextEditingController(text: widget.alertData.content);
    _focusNode = FocusNode();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(OhtliAlertBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alertData.content != widget.alertData.content) {
      _controller.removeListener(_handleTextChanged);
      _controller.text = widget.alertData.content;
      _controller.addListener(_handleTextChanged);
    }
    if (oldWidget.alertData.type != widget.alertData.type) {
      setState(() {
        _currentType = widget.alertData.type;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    _triggerUpdate(_currentType);
  }

  void _triggerUpdate(AlertType type) {
    final markdown = serializeAlertMarkdown(type, _controller.text);
    widget.onChanged(markdown);
  }

  void _injectMarkdown(String wrapper) {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid) {
      final newText = text + wrapper;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      _focusNode.requestFocus();
      return;
    }

    int start = selection.start;
    int end = selection.end;
    String selectedText = selection.textInside(text);

    if (start == end) {
      int wordStart = start;
      while (wordStart > 0 && _isWordChar(text[wordStart - 1])) {
        wordStart--;
      }
      int wordEnd = end;
      while (wordEnd < text.length && _isWordChar(text[wordEnd])) {
        wordEnd++;
      }
      if (wordStart < wordEnd) {
        start = wordStart;
        end = wordEnd;
        selectedText = text.substring(start, end);
      }
    }

    final len = wrapper.length;
    final newText = text.replaceRange(start, end, '$wrapper$selectedText$wrapper');
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start + len,
        extentOffset: start + len + selectedText.length,
      ),
    );
    _focusNode.requestFocus();
  }

  bool _isWordChar(String char) {
    if (char.isEmpty) return false;
    const exclude = {' ', '\n', '\r', '\t', '*', '_', '~', '.', ',', '!', '?', ';', ':', '(', ')', '[', ']', '{', '}'};
    return !exclude.contains(char);
  }

  @override
  Widget build(BuildContext context) {
    Color alertColor = OhtliColors.stormyTeal;
    IconData alertIcon = Icons.info_outline_rounded;
    String alertName = "Nota / Info";
    
    if (_currentType == AlertType.warning) {
      alertColor = OhtliColors.xoconostle;
      alertIcon = Icons.warning_amber_rounded;
      alertName = "Advertencia";
    } else if (_currentType == AlertType.tip) {
      alertColor = OhtliColors.cempasuchil;
      alertIcon = Icons.lightbulb_outline_rounded;
      alertName = "Consejo / Tip";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF2C2C32) : alertColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDark ? alertColor.withValues(alpha: 0.4) : alertColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: alertColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(alertIcon, color: alertColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alertName,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: alertColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Type Tabs Selector
              Wrap(
                spacing: 8,
                children: AlertType.values.map((type) {
                  final bool isSelected = _currentType == type;
                  Color chipColor = OhtliColors.stormyTeal;
                  String label = "Nota";
                  if (type == AlertType.warning) {
                    chipColor = OhtliColors.xoconostle;
                    label = "Alerta";
                  } else if (type == AlertType.tip) {
                    chipColor = OhtliColors.cempasuchil;
                    label = "Consejo";
                  }

                  return ChoiceChip(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    checkmarkColor: Colors.white,
                    label: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : chipColor,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: chipColor,
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? Colors.transparent : chipColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _currentType = type;
                        });
                        _triggerUpdate(type);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown('**'),
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown('**'),
              const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown('*'),
              const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown('*'),
              const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown('_'),
              const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown('_'),
            },
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 3,
              maxLines: null,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: OhtliColors.onyx,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Escribe tu nota, advertencia o tip aquí...',
                hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
