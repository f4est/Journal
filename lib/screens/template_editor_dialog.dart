// Диалог редактирования шаблона
import 'package:flutter/material.dart';
import '../models/template_models.dart';

class TemplateEditorDialog extends StatefulWidget {
  final Template? template;
  final TextEditingController nameController;
  final TextEditingController descController;
  final List<ColumnDefinition> columns;
  final Function(String name, String description, List<ColumnDefinition> columns) onSave;

  const TemplateEditorDialog({
    super.key,
    required this.template,
    required this.nameController,
    required this.descController,
    required this.columns,
    required this.onSave,
  });

  @override
  State<TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<TemplateEditorDialog> {
  late List<ColumnDefinition> _columns;

  @override
  void initState() {
    super.initState();
    _columns = List.from(widget.columns);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              widget.template == null ? 'Создать шаблон' : 'Редактировать шаблон',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.nameController,
              decoration: const InputDecoration(
                labelText: 'Название шаблона',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: widget.descController,
              decoration: const InputDecoration(
                labelText: 'Описание',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Столбцы',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addColumn,
                  tooltip: 'Добавить столбец',
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _columns.length,
                itemBuilder: (context, index) {
                  final col = _columns[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(col.title),
                      subtitle: Text('${col.type}${col.formula != null ? ': ${col.formula}' : ''}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editColumn(index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                            onPressed: () => _deleteColumn(index),
                          ),
                        ],
                      ),
                      onTap: () => _editColumn(index),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveTemplate,
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addColumn() {
    _editColumn(-1);
  }

  void _editColumn(int index) {
    final col = index >= 0 ? _columns[index] : null;
    final fieldController = TextEditingController(text: col?.field ?? '');
    final titleController = TextEditingController(text: col?.title ?? '');
    final formulaController = TextEditingController(text: col?.formula ?? '');
    final formatController = TextEditingController(text: col?.format ?? '');
    String type = col?.type ?? 'number';
    bool readOnly = col?.readOnly ?? false;
    bool frozen = col?.frozen ?? false;
    double width = col?.width ?? 80.0;
    int order = col?.order ?? _columns.length;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index >= 0 ? 'Редактировать столбец' : 'Добавить столбец'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fieldController,
                  decoration: const InputDecoration(
                    labelText: 'Поле (field)',
                    hintText: 'например: ro_value',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    hintText: 'например: РО',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Тип',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Текст')),
                    DropdownMenuItem(value: 'number', child: Text('Число')),
                    DropdownMenuItem(value: 'calculated', child: Text('Вычисляемое')),
                  ],
                  onChanged: (value) => setDialogState(() => type = value!),
                ),
                if (type == 'calculated') ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: const Text('Доступные переменные и функции'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildVariableHelp('Переменные:', [
                              'student_name - имя студента',
                              'dates_count - количество дат',
                              'grades_count - количество оценок',
                              'grades_sum - сумма числовых оценок',
                              'grades_avg - среднее оценок',
                              'count_n - количество "Н"',
                              'otrabotka - отработка',
                              'exam - экзамен',
                              'include_exam - включен ли экзамен (1/0)',
                              'lab_sum - сумма лаб-оценок',
                              'lab_count - количество лаб-даты',
                            ]),
                            const SizedBox(height: 8),
                            _buildVariableHelp('Функции:', [
                              'SUM(grades) - сумма всех оценок',
                              'AVG(grades) - среднее оценок',
                              'COUNT(grades) - количество оценок',
                              'COUNT(dates) - количество дат',
                              'COUNT_N() - количество "Н"',
                            ]),
                            const SizedBox(height: 8),
                            _buildVariableHelp('Примеры формул:', [
                              'grades_sum / dates_count',
                              'SUM(grades) / COUNT(dates)',
                              'grades_avg * 0.6 + exam * 0.4',
                              '(grades_sum + lab_sum) / (dates_count + lab_count)',
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: formulaController,
                    decoration: const InputDecoration(
                      labelText: 'Формула',
                      hintText: 'например: grades_sum / dates_count',
                      border: OutlineInputBorder(),
                      helperText: 'Используйте переменные и функции из списка выше',
                    ),
                    maxLines: 3,
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: formatController,
                  decoration: const InputDecoration(
                    labelText: 'Формат (опционально)',
                    hintText: '0.1, 0.2, 0',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Только чтение'),
                  value: readOnly,
                  onChanged: (value) => setDialogState(() => readOnly = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Закреплён'),
                  value: frozen,
                  onChanged: (value) => setDialogState(() => frozen = value ?? false),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Ширина',
                    border: const OutlineInputBorder(),
                    suffixText: width.toStringAsFixed(0),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final w = double.tryParse(value);
                    if (w != null) setDialogState(() => width = w);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Порядок',
                    border: const OutlineInputBorder(),
                    suffixText: order.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final o = int.tryParse(value);
                    if (o != null) setDialogState(() => order = o);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                if (fieldController.text.isEmpty || titleController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Заполните поле и название')),
                  );
                  return;
                }

                final newCol = ColumnDefinition(
                  field: fieldController.text.trim(),
                  title: titleController.text.trim(),
                  type: type,
                  formula: type == 'calculated' && formulaController.text.isNotEmpty
                      ? formulaController.text.trim()
                      : null,
                  readOnly: readOnly,
                  frozen: frozen,
                  width: width,
                  format: formatController.text.isNotEmpty ? formatController.text.trim() : null,
                  order: order,
                );

                setState(() {
                  if (index >= 0) {
                    _columns[index] = newCol;
                  } else {
                    _columns.add(newCol);
                  }
                });

                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteColumn(int index) {
    setState(() {
      _columns.removeAt(index);
    });
  }

  void _saveTemplate() {
    if (widget.nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название шаблона')),
      );
      return;
    }

    widget.onSave(
      widget.nameController.text.trim(),
      widget.descController.text.trim(),
      _columns,
    );
  }
  
  Widget _buildVariableHelp(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 2.0),
          child: Text(
            '• $item',
            style: const TextStyle(fontSize: 11),
          ),
        )),
      ],
    );
  }
}

