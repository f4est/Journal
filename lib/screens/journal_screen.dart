// Главный экран электронного журнала с PlutoGrid
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../models/journal_models.dart';
import '../services/journal_service.dart';
import '../utils/pluto_localization.dart';
import '../utils/grade_colors.dart';
import 'journal_date_picker.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState(); 
}

class _JournalScreenState extends State<JournalScreen> {
  final JournalService _service = JournalService();
  
  bool _isInitialized = false;
  Group? _currentGroup;
  List<Student> _students = [];
  List<LessonDate> _dates = [];
  bool _includeExam = true;
  bool _includeLabs = false;
  bool _includeTheory = true;
  String _searchQuery = '';
  
  // Debounce для поиска
  Timer? _searchDebounce;
  
  // Кэш для оптимизации
  final Map<String, List<Student>> _studentsCache = {};
  final Map<String, List<LessonDate>> _datesCache = {};
  final Map<String, Map<String, List<Grade>>> _gradesCache = {};

  final List<PlutoColumn> _columns = [];
  List<PlutoRow> _rows = [];
  
  // Данные для лаб-таблицы
  final List<PlutoColumn> _labColumns = [];
  List<PlutoRow> _labRows = [];
  Group? _labGroup;
  
  // Соотношение размеров между основной и лаб-таблицей (по умолчанию 2:1)
  double _tableFlexRatio = 0.67; // 0.67 = 2/3 для основной таблицы
  
  // StateManager для основной и лаб-таблиц
  PlutoGridStateManager? _stateManager;
  PlutoGridStateManager? _labStateManager;
  
  // Версия для форс перерендера таблиц
  int _gridVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
  
  void _invalidateCache() {
    _studentsCache.clear();
    _datesCache.clear();
    _gradesCache.clear();
  }

  Future<void> _loadData() async {
    await _service.init();
    setState(() {
      _isInitialized = true;
      final groups = _service.getAllGroups().where((g) => !g.name.endsWith('_Лаб')).toList();
      if (groups.isNotEmpty) {
        // Если текущая группа существует, находим её по groupId
        if (_currentGroup != null && !_currentGroup!.name.endsWith('_Лаб')) {
          try {
            _currentGroup = groups.firstWhere((g) => g.groupId == _currentGroup!.groupId);
          } catch (e) {
            _currentGroup = groups.first;
          }
        } else {
          _currentGroup = groups.first;
        }
      } else {
        _currentGroup = null;
      }
    });
    _refreshTable();
  }

  void _refreshTable() {
    if (_currentGroup == null) {
      setState(() {
        _columns.clear();
        _rows.clear();
        _labColumns.clear();
        _labRows.clear();
        _labGroup = null;
      });
      return;
    }

    // Если выбрана лаб-группа, показываем только лаб-таблицу
    if (_currentGroup!.isLabGroup) {
      _refreshLabTable();
      return;
    }

    // Инвалидируем кэш для получения актуальных данных
    final cacheKey = _currentGroup!.groupId;
    _studentsCache.remove(cacheKey);
    _datesCache.remove(cacheKey);
    _gradesCache.remove(cacheKey);
    
    // Получаем актуальные данные напрямую из базы
    final allStudents = _service.getStudentsByGroup(_currentGroup!);
    final allDates = _service.getDatesByGroup(_currentGroup!);
    allDates.sort((a, b) => a.date.compareTo(b.date));
    
    // Фильтрация по поиску (подстрока, с обрезкой пробелов)
    final searchQueryTrimmed = _searchQuery.trim();
    final filteredStudents = searchQueryTrimmed.isNotEmpty
        ? allStudents.where((s) => 
            s.name.toLowerCase().contains(searchQueryTrimmed.toLowerCase())
          ).toList()
        : allStudents;

    // Обновляем состояние один раз
    setState(() {
      _includeExam = _currentGroup!.includeExam;
      _includeLabs = _currentGroup!.includeLabs;
      _includeTheory = _currentGroup!.includeTheory;
      
      _students = filteredStudents;
      _dates = allDates;
    });

    // Строим колонки и строки после обновления данных
    _buildColumns();
    _buildRows();
    
    // Обновляем лаб-таблицу, если включены лаб-ки
    if (_includeLabs) {
      final labGroupName = '${_currentGroup!.name}_Лаб';
      _labGroup = _service.getGroupByName(labGroupName);
      if (_labGroup != null) {
        _buildLabColumns();
        _buildLabRows();
      }
    } else {
      _labGroup = null;
      _labColumns.clear();
      _labRows.clear();
    }
    
    // Обновляем UI один раз после всех изменений
    if (mounted) {
      setState(() {
        // Принудительно обновляем состояние для перерисовки таблицы
      });
    }
  }
  
  void _refreshLabTable() {
    final allStudents = _service.getStudentsByGroup(_currentGroup!);
    final allDates = _service.getDatesByGroup(_currentGroup!);
    
    final searchQueryTrimmed = _searchQuery.trim();
    final filteredStudents = searchQueryTrimmed.isNotEmpty
        ? allStudents.where((s) => 
            s.name.toLowerCase().contains(searchQueryTrimmed.toLowerCase())
          ).toList()
        : allStudents;

    allDates.sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _students = filteredStudents;
      _dates = allDates;
    });

    _buildLabColumns();
    _buildLabRows();
    
    setState(() {
      _columns.clear();
      _rows.clear();
    });
  }

  void _buildColumns() {
    // Определяем тему для использования в рендерере
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    _columns.clear();
    _columns.add(
      PlutoColumn(
        title: 'Студент',
        field: 'student',
        type: PlutoColumnType.text(),
        width: 150,
        frozen: PlutoColumnFrozen.start,
      ),
    );

    // Добавляем столбцы дат с кастомным рендерером для цветовой раскраски
    for (var i = 0; i < _dates.length; i++) {
      final date = _dates[i];
      _columns.add(
        PlutoColumn(
          title: date.label,
          field: 'date_$i',
          type: PlutoColumnType.text(),
          width: 80,
          readOnly: false,
          renderer: (rendererContext) {
            final cellValue = rendererContext.cell.value?.toString() ?? '';
            final gradeColor = getGradeColor(cellValue, isDark: isDark);
            return Container(
              color: gradeColor,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              child: Text(
                cellValue,
                style: TextStyle(
                  fontSize: 12,
                  color: gradeColor != null && !isDark 
                      ? Colors.black87 // Темный текст для светлых цветов
                      : null,
                  fontWeight: gradeColor != null && !isDark 
                      ? FontWeight.w600 // Жирнее для читаемости
                      : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      );
    }

    // Добавляем спецстолбцы (закреплены в конце, не редактируемые, кроме Отработка)
    _columns.addAll([
      PlutoColumn(
        title: 'Н',
        field: 'letter_count',
        type: PlutoColumnType.number(),
        width: 50,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'РО',
        field: 'ro_value',
        type: PlutoColumnType.text(),
        width: 70,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Отработка',
        field: 'otrabotka',
        type: PlutoColumnType.number(),
        width: 90,
        readOnly: false, // Можно редактировать
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Р',
        field: 'r_value',
        type: PlutoColumnType.text(),
        width: 70,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
    ]);

    if (_includeExam) {
      _columns.add(
        PlutoColumn(
          title: 'Экзам',
          field: 'exam',
          type: PlutoColumnType.number(),
          width: 70,
          readOnly: false, // Редактируемый только когда включен экзамен
          frozen: PlutoColumnFrozen.end,
        ),
      );
    }

    _columns.addAll([
      PlutoColumn(
        title: 'Итог',
        field: 'itog_value',
        type: PlutoColumnType.text(),
        width: 70,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Бук. экв.',
        field: 'letter_eq',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Циф. экв.',
        field: 'digital_eq',
        type: PlutoColumnType.text(),
        width: 90,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
    ]);
  }

  void _buildRows() {
    if (_currentGroup == null) return;
    
    final cacheKey = _currentGroup!.groupId;
    final gradesCacheForGroup = _gradesCache.putIfAbsent(cacheKey, () => <String, List<Grade>>{});
    
    // Получаем актуальные данные студентов после пересчета (инвалидируем кэш если нужно)
    final freshStudents = _service.getStudentsByGroup(_currentGroup!);
    final studentMap = <String, Student>{};
    for (final s in freshStudents) {
      studentMap[s.name] = s;
    }
    
    _rows = _students.map((student) {
      // Используем свежие данные если есть, иначе используем кэшированные
      final freshStudent = studentMap[student.name] ?? student;
      
      final cells = <String, PlutoCell>{};
      
      cells['student'] = PlutoCell(value: freshStudent.name);

      // Заполняем оценки по датам с кэшированием
      List<Grade> grades;
      if (gradesCacheForGroup.containsKey(freshStudent.name)) {
        grades = gradesCacheForGroup[freshStudent.name]!;
      } else {
        grades = _service.getGradesByStudent(freshStudent);
        gradesCacheForGroup[freshStudent.name] = grades;
      }
      
      final gradeMap = <String, String>{};
      for (final g in grades) {
        gradeMap[g.dateId] = g.grade;
      }

      for (var i = 0; i < _dates.length; i++) {
        final dateId = _dates[i].key.toString();
        final gradeValue = gradeMap[dateId] ?? '';
        cells['date_$i'] = PlutoCell(value: gradeValue);
      }

      // Спецстолбцы - используем свежие данные после пересчета
      cells['letter_count'] = PlutoCell(value: freshStudent.letterCount);
      // Форматируем с одной цифрой после запятой
      cells['ro_value'] = PlutoCell(value: freshStudent.roValue.toStringAsFixed(1));
      cells['otrabotka'] = PlutoCell(value: freshStudent.otrabotka);
      cells['r_value'] = PlutoCell(value: freshStudent.rValue.toStringAsFixed(1));
      
      if (_includeExam) {
        cells['exam'] = PlutoCell(value: freshStudent.exam);
      }
      
      cells['itog_value'] = PlutoCell(value: freshStudent.itogValue.toStringAsFixed(1));
      cells['letter_eq'] = PlutoCell(value: freshStudent.letterEq);
      // Форматируем с двумя цифрами после запятой
      cells['digital_eq'] = PlutoCell(value: freshStudent.digitalEq.toStringAsFixed(2));

      return PlutoRow(cells: cells);
    }).toList();
  }
  
  void _buildLabColumns() {
    if (_labGroup == null) return;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labDates = _service.getDatesByGroup(_labGroup!);
    labDates.sort((a, b) => a.date.compareTo(b.date));
    
    _labColumns.clear();
    _labColumns.add(
      PlutoColumn(
        title: 'Студент',
        field: 'student',
        type: PlutoColumnType.text(),
        width: 150,
        frozen: PlutoColumnFrozen.start,
      ),
    );

    // Добавляем столбцы дат с кастомным рендерером для цветовой раскраски
    for (var i = 0; i < labDates.length; i++) {
      final date = labDates[i];
      _labColumns.add(
        PlutoColumn(
          title: date.label,
          field: 'date_$i',
          type: PlutoColumnType.text(),
          width: 80,
          readOnly: false,
          renderer: (rendererContext) {
            final cellValue = rendererContext.cell.value?.toString() ?? '';
            final gradeColor = getGradeColor(cellValue, isDark: isDark);
            return Container(
              color: gradeColor,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              child: Text(
                cellValue,
                style: TextStyle(
                  fontSize: 12,
                  color: gradeColor != null && !isDark 
                      ? Colors.black87 // Темный текст для светлых цветов
                      : null,
                  fontWeight: gradeColor != null && !isDark 
                      ? FontWeight.w600 // Жирнее для читаемости
                      : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      );
    }

    // Спецстолбцы для лаб-таблицы
    _labColumns.addAll([
      PlutoColumn(
        title: 'Н',
        field: 'letter_count',
        type: PlutoColumnType.number(),
        width: 50,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'РО',
        field: 'ro_value',
        type: PlutoColumnType.text(),
        width: 70,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Отработка',
        field: 'otrabotka',
        type: PlutoColumnType.number(),
        width: 90,
        readOnly: false,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Р',
        field: 'r_value',
        type: PlutoColumnType.text(),
        width: 70,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Итог',
        field: 'itog_value',
        type: PlutoColumnType.text(),
        width: 70,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Бук. экв.',
        field: 'letter_eq',
        type: PlutoColumnType.text(),
        width: 80,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
      PlutoColumn(
        title: 'Циф. экв.',
        field: 'digital_eq',
        type: PlutoColumnType.text(),
        width: 90,
        readOnly: true,
        frozen: PlutoColumnFrozen.end,
      ),
    ]);
  }
  
  void _buildLabRows() {
    if (_labGroup == null) return;
    
    final labStudents = _service.getStudentsByGroup(_labGroup!);
    final labDates = _service.getDatesByGroup(_labGroup!);
    labDates.sort((a, b) => a.date.compareTo(b.date));
    
    // Фильтрация по поиску
    final searchQueryTrimmed = _searchQuery.trim();
    final filteredLabStudents = searchQueryTrimmed.isNotEmpty
        ? labStudents.where((s) => 
            s.name.toLowerCase().contains(searchQueryTrimmed.toLowerCase())
          ).toList()
        : labStudents;
    
    _labRows = filteredLabStudents.map((student) {
      final cells = <String, PlutoCell>{};
      
      cells['student'] = PlutoCell(value: student.name);

      // Заполняем оценки по датам
      final grades = _service.getGradesByStudent(student);
      final gradeMap = <String, String>{};
      for (final g in grades) {
        gradeMap[g.dateId] = g.grade;
      }

      for (var i = 0; i < labDates.length; i++) {
        final dateId = labDates[i].key.toString();
        final gradeValue = gradeMap[dateId] ?? '';
        cells['date_$i'] = PlutoCell(value: gradeValue);
      }

      // Спецстолбцы
      cells['letter_count'] = PlutoCell(value: student.letterCount);
      // Форматируем с одной цифрой после запятой
      cells['ro_value'] = PlutoCell(value: student.roValue.toStringAsFixed(1));
      cells['otrabotka'] = PlutoCell(value: student.otrabotka);
      cells['r_value'] = PlutoCell(value: student.rValue.toStringAsFixed(1));
      cells['itog_value'] = PlutoCell(value: student.itogValue.toStringAsFixed(1));
      cells['letter_eq'] = PlutoCell(value: student.letterEq);
      // Форматируем с двумя цифрами после запятой
      cells['digital_eq'] = PlutoCell(value: student.digitalEq.toStringAsFixed(2));

      return PlutoRow(cells: cells);
    }).toList();
  }
  
  Widget _buildTablesWidget() {
    // Если выбрана лаб-группа, показываем только лаб-таблицу
    if (_currentGroup != null && _currentGroup!.isLabGroup) {
      if (_labColumns.isEmpty && _labRows.isEmpty) {
        return const Center(child: Text('Нет данных для отображения'));
      }
      return PlutoGrid(
        key: ValueKey('lab_${_labGroup?.groupId}_${_labColumns.length}_${_labRows.length}_v$_gridVersion'),
        columns: _labColumns,
        rows: _labRows,
        onChanged: _onLabCellChanged,
        onLoaded: (PlutoGridOnLoadedEvent event) {
          _labStateManager = event.stateManager;
        },
        onRowSecondaryTap: (event) {
          final row = event.row;
          final studentName = row.cells['student']?.value as String?;
          if (studentName != null && _labGroup != null) {
            _showDeleteStudentDialog(studentName);
          }
        },
        configuration: PlutoGridConfiguration(
          localeText: RussianPlutoGridLocalization(),
          columnSize: const PlutoGridColumnSizeConfig(
            autoSizeMode: PlutoAutoSizeMode.none,
          ),
          style: PlutoGridStyleConfig(
            gridBackgroundColor: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[900]! 
                : Colors.white,
            activatedColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.blue.shade800
                : Colors.blue.shade100,
            gridBorderColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[700]!
                : Colors.grey.shade300,
          ),
        ),
      );
    }
    
    // Если теория выключена, показываем сообщение
    if (!_includeTheory && _currentGroup != null && !_currentGroup!.isLabGroup) {
      return const Center(child: Text('Теория выключена'));
    }
    
    // Основная таблица
    final mainTable = _columns.isEmpty && _rows.isEmpty
        ? const Center(child: Text('Нет данных для отображения'))
        : PlutoGrid(
            key: ValueKey('main_${_currentGroup?.groupId}_${_columns.length}_${_rows.length}_v$_gridVersion'),
            columns: _columns,
            rows: _rows,
            onChanged: _onCellChanged,
            onLoaded: (PlutoGridOnLoadedEvent event) {
              _stateManager = event.stateManager;
            },
            onRowSecondaryTap: (event) {
              final row = event.row;
              final studentName = row.cells['student']?.value as String?;
              if (studentName != null) {
                _showDeleteStudentDialog(studentName);
              }
            },
            configuration: PlutoGridConfiguration(
              localeText: RussianPlutoGridLocalization(),
              columnSize: const PlutoGridColumnSizeConfig(
                autoSizeMode: PlutoAutoSizeMode.none,
              ),
              style: PlutoGridStyleConfig(
                gridBackgroundColor: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[900]! 
                    : Colors.white,
                activatedColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue.shade800
                    : Colors.blue.shade100,
                gridBorderColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[700]!
                    : Colors.grey.shade300,
              ),
            ),
          );
    
    // Если включены лаб-ки, показываем две таблицы
    if (_includeLabs && _labGroup != null && _labColumns.isNotEmpty) {
      final mainFlex = (_tableFlexRatio * 100).round();
      final labFlex = ((1 - _tableFlexRatio) * 100).round();
      
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              Expanded(
                flex: mainFlex > 0 ? mainFlex : 2,
                child: mainTable,
              ),
              GestureDetector(
                onPanUpdate: (details) {
                  final totalHeight = constraints.maxHeight;
                  if (totalHeight > 0) {
                    setState(() {
                      final delta = details.delta.dy / totalHeight;
                      _tableFlexRatio = (_tableFlexRatio + delta).clamp(0.1, 0.9);
                    });
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    height: 8,
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[700] 
                        : Colors.grey[400],
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[500] 
                              : Colors.grey[600],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: labFlex > 0 ? labFlex : 1,
                child: PlutoGrid(
                  key: ValueKey('lab_${_labGroup?.groupId}_${_labColumns.length}_${_labRows.length}_v$_gridVersion'),
                  columns: _labColumns,
                  rows: _labRows,
                  onChanged: _onLabCellChanged,
                  onLoaded: (PlutoGridOnLoadedEvent event) {
                    _labStateManager = event.stateManager;
                  },
                  onRowSecondaryTap: (event) {
                    final row = event.row;
                    final studentName = row.cells['student']?.value as String?;
                    if (studentName != null && _labGroup != null) {
                      _showDeleteStudentDialog(studentName);
                    }
                  },
                  configuration: PlutoGridConfiguration(
                    localeText: RussianPlutoGridLocalization(),
                    columnSize: const PlutoGridColumnSizeConfig(
                      autoSizeMode: PlutoAutoSizeMode.none,
                    ),
                    style: PlutoGridStyleConfig(
                      gridBackgroundColor: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[900]! 
                          : Colors.white,
                      activatedColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade800
                          : Colors.blue.shade100,
                      gridBorderColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[700]!
                          : Colors.grey.shade300,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    
    return mainTable;
  }
  
  Widget _buildMobileControls() {
    return Column(
      children: [
        // Выбор группы с кнопкой удаления
        Row(
          children: [
            Expanded(
              child: DropdownButton<Group>(
                value: _currentGroup != null 
                    ? _service.getAllGroups().where((g) => !g.name.endsWith('_Лаб')).firstWhere(
                        (g) => g.groupId == _currentGroup!.groupId,
                        orElse: () => _currentGroup!,
                      )
                    : null,
                hint: const Text('Выберите группу'),
                isExpanded: true,
                items: _service.getAllGroups().where((g) => !g.name.endsWith('_Лаб')).map((group) {
                  return DropdownMenuItem(
                    value: group,
                    child: Text(group.name),
                  );
                }).toList(),
                onChanged: (Group? group) {
                  if (group != null && (_currentGroup == null || group.groupId != _currentGroup!.groupId)) {
                    setState(() {
                      _currentGroup = group;
                    });
                    _invalidateCache(); // Очищаем кэш при смене группы
                    _refreshTable();
                  }
                },
              ),
            ),
            if (_currentGroup != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _showDeleteGroupDialog,
                tooltip: 'Удалить группу',
              ),
          ],
        ),
        const SizedBox(height: 4),
        // Поиск
        TextField(
          decoration: const InputDecoration(
            hintText: 'Поиск студента...',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onChanged: (value) {
            // Debounce для поиска - уменьшаем нагрузку на мобильных
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                setState(() {
                  _searchQuery = value.trim();
                });
                _refreshTable();
              }
            });
          },
        ),
        const SizedBox(height: 4),
        // Чекбоксы в одну строку
        Wrap(
          spacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _includeExam,
                  onChanged: (bool? value) async {
                    if (_currentGroup != null) {
      // Завершаем редактирование перед пересчётом
      _stateManager?.setKeepFocus(false);
      _labStateManager?.setKeepFocus(false);
                      
                      setState(() {
                        _includeExam = value ?? true;
                        _currentGroup!.includeExam = _includeExam;
                      });
                      await _service.updateGroup(_currentGroup!);
                      _invalidateCacheForGroup(_currentGroup!.groupId);
                      await _service.calculateRatings(_currentGroup!);
                      // Если включены лаб-ки, пересчитываем и лаб-группу
                      if (_currentGroup!.includeLabs && !_currentGroup!.isLabGroup) {
                        final labGroupName = '${_currentGroup!.name}_Лаб';
                        final labGroup = _service.getGroupByName(labGroupName);
                        if (labGroup != null) {
                          await _service.calculateRatings(labGroup);
                        }
                      }
                      final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
                      setState(() {
                        _students = updatedStudents;
                        _gridVersion++; // Инкрементируем версию для перерендера
                      });
                      _refreshTable();
                    }
                  },
                ),
                const Text('Экзам', style: TextStyle(fontSize: 12)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _includeLabs,
                  onChanged: (bool? value) async {
                    if (_currentGroup != null && !_currentGroup!.isLabGroup) {
      // Завершаем редактирование перед пересчётом
      _stateManager?.setKeepFocus(false);
      _labStateManager?.setKeepFocus(false);
                      
                      setState(() {
                        _includeLabs = value ?? false;
                        _currentGroup!.includeLabs = _includeLabs;
                      });
                      await _service.updateGroup(_currentGroup!);
                      _invalidateCacheForGroup(_currentGroup!.groupId);
                      await _service.calculateRatings(_currentGroup!);
                      // Если включены лаб-ки, пересчитываем и лаб-группу
                      if (_includeLabs) {
                        final labGroupName = '${_currentGroup!.name}_Лаб';
                        final labGroup = _service.getGroupByName(labGroupName);
                        if (labGroup != null) {
                          await _service.calculateRatings(labGroup);
                        }
                      }
                      final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
                      setState(() {
                        _students = updatedStudents;
                        _gridVersion++; // Инкрементируем версию для перерендера
                      });
                      _refreshTable();
                    }
                  },
                ),
                const Text('Лаб-ки', style: TextStyle(fontSize: 12)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _includeTheory,
                  onChanged: (bool? value) async {
                    if (_currentGroup != null && !_currentGroup!.isLabGroup) {
      // Завершаем редактирование перед пересчётом
      _stateManager?.setKeepFocus(false);
      _labStateManager?.setKeepFocus(false);
                      
                      setState(() {
                        _includeTheory = value ?? true;
                        _currentGroup!.includeTheory = _includeTheory;
                      });
                      await _service.updateGroup(_currentGroup!);
                      _invalidateCacheForGroup(_currentGroup!.groupId);
                      await _service.calculateRatings(_currentGroup!);
                      // Если включены лаб-ки, пересчитываем и лаб-группу
                      if (_currentGroup!.includeLabs && !_currentGroup!.isLabGroup) {
                        final labGroupName = '${_currentGroup!.name}_Лаб';
                        final labGroup = _service.getGroupByName(labGroupName);
                        if (labGroup != null) {
                          await _service.calculateRatings(labGroup);
                        }
                      }
                      final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
                      setState(() {
                        _students = updatedStudents;
                        _gridVersion++; // Инкрементируем версию для перерендера
                      });
                      _refreshTable();
                    }
                  },
                ),
                const Text('Теория', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Кнопки управления
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddGroupDialog,
              tooltip: 'Добавить группу',
            ),
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: _showAddStudentDialog,
              tooltip: 'Добавить студентов',
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _showAddDateDialog,
              tooltip: 'Добавить дату',
            ),
            if (_dates.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить дату',
                onSelected: (String dateId) {
                  final date = _dates.firstWhere((d) => d.key.toString() == dateId);
                  _showDeleteDateDialog(date);
                },
                itemBuilder: (BuildContext context) => _dates.map((date) {
                  return PopupMenuItem<String>(
                    value: date.key.toString(),
                    child: Text('Удалить "${date.label}"'),
                  );
                }).toList(),
              ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildDesktopControls() {
    return Row(
      children: [
        // Выбор группы с кнопкой удаления
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<Group>(
                  value: _currentGroup != null 
                      ? _service.getAllGroups().where((g) => !g.name.endsWith('_Лаб')).firstWhere(
                          (g) => g.groupId == _currentGroup!.groupId,
                          orElse: () => _currentGroup!,
                        )
                      : null,
                  hint: const Text('Выберите группу'),
                  isExpanded: true,
                  items: _service.getAllGroups().where((g) => !g.name.endsWith('_Лаб')).map((group) {
                    return DropdownMenuItem(
                      value: group,
                      child: Text(group.name),
                    );
                  }).toList(),
                  onChanged: (Group? group) {
                    if (group != null && (_currentGroup == null || group.groupId != _currentGroup!.groupId)) {
                      setState(() {
                        _currentGroup = group;
                      });
                      _invalidateCache(); // Очищаем кэш при смене группы
                      _refreshTable();
                    }
                  },
                ),
              ),
              if (_currentGroup != null)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _showDeleteGroupDialog,
                  tooltip: 'Удалить группу',
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Чекбоксы
        Checkbox(
          value: _includeExam,
          onChanged: (bool? value) async {
            if (_currentGroup != null) {
              setState(() {
                _includeExam = value ?? true;
                _currentGroup!.includeExam = _includeExam;
              });
              await _service.updateGroup(_currentGroup!);
              _invalidateCacheForGroup(_currentGroup!.groupId);
              await _service.calculateRatings(_currentGroup!);
              // Если включены лаб-ки, пересчитываем и лаб-группу
              if (_currentGroup!.includeLabs && !_currentGroup!.isLabGroup) {
                final labGroupName = '${_currentGroup!.name}_Лаб';
                final labGroup = _service.getGroupByName(labGroupName);
                if (labGroup != null) {
                  await _service.calculateRatings(labGroup);
                }
              }
              final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
              setState(() {
                _students = updatedStudents;
              });
              _refreshTable();
            }
          },
        ),
        const Text('Экзамен'),
        const SizedBox(width: 16),
        Checkbox(
          value: _includeLabs,
          onChanged: (bool? value) async {
            if (_currentGroup != null && !_currentGroup!.isLabGroup) {
              setState(() {
                _includeLabs = value ?? false;
                _currentGroup!.includeLabs = _includeLabs;
              });
              await _service.updateGroup(_currentGroup!);
              _invalidateCacheForGroup(_currentGroup!.groupId);
              await _service.calculateRatings(_currentGroup!);
              // Если включены лаб-ки, пересчитываем и лаб-группу
              if (_includeLabs) {
                final labGroupName = '${_currentGroup!.name}_Лаб';
                final labGroup = _service.getGroupByName(labGroupName);
                if (labGroup != null) {
                  await _service.calculateRatings(labGroup);
                }
              }
              final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
              setState(() {
                _students = updatedStudents;
              });
              _refreshTable();
            }
          },
        ),
        const Text('Лаб-ки'),
        const SizedBox(width: 16),
        Checkbox(
          value: _includeTheory,
          onChanged: (bool? value) async {
            if (_currentGroup != null && !_currentGroup!.isLabGroup) {
              setState(() {
                _includeTheory = value ?? true;
                _currentGroup!.includeTheory = _includeTheory;
              });
              await _service.updateGroup(_currentGroup!);
              _invalidateCacheForGroup(_currentGroup!.groupId);
              await _service.calculateRatings(_currentGroup!);
              // Если включены лаб-ки, пересчитываем и лаб-группу
              if (_currentGroup!.includeLabs && !_currentGroup!.isLabGroup) {
                final labGroupName = '${_currentGroup!.name}_Лаб';
                final labGroup = _service.getGroupByName(labGroupName);
                if (labGroup != null) {
                  await _service.calculateRatings(labGroup);
                }
              }
              final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
              setState(() {
                _students = updatedStudents;
              });
              _refreshTable();
            }
          },
        ),
        const Text('Теория'),
        const SizedBox(width: 16),
        // Поиск
        SizedBox(
          width: 200,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Поиск студента...',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim();
              });
              _refreshTable();
            },
          ),
        ),
        const SizedBox(width: 16),
        // Кнопки управления
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: _showAddGroupDialog,
          tooltip: 'Добавить группу',
        ),
        IconButton(
          icon: const Icon(Icons.person_add),
          onPressed: _showAddStudentDialog,
          tooltip: 'Добавить студентов',
        ),
        IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: _showAddDateDialog,
          tooltip: 'Добавить дату',
        ),
        if (_dates.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Удалить дату',
            onSelected: (String dateId) {
              final date = _dates.firstWhere((d) => d.key.toString() == dateId);
              _showDeleteDateDialog(date);
            },
            itemBuilder: (BuildContext context) => _dates.map((date) {
              return PopupMenuItem<String>(
                value: date.key.toString(),
                child: Text('Удалить "${date.label}"'),
              );
            }).toList(),
          ),
      ],
    );
  }
  
  Widget? _buildMobileDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text(
              'Меню',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Добавить группу'),
            onTap: () {
              Navigator.pop(context);
              _showAddGroupDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Добавить студентов'),
            onTap: () {
              Navigator.pop(context);
              _showAddStudentDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Добавить дату'),
            onTap: () {
              Navigator.pop(context);
              _showAddDateDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.calculate),
            title: const Text('Рассчитать оценки'),
            onTap: () async {
              Navigator.pop(context);
              if (_currentGroup != null) {
                await _service.calculateRatings(_currentGroup!);
                _refreshTable();
              }
            },
          ),
        ],
      ),
    );
  }
  
  Future<void> _onLabCellChanged(PlutoGridOnChangedEvent event) async {
    if (_labGroup == null) return;

    // Завершаем редактирование ячейки
    _labStateManager?.setKeepFocus(false);
    
    final row = event.row;
    final column = event.column;
    final newValue = event.value;
    
    final studentName = row.cells['student']?.value as String?;
    if (studentName == null || studentName.isEmpty) return;
    
    final labStudents = _service.getStudentsByGroup(_labGroup!);
    final labDates = _service.getDatesByGroup(_labGroup!);
    labDates.sort((a, b) => a.date.compareTo(b.date));
    
    Student? student;
    try {
      student = labStudents.firstWhere((s) => s.name == studentName);
    } catch (e) {
      return;
    }
    
    bool needRecalc = false;
    
    if (column.field == 'student') {
      final newName = newValue.toString().trim();
      if (newName.isEmpty) return;
      student.name = newName;
      await _service.updateStudent(student);
      _refreshTable();
      return;
    } else if (column.field.startsWith('date_')) {
      try {
        final dateIndex = int.parse(column.field.split('_')[1]);
        if (dateIndex >= labDates.length) return;
        final date = labDates[dateIndex];
        
        String gradeValue = (newValue?.toString() ?? '').trim();
        
        if (gradeValue.isNotEmpty) {
          try {
            final val = double.parse(gradeValue.replaceAll(',', '.'));
            if (val > 100) {
              gradeValue = '100';
            } else if (val < 0) {
              gradeValue = '0';
            } else {
              gradeValue = val == val.truncateToDouble() 
                  ? val.toInt().toString() 
                  : val.toString();
            }
          } catch (e) {
            if (gradeValue.toUpperCase() != 'Н') {
              gradeValue = '';
            }
          }
        }
        
        await _service.addOrUpdateGrade(
          Grade(
            studentName: student.name,
            groupId: _labGroup!.groupId,
            grade: gradeValue,
            dateId: date.key.toString(),
          ),
        );
        needRecalc = true;
      } catch (e) {
        return;
      }
    } else if (column.field == 'otrabotka') {
      try {
        final val = double.parse(newValue.toString().replaceAll(',', '.'));
        student.otrabotka = val > 100 ? 100.0 : (val < 0 ? 0.0 : val);
        await _service.updateStudent(student);
        needRecalc = true;
      } catch (e) {
        student.otrabotka = 0;
        await _service.updateStudent(student);
        needRecalc = true;
      }
    }
    
      if (needRecalc) {
      // Завершаем редактирование перед пересчётом
      _labStateManager?.setKeepFocus(false);
      
      await _service.calculateRatings(_labGroup!);
      // Если включены лаб-ки в основной группе, пересчитываем и её
      if (_currentGroup != null && !_currentGroup!.isLabGroup && _includeLabs) {
        await _service.calculateRatings(_currentGroup!);
      }
      // Инвалидируем кэш после пересчета
      _invalidateCache();
      // Принудительно перечитываем студентов
      final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
      setState(() {
        _students = updatedStudents;
        _gridVersion++; // Инкрементируем версию для перерендера
      });
    }
    
    _refreshTable();
  }

  Future<void> _onCellChanged(PlutoGridOnChangedEvent event) async {
    if (_currentGroup == null) return;

    // Завершаем редактирование ячейки
    _stateManager?.setKeepFocus(false);
    
    final row = event.row;
    final column = event.column;
    final newValue = event.value;

    final studentName = row.cells['student']?.value as String?;
    if (studentName == null || studentName.isEmpty) return;

    Student? student;
    try {
      student = _students.firstWhere((s) => s.name == studentName);
    } catch (e) {
      return; // Студент не найден
    }

    bool needRecalc = false;

    // Редактирование имени студента
    if (column.field == 'student') {
      final newName = newValue.toString().trim();
      if (newName.isEmpty) return;
      student.name = newName;
      await _service.updateStudent(student);
      // Обновляем список студентов
      _students = _service.getStudentsByGroup(_currentGroup!);
      _refreshTable();
      return;
    }
    // Редактирование оценки по дате
    else if (column.field.startsWith('date_')) {
      try {
        final dateIndex = int.parse(column.field.split('_')[1]);
        if (dateIndex >= _dates.length) return;
        final date = _dates[dateIndex];
        
        String gradeValue = (newValue?.toString() ?? '').trim();
        
        // Валидация согласно main.py
        if (gradeValue.isNotEmpty) {
          try {
            final val = double.parse(gradeValue.replaceAll(',', '.'));
            if (val > 100) {
              gradeValue = '100';
            } else if (val < 0) {
              gradeValue = '0';
            } else {
              // Форматируем как int если целое число
              gradeValue = val == val.truncateToDouble() 
                  ? val.toInt().toString() 
                  : val.toString();
            }
          } catch (e) {
            // Допускаем «Н» (н/я). Всё остальное – пусто
            if (gradeValue.toUpperCase() != 'Н') {
              gradeValue = '';
            }
          }
        }

        await _service.addOrUpdateGrade(
          Grade(
            studentName: student.name,
            groupId: _currentGroup!.groupId,
            grade: gradeValue,
            dateId: date.key.toString(),
          ),
        );
        needRecalc = true;
      } catch (e) {
        // Ошибка парсинга индекса даты
        return;
      }
    }
    // Редактирование отработки
    else if (column.field == 'otrabotka') {
      try {
        final val = double.parse(newValue.toString().replaceAll(',', '.'));
        student.otrabotka = val > 100 ? 100.0 : (val < 0 ? 0.0 : val);
        await _service.updateStudent(student);
        needRecalc = true;
      } catch (e) {
        student.otrabotka = 0;
        await _service.updateStudent(student);
        needRecalc = true;
      }
    }
    // Редактирование экзамена (только если включен экзамен)
    else if (column.field == 'exam') {
      if (!_includeExam) {
        return;
      }
      try {
        final val = double.parse(newValue.toString().replaceAll(',', '.'));
        student.exam = val > 100 ? 100.0 : (val < 0 ? 0.0 : val);
        await _service.updateStudent(student);
        needRecalc = true;
      } catch (e) {
        student.exam = 0;
        await _service.updateStudent(student);
        needRecalc = true;
      }
    }

    // Пересчитываем оценки после изменения
    if (needRecalc) {
      // Завершаем редактирование перед пересчётом
      _stateManager?.setKeepFocus(false);
      
      await _service.calculateRatings(_currentGroup!);
      // Если включены лаб-ки, пересчитываем и лаб-группу
      if (_currentGroup!.includeLabs && !_currentGroup!.isLabGroup) {
        final labGroupName = '${_currentGroup!.name}_Лаб';
        final labGroup = _service.getGroupByName(labGroupName);
        if (labGroup != null) {
          await _service.calculateRatings(labGroup);
        }
      }
      // Инвалидируем кэш после пересчета
      _invalidateCache();
      // Принудительно перечитываем студентов
      final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
      setState(() {
        _students = updatedStudents;
        _gridVersion++; // Инкрементируем версию для перерендера
      });
    }
    
    _refreshTable();
  }
  
  // Инвалидация кэша при изменении данных
  void _invalidateCacheForGroup(String? groupId) {
    if (groupId != null) {
      _studentsCache.remove(groupId);
      _datesCache.remove(groupId);
      _gradesCache.remove(groupId);
    }
  }

  void _showDeleteStudentDialog(String studentName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление студента'),
        content: Text('Удалить студента "$studentName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (result == true && _currentGroup != null) {
      final student = _service.getStudentByNameAndGroup(studentName, _currentGroup!.groupId);
      if (student != null) {
        await _service.deleteStudent(student);
        // Синхронизация с параллельной группой
        if (!_currentGroup!.isLabGroup) {
          final labGroupName = '${_currentGroup!.name}_Лаб';
          final labGroup = _service.getGroupByName(labGroupName);
          if (labGroup != null) {
            final labStudent = _service.getStudentByNameAndGroup(studentName, labGroup.groupId);
            if (labStudent != null) {
              await _service.deleteStudent(labStudent);
            }
          }
        } else {
          // Если это лаб-группа, удаляем из теории
          final baseGroupName = _currentGroup!.name.replaceAll('_Лаб', '');
          final baseGroup = _service.getGroupByName(baseGroupName);
          if (baseGroup != null) {
            final baseStudent = _service.getStudentByNameAndGroup(studentName, baseGroup.groupId);
            if (baseStudent != null) {
              await _service.deleteStudent(baseStudent);
            }
          }
        }
        _invalidateCacheForGroup(_currentGroup?.groupId);
        _refreshTable();
      }
    }
  }

  void _showDeleteDateDialog(LessonDate date) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление даты'),
        content: Text('Удалить дату "${date.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _service.deleteDate(date);
      _invalidateCacheForGroup(_currentGroup?.groupId);
      _refreshTable();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Электронный журнал'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            onPressed: () async {
              if (_currentGroup != null) {
      // Завершаем редактирование перед пересчётом
      _stateManager?.setKeepFocus(false);
      _labStateManager?.setKeepFocus(false);
                
                // Инвалидируем кэш перед расчетом
                _invalidateCacheForGroup(_currentGroup!.groupId);
                // Пересчитываем оценки
                await _service.calculateRatings(_currentGroup!);
                // Если включены лаб-ки, пересчитываем и лаб-группу
                if (_currentGroup!.includeLabs && !_currentGroup!.isLabGroup) {
                  final labGroupName = '${_currentGroup!.name}_Лаб';
                  final labGroup = _service.getGroupByName(labGroupName);
                  if (labGroup != null) {
                    await _service.calculateRatings(labGroup);
                  }
                }
                // Обновляем данные студентов после пересчета - перечитываем из базы
                _invalidateCacheForGroup(_currentGroup!.groupId);
                // Принудительно перечитываем студентов
                final updatedStudents = _service.getStudentsByGroup(_currentGroup!);
                setState(() {
                  _students = updatedStudents;
                  _gridVersion++; // Инкрементируем версию для перерендера
                });
                // Обновляем таблицу
                _refreshTable();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Оценки пересчитаны')),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Сначала выберите группу')),
                );
              }
            },
            tooltip: 'Рассчитать оценки',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
            tooltip: 'Настройки',
          ),
        ],
      ),
      drawer: isMobile ? _buildMobileDrawer() : null,
      body: Column(
        children: [
          // Панель управления - адаптивная для мобильных
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : 8),
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[800] 
                : Colors.grey[200],
            child: isMobile
                ? _buildMobileControls()
                : _buildDesktopControls(),
          ),
          // Таблицы (основная и лаб)
          Expanded(
            child: _buildTablesWidget(),
          ),
        ],
      ),
    );
  }

  void _showAddGroupDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить группу'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Название группы',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите название группы')),
                );
                return;
              }
              // Запрещаем создавать группы с _Лаб в конце
              if (nameController.text.trim().endsWith('_Лаб')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Название группы не может заканчиваться на "_Лаб"')),
                );
                return;
              }
              Navigator.pop(context);
              final group = Group(name: nameController.text.trim());
              await _service.addGroup(group);
              if (mounted) {
                setState(() {
                  _currentGroup = group;
                });
                _invalidateCache();
                _refreshTable();
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
  
  void _showDeleteGroupDialog() async {
    if (_currentGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выберите группу')),
      );
      return;
    }

    final groupName = _currentGroup!.name;
    final labGroupName = '${_currentGroup!.name}_Лаб';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление группы'),
        content: Text('Удалить группу "$groupName" и связанную "$labGroupName"?\n\nВсе студенты, даты и оценки будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (result == true && _currentGroup != null) {
      final groupToDelete = _currentGroup!;
      final labGroup = _service.getGroupByName(labGroupName);
      
      // Удаляем основную группу
      await _service.deleteGroup(groupToDelete);
      
      // Удаляем связанную лаб-группу, если существует
      if (labGroup != null) {
        await _service.deleteGroup(labGroup);
      }
      
      if (mounted) {
        _invalidateCache();
        setState(() {
          _currentGroup = null;
        });
        _refreshTable();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Группа удалена')),
        );
      }
    }
  }

  void _showAddStudentDialog() {
    if (_currentGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выберите группу')),
      );
      return;
    }

    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить студентов'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Имена через запятую',
          ),
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите имена студентов')),
                );
                return;
              }
              final names = nameController.text
                  .split(',')
                  .map((n) => n.trim())
                  .where((n) => n.isNotEmpty)
                  .toList();
              if (names.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите имена студентов')),
                );
                return;
              }
              Navigator.pop(context);
              for (final name in names) {
                final student = Student(
                  name: name,
                  groupId: _currentGroup!.groupId,
                );
                await _service.addStudent(student);
                
                // Синхронизируем с параллельной лаб-группой
                if (!_currentGroup!.isLabGroup) {
                  final labGroupName = '${_currentGroup!.name}_Лаб';
                  final labGroup = _service.getGroupByName(labGroupName);
                  if (labGroup != null) {
                    final labStudent = Student(
                      name: name,
                      groupId: labGroup.groupId,
                    );
                    await _service.addStudent(labStudent);
                  }
                } else {
                  // Если это лаб-группа, добавляем в основную
                  final baseGroupName = _currentGroup!.name.replaceAll('_Лаб', '');
                  final baseGroup = _service.getGroupByName(baseGroupName);
                  if (baseGroup != null) {
                    final baseStudent = Student(
                      name: name,
                      groupId: baseGroup.groupId,
                    );
                    await _service.addStudent(baseStudent);
                  }
                }
              }
              if (mounted) {
                _invalidateCacheForGroup(_currentGroup?.groupId);
                _refreshTable();
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showAddDateDialog() async {
    if (_currentGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выберите группу')),
      );
      return;
    }

    // Если включены лаб-ки, спрашиваем куда добавлять
    String? targetGroupType;
    if (_includeLabs && !_currentGroup!.isLabGroup) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Куда добавить дату?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.book),
                title: const Text('Теория'),
                onTap: () => Navigator.pop(context, 'theory'),
              ),
              ListTile(
                leading: const Icon(Icons.science),
                title: const Text('Лаб-ки'),
                onTap: () => Navigator.pop(context, 'lab'),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('В обе'),
                onTap: () => Navigator.pop(context, 'both'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
      
      if (choice == null) return;
      targetGroupType = choice;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => JournalDatePickerDialog(),
    );

    if (result != null) {
      final dates = result['dates'] as List<DateTime>;
      
      for (final date in dates) {
        // Формат даты: дд.мм.гггг
        final dateLabel = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
        
        if (targetGroupType == 'theory' || targetGroupType == 'both' || targetGroupType == null) {
          final dateObj = LessonDate(
            date: date,
            label: dateLabel,
            groupId: _currentGroup!.groupId,
          );
          await _service.addDate(dateObj);
        }
        
        if (targetGroupType == 'lab' || targetGroupType == 'both') {
          final labGroupName = '${_currentGroup!.name}_Лаб';
          final labGroup = _service.getGroupByName(labGroupName);
          if (labGroup != null) {
            final labDateObj = LessonDate(
              date: date,
              label: dateLabel,
              groupId: labGroup.groupId,
            );
            await _service.addDate(labDateObj);
          }
        }
      }
      if (mounted) {
        _invalidateCacheForGroup(_currentGroup?.groupId);
        if (_labGroup != null) {
          _invalidateCacheForGroup(_labGroup?.groupId);
        }
        _refreshTable();
      }
    }
  }
}

