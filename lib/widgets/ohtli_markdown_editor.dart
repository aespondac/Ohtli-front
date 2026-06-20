import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class StyleState {
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;

  const StyleState({
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
  });

  StyleState copyWith({
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
  }) {
    return StyleState(
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
    );
  }
}

class MarkdownRichTextController extends TextEditingController {
  final BuildContext context;
  final List<StyleState> _characterStyles = [];

  // Toggled formatting states for the next typed characters
  bool _isBoldToggled = false;
  bool _isItalicToggled = false;
  bool _isUnderlineToggled = false;
  bool _hasActiveToggles = false;

  MarkdownRichTextController({String? text, required this.context}) : super() {
    if (text != null && text.isNotEmpty) {
      _loadFromMarkdown(text);
    }
  }

  bool get isBoldActive {
    final sel = selection;
    if (!sel.isValid) return _isBoldToggled;
    if (sel.isCollapsed) {
      if (_hasActiveToggles) return _isBoldToggled;
      final idx = sel.start;
      if (idx > 0 && idx - 1 < _characterStyles.length) {
        return _characterStyles[idx - 1].isBold;
      }
      return false;
    }
    for (int i = sel.start; i < sel.end; i++) {
      if (i >= 0 && i < _characterStyles.length && _characterStyles[i].isBold) {
        return true;
      }
    }
    return false;
  }

  bool get isItalicActive {
    final sel = selection;
    if (!sel.isValid) return _isItalicToggled;
    if (sel.isCollapsed) {
      if (_hasActiveToggles) return _isItalicToggled;
      final idx = sel.start;
      if (idx > 0 && idx - 1 < _characterStyles.length) {
        return _characterStyles[idx - 1].isItalic;
      }
      return false;
    }
    for (int i = sel.start; i < sel.end; i++) {
      if (i >= 0 && i < _characterStyles.length && _characterStyles[i].isItalic) {
        return true;
      }
    }
    return false;
  }

  bool get isUnderlineActive {
    final sel = selection;
    if (!sel.isValid) return _isUnderlineToggled;
    if (sel.isCollapsed) {
      if (_hasActiveToggles) return _isUnderlineToggled;
      final idx = sel.start;
      if (idx > 0 && idx - 1 < _characterStyles.length) {
        return _characterStyles[idx - 1].isUnderline;
      }
      return false;
    }
    for (int i = sel.start; i < sel.end; i++) {
      if (i >= 0 && i < _characterStyles.length && _characterStyles[i].isUnderline) {
        return true;
      }
    }
    return false;
  }

  void toggleBold() {
    final sel = selection;
    if (!sel.isValid) return;

    if (sel.isCollapsed) {
      _isBoldToggled = !_isBoldToggled;
      _hasActiveToggles = true;
      notifyListeners();
    } else {
      bool allBold = true;
      for (int i = sel.start; i < sel.end; i++) {
        if (i >= 0 && i < _characterStyles.length && !_characterStyles[i].isBold) {
          allBold = false;
          break;
        }
      }
      for (int i = sel.start; i < sel.end; i++) {
        if (i >= 0 && i < _characterStyles.length) {
          _characterStyles[i] = _characterStyles[i].copyWith(isBold: !allBold);
        }
      }
      notifyListeners();
    }
  }

  void toggleItalic() {
    final sel = selection;
    if (!sel.isValid) return;

    if (sel.isCollapsed) {
      _isItalicToggled = !_isItalicToggled;
      _hasActiveToggles = true;
      notifyListeners();
    } else {
      bool allItalic = true;
      for (int i = sel.start; i < sel.end; i++) {
        if (i >= 0 && i < _characterStyles.length && !_characterStyles[i].isItalic) {
          allItalic = false;
          break;
        }
      }
      for (int i = sel.start; i < sel.end; i++) {
        if (i >= 0 && i < _characterStyles.length) {
          _characterStyles[i] = _characterStyles[i].copyWith(isItalic: !allItalic);
        }
      }
      notifyListeners();
    }
  }

  void toggleUnderline() {
    final sel = selection;
    if (!sel.isValid) return;

    if (sel.isCollapsed) {
      _isUnderlineToggled = !_isUnderlineToggled;
      _hasActiveToggles = true;
      notifyListeners();
    } else {
      bool allUnderline = true;
      for (int i = sel.start; i < sel.end; i++) {
        if (i >= 0 && i < _characterStyles.length && !_characterStyles[i].isUnderline) {
          allUnderline = false;
          break;
        }
      }
      for (int i = sel.start; i < sel.end; i++) {
        if (i >= 0 && i < _characterStyles.length) {
          _characterStyles[i] = _characterStyles[i].copyWith(isUnderline: !allUnderline);
        }
      }
      notifyListeners();
    }
  }

  String get markdownText => _convertToMarkdown();

  @override
  set text(String newText) {
    _loadFromMarkdown(newText);
  }

  void _loadFromMarkdown(String markdown) {
    _characterStyles.clear();
    final plainTextBuffer = StringBuffer();
    final spans = _parseMarkdownToSpans(markdown);
    for (final span in spans) {
      _flattenSpans(span, const TextStyle(), plainTextBuffer);
    }
    
    final plainText = plainTextBuffer.toString();
    
    super.value = TextEditingValue(
      text: plainText,
      selection: TextSelection.collapsed(offset: plainText.length),
    );
  }

  List<InlineSpan> _parseMarkdownToSpans(String text) {
    final List<InlineSpan> spans = [];
    final regExp = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(\_(.*?)\_)');
    final matches = regExp.allMatches(text);
    
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      
      final String matchText = match.group(0)!;
      if (matchText.startsWith('**') && matchText.endsWith('**')) {
        final innerText = match.group(2) ?? '';
        spans.add(TextSpan(
          children: _parseMarkdownToSpans(innerText),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('*') && matchText.endsWith('*')) {
        final innerText = match.group(4) ?? '';
        spans.add(TextSpan(
          children: _parseMarkdownToSpans(innerText),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('_') && matchText.endsWith('_')) {
        final innerText = match.group(6) ?? '';
        spans.add(TextSpan(
          children: _parseMarkdownToSpans(innerText),
          style: const TextStyle(decoration: TextDecoration.underline),
        ));
      }
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans;
  }

  void _flattenSpans(InlineSpan span, TextStyle currentStyle, StringBuffer plainText) {
    TextStyle activeStyle = currentStyle;
    if (span is TextSpan) {
      if (span.style != null) {
        activeStyle = activeStyle.merge(span.style);
      }
      
      if (span.text != null && span.text!.isNotEmpty) {
        final text = span.text!;
        final state = StyleState(
          isBold: activeStyle.fontWeight == FontWeight.bold,
          isItalic: activeStyle.fontStyle == FontStyle.italic,
          isUnderline: activeStyle.decoration == TextDecoration.underline || 
                       (activeStyle.decoration?.contains(TextDecoration.underline) ?? false),
        );
        for (int i = 0; i < text.length; i++) {
          plainText.write(text[i]);
          _characterStyles.add(state);
        }
      }
      
      if (span.children != null) {
        for (final child in span.children!) {
          _flattenSpans(child, activeStyle, plainText);
        }
      }
    }
  }

  String _convertToMarkdown() {
    final plainText = super.text;
    if (plainText.isEmpty) return '';

    final buffer = StringBuffer();
    int i = 0;
    while (i < plainText.length) {
      final state = i < _characterStyles.length ? _characterStyles[i] : const StyleState();
      int start = i;
      while (i < plainText.length && 
             (i < _characterStyles.length ? _characterStyles[i].isBold : false) == state.isBold && 
             (i < _characterStyles.length ? _characterStyles[i].isItalic : false) == state.isItalic && 
             (i < _characterStyles.length ? _characterStyles[i].isUnderline : false) == state.isUnderline) {
        i++;
      }
      
      final runText = plainText.substring(start, i);
      buffer.write(_wrapText(runText, state));
    }
    return buffer.toString();
  }

  String _wrapText(String text, StyleState style) {
    String result = text;
    if (style.isUnderline) {
      result = '_${result}_';
    }
    if (style.isItalic) {
      result = '*$result*';
    }
    if (style.isBold) {
      result = '**$result**';
    }
    return result;
  }

  @override
  set value(TextEditingValue newValue) {
    final oldText = super.text;
    final newText = newValue.text;
    final newSelection = newValue.selection;

    if (oldText != newText) {
      int start = 0;
      while (start < oldText.length && start < newText.length && oldText[start] == newText[start]) {
        start++;
      }

      int oldEnd = oldText.length;
      int newEnd = newText.length;
      while (oldEnd > start && newEnd > start && oldText[oldEnd - 1] == newText[newEnd - 1]) {
        oldEnd--;
        newEnd--;
      }

      final deletedCount = oldEnd - start;
      final insertedCount = newEnd - start;

      StyleState insertStyle = const StyleState();
      if (_hasActiveToggles) {
        insertStyle = StyleState(
          isBold: _isBoldToggled,
          isItalic: _isItalicToggled,
          isUnderline: _isUnderlineToggled,
        );
      } else if (start > 0 && start - 1 < _characterStyles.length) {
        insertStyle = _characterStyles[start - 1];
      }

      if (deletedCount > 0 && start < _characterStyles.length) {
        final removeEnd = (start + deletedCount).clamp(0, _characterStyles.length);
        _characterStyles.removeRange(start, removeEnd);
      }

      if (insertedCount > 0) {
        final newStyles = List<StyleState>.filled(insertedCount, insertStyle);
        _characterStyles.insertAll(start, newStyles);
      }
    }

    if (newSelection.isCollapsed && newSelection.isValid && newSelection.start >= 0) {
      final idx = newSelection.start;
      if (idx > 0 && idx - 1 < _characterStyles.length) {
        final style = _characterStyles[idx - 1];
        _isBoldToggled = style.isBold;
        _isItalicToggled = style.isItalic;
        _isUnderlineToggled = style.isUnderline;
      } else {
        _isBoldToggled = false;
        _isItalicToggled = false;
        _isUnderlineToggled = false;
      }
      _hasActiveToggles = false;
    }

    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final defaultStyle = style ?? GoogleFonts.inter(color: OhtliColors.onyx);
    final List<InlineSpan> spans = [];

    final plainText = super.text;
    if (plainText.isEmpty) {
      return TextSpan(text: '', style: defaultStyle);
    }

    int i = 0;
    while (i < plainText.length) {
      final state = i < _characterStyles.length ? _characterStyles[i] : const StyleState();
      int start = i;
      while (i < plainText.length && 
             (i < _characterStyles.length ? _characterStyles[i].isBold : false) == state.isBold && 
             (i < _characterStyles.length ? _characterStyles[i].isItalic : false) == state.isItalic && 
             (i < _characterStyles.length ? _characterStyles[i].isUnderline : false) == state.isUnderline) {
        i++;
      }

      final runText = plainText.substring(start, i);
      TextStyle runStyle = defaultStyle;
      if (state.isBold) {
        runStyle = runStyle.copyWith(fontWeight: FontWeight.bold);
      }
      if (state.isItalic) {
        runStyle = runStyle.copyWith(fontStyle: FontStyle.italic);
      }
      if (state.isUnderline) {
        runStyle = runStyle.copyWith(decoration: TextDecoration.underline);
      }

      spans.add(TextSpan(text: runText, style: runStyle));
    }

    return TextSpan(children: spans, style: defaultStyle);
  }
}

class OhtliMarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final int? maxLines;
  final int? minLines;
  final VoidCallback? onChanged;

  const OhtliMarkdownEditor({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    this.maxLines,
    this.minLines,
    this.onChanged,
  });

  @override
  State<OhtliMarkdownEditor> createState() => _OhtliMarkdownEditorState();
}

class _OhtliMarkdownEditorState extends State<OhtliMarkdownEditor> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  void _onTextChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  int get _charCount => widget.controller.text.length;

  int get _wordCount {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  void _injectMarkdown(String wrapper) {
    final controller = widget.controller;
    if (controller is MarkdownRichTextController) {
      if (wrapper == '**') {
        controller.toggleBold();
      } else if (wrapper == '*') {
        controller.toggleItalic();
      } else if (wrapper == '_') {
        controller.toggleUnderline();
      } else if (wrapper == '- ') {
        final text = controller.text;
        final sel = controller.selection;
        if (sel.isValid) {
          int lineStart = sel.start;
          while (lineStart > 0 && text[lineStart - 1] != '\n') {
            lineStart--;
          }
          if (lineStart + 2 <= text.length && text.substring(lineStart, lineStart + 2) == '- ') {
            final newText = text.replaceRange(lineStart, lineStart + 2, '');
            controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: (sel.start - 2).clamp(0, newText.length)),
            );
          } else {
            final newText = text.replaceRange(lineStart, lineStart, '- ');
            controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: sel.start + 2),
            );
          }
        }
      }
      _focusNode.requestFocus();
      widget.onChanged?.call();
      return;
    }

    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) {
      final newText = text + wrapper;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      _focusNode.requestFocus();
      widget.onChanged?.call();
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

    if (wrapper == '- ') {
      if (selectedText.startsWith('- ')) {
        final unwrappedText = selectedText.substring(2);
        final newText = text.replaceRange(start, end, unwrappedText);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + unwrappedText.length,
          ),
        );
      } else {
        final newText = text.replaceRange(start, end, '- $selectedText');
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection(
            baseOffset: start,
            extentOffset: start + 2 + selectedText.length,
          ),
        );
      }
      _focusNode.requestFocus();
      widget.onChanged?.call();
      return;
    }

    final len = wrapper.length;
    const formatChars = {'*', '_', '~'};

    int leftFormatStart = start;
    while (leftFormatStart > 0 && formatChars.contains(text[leftFormatStart - 1])) {
      leftFormatStart--;
    }
    final leftFormats = text.substring(leftFormatStart, start);

    int rightFormatEnd = end;
    while (rightFormatEnd < text.length && formatChars.contains(text[rightFormatEnd])) {
      rightFormatEnd++;
    }
    final rightFormats = text.substring(end, rightFormatEnd);

    if (_hasFormat(leftFormats, rightFormats, wrapper)) {
      final newLeftFormats = leftFormats.replaceFirst(wrapper, '');
      final newRightFormats = rightFormats.replaceFirst(wrapper, '');

      final newText = text.replaceRange(leftFormatStart, rightFormatEnd, '$newLeftFormats$selectedText$newRightFormats');
      final newStart = leftFormatStart + newLeftFormats.length;

      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: newStart,
          extentOffset: newStart + selectedText.length,
        ),
      );
    } else {
      final newText = text.replaceRange(start, end, '$wrapper$selectedText$wrapper');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: start + len,
          extentOffset: start + len + selectedText.length,
        ),
      );
    }

    _focusNode.requestFocus();
    widget.onChanged?.call();
  }

  bool _isWordChar(String char) {
    if (char.isEmpty) return false;
    const exclude = {' ', '\n', '\r', '\t', '*', '_', '~', '.', ',', '!', '?', ';', ':', '(', ')', '[', ']', '{', '}'};
    return !exclude.contains(char);
  }

  bool _hasFormat(String left, String right, String wrapper) {
    final leftAsterisks = _countOccurrences(left, '*');
    final rightAsterisks = _countOccurrences(right, '*');
    final leftUnderlines = _countOccurrences(left, '_');
    final rightUnderlines = _countOccurrences(right, '_');

    if (wrapper == '**') {
      return leftAsterisks >= 2 && rightAsterisks >= 2;
    } else if (wrapper == '*') {
      return leftAsterisks >= 1 && rightAsterisks >= 1;
    } else if (wrapper == '_') {
      return leftUnderlines >= 1 && rightUnderlines >= 1;
    }
    return false;
  }

  int _countOccurrences(String source, String char) {
    int count = 0;
    for (int i = 0; i < source.length; i++) {
      if (source[i] == char) count++;
    }
    return count;
  }

  bool _isFormatActive(String wrapper) {
    final controller = widget.controller;
    if (controller is MarkdownRichTextController) {
      if (wrapper == '**') return controller.isBoldActive;
      if (wrapper == '*') return controller.isItalicActive;
      if (wrapper == '_') return controller.isUnderlineActive;
    }

    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return false;
    int start = sel.start;
    int end = sel.end;

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
      }
    }

    const formatChars = {'*', '_', '~'};
    int leftFormatStart = start;
    while (leftFormatStart > 0 && formatChars.contains(text[leftFormatStart - 1])) {
      leftFormatStart--;
    }
    final leftFormats = text.substring(leftFormatStart, start);

    int rightFormatEnd = end;
    while (rightFormatEnd < text.length && formatChars.contains(text[rightFormatEnd])) {
      rightFormatEnd++;
    }
    final rightFormats = text.substring(end, rightFormatEnd);

    return _hasFormat(leftFormats, rightFormats, wrapper);
  }

  Widget _buildMarkdownToolbar(bool isDark) {
    final controller = widget.controller;
    final text = controller.text;
    final sel = controller.selection;
    final isBold = controller is MarkdownRichTextController ? controller.isBoldActive : _isFormatActive('**');
    final isItalic = controller is MarkdownRichTextController ? controller.isItalicActive : _isFormatActive('*');
    final isUnderline = controller is MarkdownRichTextController ? controller.isUnderlineActive : _isFormatActive('_');

    bool isList = false;
    if (sel.isValid) {
      if (sel.isCollapsed) {
        int lineStart = sel.start;
        while (lineStart > 0 && text[lineStart - 1] != '\n') {
          lineStart--;
        }
        if (lineStart + 2 <= text.length && text.substring(lineStart, lineStart + 2) == '- ') {
          isList = true;
        }
      } else {
        final selectedText = sel.textInside(text);
        if (selectedText.startsWith('- ')) {
          isList = true;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF25252A) : OhtliColors.cantera.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolbarButton(
            icon: Icons.format_bold_rounded,
            tooltip: 'Negrita (Ctrl+B)',
            isActive: isBold,
            onTap: () => _injectMarkdown('**'),
            isDark: isDark,
          ),
          _buildToolbarButton(
            icon: Icons.format_italic_rounded,
            tooltip: 'Cursiva (Ctrl+I)',
            isActive: isItalic,
            onTap: () => _injectMarkdown('*'),
            isDark: isDark,
          ),
          _buildToolbarButton(
            icon: Icons.format_underlined_rounded,
            tooltip: 'Subrayado (Ctrl+U)',
            isActive: isUnderline,
            onTap: () => _injectMarkdown('_'),
            isDark: isDark,
          ),
          _buildToolbarButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: 'Lista (-)',
            isActive: isList,
            onTap: () => _injectMarkdown('- '),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
    bool isActive = false,
    Color? activeColor,
  }) {
    final Color actualActiveColor = activeColor ?? OhtliColors.cempasuchil;
    final Color inactiveColor = isDark ? OhtliColors.onyx.withValues(alpha: 0.7) : OhtliColors.stormyTeal;

    return Tooltip(
      message: tooltip,
      textStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white),
      child: Container(
        decoration: BoxDecoration(
          color: isActive 
              ? (isDark ? actualActiveColor.withValues(alpha: 0.15) : actualActiveColor.withValues(alpha: 0.1)) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
          icon: Icon(
            icon, 
            size: 16, 
            color: isActive ? actualActiveColor : inactiveColor,
          ),
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = OhtliSettings.instance.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF25252A) 
            : OhtliColors.cantera.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused
              ? OhtliColors.stormyTeal
              : (isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.15)),
          width: _isFocused ? 1.5 : 1,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMarkdownToolbar(isDark),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '$_wordCount palabras  |  $_charCount caracteres',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: OhtliColors.onyx.withValues(alpha: 0.35),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              controller: widget.controller,
              focusNode: _focusNode,
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: OhtliColors.onyx,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: GoogleFonts.inter(color: OhtliColors.onyx.withValues(alpha: 0.3)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
