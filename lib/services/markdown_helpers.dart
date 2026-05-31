enum AlertType { note, warning, tip }

class AlertData {
  final AlertType type;
  final String content;

  AlertData({required this.type, required this.content});
}

AlertData? parseAlertMarkdown(String markdown) {
  final trimmed = markdown.trim();
  if (!trimmed.startsWith('> [!')) return null;

  AlertType type = AlertType.note;
  if (trimmed.contains('[!WARNING]')) {
    type = AlertType.warning;
  } else if (trimmed.contains('[!TIP]')) {
    type = AlertType.tip;
  }

  final lines = markdown.split('\n');
  final List<String> contentLines = [];
  for (var line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith('> [!')) continue;
    if (trimmedLine.startsWith('>')) {
      var contentLine = trimmedLine.substring(1);
      if (contentLine.startsWith(' ')) {
        contentLine = contentLine.substring(1);
      }
      contentLines.add(contentLine);
    } else if (trimmedLine.isNotEmpty) {
      contentLines.add(trimmedLine);
    }
  }

  return AlertData(
    type: type,
    content: contentLines.join('\n').trim(),
  );
}

String serializeAlertMarkdown(AlertType type, String content) {
  final String typeStr = type == AlertType.warning 
      ? 'WARNING' 
      : (type == AlertType.tip ? 'TIP' : 'NOTE');
  
  final lines = content.split('\n');
  final buffer = StringBuffer();
  buffer.writeln('> [!$typeStr]');
  for (var line in lines) {
    buffer.writeln('> $line');
  }
  return buffer.toString().trim();
}

class TableColumn {
  final String name;
  final String type; // 'text', 'number', or 'money'
  final String currency; // 'MXN', 'USD', etc.
  final bool isTotalEnabled;

  TableColumn({
    required this.name,
    this.type = 'text',
    this.currency = 'MXN',
    this.isTotalEnabled = false,
  });
}

class TableData {
  final List<TableColumn> columns;
  final List<List<String>> rows;

  TableData({required this.columns, required this.rows});
}

TableData? parseTableMarkdown(String markdown) {
  final lines = markdown.trim().split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.length < 2) return null;

  if (!lines[0].startsWith('|') || !lines[0].endsWith('|')) return null;
  if (!lines[1].startsWith('|') || !lines[1].endsWith('|')) return null;
  if (!lines[1].contains('---') && !lines[1].contains('-')) return null;

  List<String> splitRow(String row) {
    final parts = row.split('|');
    if (parts.length > 2) {
      final sub = parts.sublist(1, parts.length - 1);
      return sub.map((s) => s.trim()).toList();
    }
    return [];
  }

  final headers = splitRow(lines[0]);
  if (headers.isEmpty) return null;

  final List<TableColumn> columns = headers.map((h) {
    final moneyReg = RegExp(r'^(.*?)\s*\[money:([^:\]]+)(?::(total|sum))?\]$', caseSensitive: false);
    final textReg = RegExp(r'^(.*?)\s*\[text\]$', caseSensitive: false);
    final numberReg = RegExp(r'^(.*?)\s*\[number\]$', caseSensitive: false);
    
    if (moneyReg.hasMatch(h)) {
      final match = moneyReg.firstMatch(h)!;
      final bool isTotal = match.group(3) != null;
      return TableColumn(
        name: match.group(1)!.trim(),
        type: 'money',
        currency: match.group(2)!.toUpperCase(),
        isTotalEnabled: isTotal,
      );
    } else if (numberReg.hasMatch(h)) {
      final match = numberReg.firstMatch(h)!;
      return TableColumn(
        name: match.group(1)!.trim(),
        type: 'number',
      );
    } else if (textReg.hasMatch(h)) {
      final match = textReg.firstMatch(h)!;
      return TableColumn(
        name: match.group(1)!.trim(),
        type: 'text',
      );
    } else {
      return TableColumn(name: h.trim(), type: 'text');
    }
  }).toList();

  final List<List<String>> rows = [];
  for (int i = 2; i < lines.length; i++) {
    if (lines[i].startsWith('|') && lines[i].endsWith('|')) {
      final rowParts = splitRow(lines[i]);
      while (rowParts.length < columns.length) {
        rowParts.add('');
      }
      rows.add(rowParts.sublist(0, columns.length));
    }
  }

  return TableData(columns: columns, rows: rows);
}

String serializeTableMarkdown(TableData table) {
  final buffer = StringBuffer();
  
  buffer.write('| ');
  final headerStrings = table.columns.map((col) {
    if (col.type == 'money') {
      if (col.isTotalEnabled) {
        return '${col.name} [money:${col.currency}:total]';
      }
      return '${col.name} [money:${col.currency}]';
    } else if (col.type == 'number') {
      return '${col.name} [number]';
    } else {
      return '${col.name} [text]';
    }
  }).toList();
  buffer.write(headerStrings.join(' | '));
  buffer.writeln(' |');
  
  buffer.write('|');
  for (int i = 0; i < table.columns.length; i++) {
    buffer.write('---|');
  }
  buffer.writeln();
  
  for (final row in table.rows) {
    buffer.write('| ');
    buffer.write(row.join(' | '));
    buffer.writeln(' |');
  }
  
  return buffer.toString().trim();
}
