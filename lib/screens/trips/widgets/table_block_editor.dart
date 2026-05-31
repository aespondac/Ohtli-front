import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/colors.dart';
import '../../../services/markdown_helpers.dart';

class OhtliTableBlockEditor extends StatefulWidget {
  final String tableMarkdown;
  final Function(String) onChanged;
  final bool isDark;

  const OhtliTableBlockEditor({
    super.key,
    required this.tableMarkdown,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<OhtliTableBlockEditor> createState() => _OhtliTableBlockEditorState();
}

class _OhtliTableBlockEditorState extends State<OhtliTableBlockEditor> {
  late TableData _tableData;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _parseInitialTable();
  }

  @override
  void didUpdateWidget(OhtliTableBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableMarkdown != widget.tableMarkdown) {
      _parseInitialTable();
    }
  }

  void _parseInitialTable() {
    final parsed = parseTableMarkdown(widget.tableMarkdown);
    if (parsed != null) {
      _tableData = parsed;
    } else {
      _tableData = TableData(
        columns: [TableColumn(name: 'Columna 1', type: 'text'), TableColumn(name: 'Columna 2', type: 'text')],
        rows: [['', '']],
      );
    }
  }

  @override
  void dispose() {
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  TextEditingController _getCellController(String key, String initialText) {
    return _controllers.putIfAbsent(key, () {
      final c = TextEditingController(text: initialText);
      c.addListener(_handleCellChanged);
      return c;
    });
  }

  FocusNode _getFocusNode(String key) {
    return _focusNodes.putIfAbsent(key, () => FocusNode());
  }

  void _handleCellChanged() {
    _triggerUpdate();
  }

  void _triggerUpdate() {
    final List<TableColumn> currentColumns = [];
    for (int c = 0; c < _tableData.columns.length; c++) {
      final ctrl = _controllers['h_$c'];
      final col = _tableData.columns[c];
      currentColumns.add(TableColumn(
        name: ctrl?.text ?? col.name,
        type: col.type,
        currency: col.currency,
        isTotalEnabled: col.isTotalEnabled,
      ));
    }

    final List<List<String>> currentRows = [];
    for (int r = 0; r < _tableData.rows.length; r++) {
      final List<String> rowCells = [];
      for (int c = 0; c < _tableData.columns.length; c++) {
        final ctrl = _controllers['cell_${r}_$c'];
        rowCells.add(ctrl?.text ?? _tableData.rows[r][c]);
      }
      currentRows.add(rowCells);
    }

    final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
    widget.onChanged(newMarkdown);
  }

  void _updateColumnType(int colIdx, String newType, String newCurrency, {bool? isTotalEnabled}) {
    final List<TableColumn> currentColumns = [];
    for (int c = 0; c < _tableData.columns.length; c++) {
      final ctrl = _controllers['h_$c'];
      final col = _tableData.columns[c];
      if (c == colIdx) {
        currentColumns.add(TableColumn(
          name: ctrl?.text ?? col.name,
          type: newType,
          currency: newCurrency,
          isTotalEnabled: isTotalEnabled ?? col.isTotalEnabled,
        ));
      } else {
        currentColumns.add(TableColumn(
          name: ctrl?.text ?? col.name,
          type: col.type,
          currency: col.currency,
          isTotalEnabled: col.isTotalEnabled,
        ));
      }
    }

    final List<List<String>> currentRows = [];
    for (int r = 0; r < _tableData.rows.length; r++) {
      final List<String> rowCells = [];
      for (int c = 0; c < _tableData.columns.length; c++) {
        final ctrl = _controllers['cell_${r}_$c'];
        rowCells.add(ctrl?.text ?? _tableData.rows[r][c]);
      }
      currentRows.add(rowCells);
    }

    _clearControllersAndFocusNodes();

    final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
    widget.onChanged(newMarkdown);
    setState(() {
      _tableData = TableData(columns: currentColumns, rows: currentRows);
    });
  }

  void _clearControllersAndFocusNodes() {
    for (var ctrl in _controllers.values) {
      ctrl.dispose();
    }
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  void _addColumn() {
    final List<TableColumn> currentColumns = [];
    for (int c = 0; c < _tableData.columns.length; c++) {
      final ctrl = _controllers['h_$c'];
      final col = _tableData.columns[c];
      currentColumns.add(TableColumn(
        name: ctrl?.text ?? col.name,
        type: col.type,
        currency: col.currency,
        isTotalEnabled: col.isTotalEnabled,
      ));
    }
    currentColumns.add(TableColumn(name: 'Columna ${currentColumns.length + 1}', type: 'text'));

    final List<List<String>> currentRows = [];
    for (int r = 0; r < _tableData.rows.length; r++) {
      final List<String> rowCells = [];
      for (int c = 0; c < _tableData.columns.length; c++) {
        final ctrl = _controllers['cell_${r}_$c'];
        rowCells.add(ctrl?.text ?? _tableData.rows[r][c]);
      }
      rowCells.add('');
      currentRows.add(rowCells);
    }

    _clearControllersAndFocusNodes();

    final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
    widget.onChanged(newMarkdown);
    setState(() {
      _tableData = TableData(columns: currentColumns, rows: currentRows);
    });
  }

  void _deleteColumn(int colIdx) {
    if (_tableData.columns.length <= 1) return;
    final List<TableColumn> currentColumns = [];
    for (int c = 0; c < _tableData.columns.length; c++) {
      final ctrl = _controllers['h_$c'];
      final col = _tableData.columns[c];
      currentColumns.add(TableColumn(
        name: ctrl?.text ?? col.name,
        type: col.type,
        currency: col.currency,
        isTotalEnabled: col.isTotalEnabled,
      ));
    }
    currentColumns.removeAt(colIdx);

    final List<List<String>> currentRows = [];
    for (int r = 0; r < _tableData.rows.length; r++) {
      final List<String> rowCells = [];
      for (int c = 0; c < _tableData.columns.length; c++) {
        final ctrl = _controllers['cell_${r}_$c'];
        rowCells.add(ctrl?.text ?? _tableData.rows[r][c]);
      }
      rowCells.removeAt(colIdx);
      currentRows.add(rowCells);
    }

    _clearControllersAndFocusNodes();

    final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
    widget.onChanged(newMarkdown);
    setState(() {
      _tableData = TableData(columns: currentColumns, rows: currentRows);
    });
  }

  void _addRow() {
    final List<TableColumn> currentColumns = [];
    for (int c = 0; c < _tableData.columns.length; c++) {
      final ctrl = _controllers['h_$c'];
      final col = _tableData.columns[c];
      currentColumns.add(TableColumn(
        name: ctrl?.text ?? col.name,
        type: col.type,
        currency: col.currency,
        isTotalEnabled: col.isTotalEnabled,
      ));
    }

    final List<List<String>> currentRows = [];
    for (int r = 0; r < _tableData.rows.length; r++) {
      final List<String> rowCells = [];
      for (int c = 0; c < _tableData.columns.length; c++) {
        final ctrl = _controllers['cell_${r}_$c'];
        rowCells.add(ctrl?.text ?? _tableData.rows[r][c]);
      }
      currentRows.add(rowCells);
    }
    currentRows.add(List<String>.filled(_tableData.columns.length, ''));

    _clearControllersAndFocusNodes();

    final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
    widget.onChanged(newMarkdown);
    setState(() {
      _tableData = TableData(columns: currentColumns, rows: currentRows);
    });
  }

  void _deleteRow(int rowIdx) {
    final List<TableColumn> currentColumns = [];
    for (int c = 0; c < _tableData.columns.length; c++) {
      final ctrl = _controllers['h_$c'];
      final col = _tableData.columns[c];
      currentColumns.add(TableColumn(
        name: ctrl?.text ?? col.name,
        type: col.type,
        currency: col.currency,
        isTotalEnabled: col.isTotalEnabled,
      ));
    }

    final List<List<String>> currentRows = [];
    for (int r = 0; r < _tableData.rows.length; r++) {
      final List<String> rowCells = [];
      for (int c = 0; c < _tableData.columns.length; c++) {
        final ctrl = _controllers['cell_${r}_$c'];
        rowCells.add(ctrl?.text ?? _tableData.rows[r][c]);
      }
      currentRows.add(rowCells);
    }
    if (rowIdx < currentRows.length) {
      currentRows.removeAt(rowIdx);
    }

    _clearControllersAndFocusNodes();

    final newMarkdown = serializeTableMarkdown(TableData(columns: currentColumns, rows: currentRows));
    widget.onChanged(newMarkdown);
    setState(() {
      _tableData = TableData(columns: currentColumns, rows: currentRows);
    });
  }

  double _calculateTotal(int colIdx) {
    double total = 0.0;
    for (int r = 0; r < _tableData.rows.length; r++) {
      final ctrl = _controllers['cell_${r}_$colIdx'];
      final valStr = ctrl?.text ?? _tableData.rows[r][colIdx];
      final cleanStr = valStr.replaceAll(RegExp(r'[^\d.-]'), '');
      final double? val = double.tryParse(cleanStr);
      if (val != null) {
        total += val;
      }
    }
    return total;
  }

  void _injectMarkdown(TextEditingController controller, String wrapper, {FocusNode? focusNode}) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid) {
      final newText = text + wrapper;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      if (focusNode != null) focusNode.requestFocus();
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
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start + len,
        extentOffset: start + len + selectedText.length,
      ),
    );
    if (focusNode != null) focusNode.requestFocus();
  }

  bool _isWordChar(String char) {
    if (char.isEmpty) return false;
    const exclude = {' ', '\n', '\r', '\t', '*', '_', '~', '.', ',', '!', '?', ';', ':', '(', ')', '[', ']', '{', '}'};
    return !exclude.contains(char);
  }

  @override
  Widget build(BuildContext context) {
    final int numCols = _tableData.columns.length;
    final int numRows = _tableData.rows.length;
    final bool showTotalRow = _tableData.columns.any((col) => col.type == 'money' && col.isTotalEnabled);
    final Color headerBg = widget.isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.2);
    final Color cellBorder = widget.isDark ? const Color(0xFF2C2C32) : OhtliColors.cantera.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column Headers Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(numCols, (colIdx) {
                    final ctrl = _getCellController(
                      'h_$colIdx',
                      _tableData.columns[colIdx].name,
                    );
                    final col = _tableData.columns[colIdx];
                    final bool isMoney = col.type == 'money';

                    return Container(
                      width: 155,
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final fNode = _getFocusNode('h_$colIdx');
                                    return CallbackShortcuts(
                                      bindings: <ShortcutActivator, VoidCallback>{
                                        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                      },
                                      child: TextFormField(
                                        controller: ctrl,
                                        focusNode: fNode,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: OhtliColors.onyx,
                                        ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }
                                ),
                              ),
                              // Type menu selector
                              PopupMenuButton<String>(
                                icon: Icon(
                                  col.type == 'money'
                                      ? Icons.payments_rounded
                                      : col.type == 'number'
                                          ? Icons.tag_rounded
                                          : Icons.text_fields_rounded,
                                  size: 14,
                                  color: OhtliColors.stormyTeal,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (val) {
                                  if (val == 'text') {
                                    _updateColumnType(colIdx, 'text', 'MXN', isTotalEnabled: false);
                                  } else if (val == 'number') {
                                    _updateColumnType(colIdx, 'number', 'MXN', isTotalEnabled: false);
                                  } else {
                                    _updateColumnType(colIdx, 'money', 'MXN');
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'text',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.text_fields_rounded, size: 14),
                                        const SizedBox(width: 8),
                                        Text('📝 Texto', style: GoogleFonts.inter(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'number',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.tag_rounded, size: 14),
                                        const SizedBox(width: 8),
                                        Text('🔢 Número', style: GoogleFonts.inter(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'money',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.payments_rounded, size: 14, color: Colors.amber),
                                        const SizedBox(width: 8),
                                        Text('💵 Dinero', style: GoogleFonts.inter(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (isMoney) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Compact Currency Dropdown
                                Container(
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: widget.isDark ? const Color(0xFF1E1E22) : Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: OhtliColors.stormyTeal.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: col.currency.isNotEmpty ? col.currency : 'MXN',
                                      dropdownColor: widget.isDark ? const Color(0xFF1E1E22) : Colors.white,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: OhtliColors.onyx,
                                      ),
                                      isDense: true,
                                      items: <String>['MXN', 'USD', 'EUR', 'CAD', 'GBP'].map((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          _updateColumnType(colIdx, 'money', val);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                // Sigma Button
                                Tooltip(
                                  message: col.isTotalEnabled ? 'Desactivar total automático' : 'Activar total automático',
                                  child: InkWell(
                                    onTap: () {
                                      _updateColumnType(
                                        colIdx,
                                        'money',
                                        col.currency,
                                        isTotalEnabled: !col.isTotalEnabled,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: col.isTotalEnabled
                                            ? OhtliColors.stormyTeal.withValues(alpha: 0.15)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: col.isTotalEnabled
                                              ? OhtliColors.stormyTeal.withValues(alpha: 0.4)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.functions_rounded,
                                        size: 14,
                                        color: col.isTotalEnabled
                                            ? OhtliColors.stormyTeal
                                            : OhtliColors.stormyTeal.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (numCols > 1)
                            Align(
                              alignment: Alignment.centerRight,
                              child: InkWell(
                                onTap: () => _deleteColumn(colIdx),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: OhtliColors.xoconostle.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: OhtliColors.stormyTeal),
                    onPressed: _addColumn,
                    tooltip: 'Añadir Columna',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Rows
              ...List.generate(numRows, (rowIdx) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      ...List.generate(numCols, (colIdx) {
                        final cellVal = _tableData.rows[rowIdx][colIdx];
                        final ctrl = _getCellController(
                          'cell_${rowIdx}_$colIdx',
                          cellVal,
                        );
                        final col = _tableData.columns[colIdx];
                        final bool isMoney = col.type == 'money';
                        final bool isNumber = col.type == 'number';

                        return Container(
                          width: 155,
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cellBorder),
                          ),
                          child: Builder(
                            builder: (context) {
                              final fNode = _getFocusNode('cell_${rowIdx}_$colIdx');
                              return CallbackShortcuts(
                                bindings: <ShortcutActivator, VoidCallback>{
                                  const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _injectMarkdown(ctrl, '**', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _injectMarkdown(ctrl, '*', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                  const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _injectMarkdown(ctrl, '_', focusNode: fNode),
                                },
                                child: TextFormField(
                                  controller: ctrl,
                                  focusNode: fNode,
                                  style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx),
                                  keyboardType: (isMoney || isNumber)
                                      ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                                      : TextInputType.text,
                                  inputFormatters: (isMoney || isNumber)
                                      ? [
                                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                                        ]
                                      : null,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                    prefixText: isMoney ? '\$ ' : null,
                                    suffixText: isMoney ? col.currency : null,
                                    suffixStyle: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: OhtliColors.onyx.withValues(alpha: 0.5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }
                          ),
                        );
                      }),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: OhtliColors.xoconostle),
                        onPressed: () => _deleteRow(rowIdx),
                        tooltip: 'Eliminar Fila',
                      ),
                    ],
                  ),
                );
              }),
              if (showTotalRow)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(
                    children: [
                      ...List.generate(numCols, (colIdx) {
                        final col = _tableData.columns[colIdx];
                        final bool isMoneyTotal = col.type == 'money' && col.isTotalEnabled;

                        return Container(
                          width: 155,
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isMoneyTotal
                                ? (widget.isDark ? const Color(0xFF2C2C32) : OhtliColors.stormyTeal.withValues(alpha: 0.05))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isMoneyTotal
                                ? Border(
                                    top: BorderSide(
                                      color: OhtliColors.stormyTeal,
                                      width: 1.5,
                                      style: BorderStyle.solid,
                                    ),
                                    bottom: BorderSide(
                                      color: OhtliColors.stormyTeal,
                                      width: 1.5,
                                      style: BorderStyle.solid,
                                    ),
                                  )
                                : null,
                          ),
                          child: isMoneyTotal
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total:',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: OhtliColors.stormyTeal,
                                      ),
                                    ),
                                    Text(
                                      '\$ ${_calculateTotal(colIdx).toStringAsFixed(2)} ${col.currency}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: OhtliColors.onyx,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox(),
                        );
                      }),
                      const SizedBox(width: 48), // align with row delete icon
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(
            'Añadir Fila',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: OhtliColors.stormyTeal.withValues(alpha: 0.1),
            foregroundColor: OhtliColors.stormyTeal,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: OhtliColors.stormyTeal.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }
}
