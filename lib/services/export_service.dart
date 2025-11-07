// Сервис для экспорта данных в Excel и CSV
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/journal_models.dart';
import 'journal_service.dart';

class ExportService {
  final JournalService _journalService;

  ExportService(this._journalService);

  // Экспорт всех групп в Excel (каждая группа - отдельная страница)
  Future<String> exportAllGroupsToExcel() async {
    final allGroups = _journalService.getAllGroups();
    if (allGroups.isEmpty) {
      throw Exception('Нет групп для экспорта');
    }

    var excel = Excel.createExcel();
    excel.delete('Sheet1');

    for (final group in allGroups) {
      await _addGroupToExcelSheet(excel, group);
    }

    // Сохраняем файл
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/Все_группы_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final fileBytes = excel.save();
    if (fileBytes != null) {
      File(filePath).writeAsBytesSync(fileBytes);
      return filePath;
    }
    throw Exception('Ошибка сохранения Excel файла');
  }

  // Добавляет группу в Excel как отдельную страницу
  Future<void> _addGroupToExcelSheet(Excel excel, Group group) async {
    final students = _journalService.getStudentsByGroup(group);
    final dates = _journalService.getDatesByGroup(group);
    dates.sort((a, b) => a.date.compareTo(b.date));

    // Создаем страницу для группы (убираем недопустимые символы для имени листа)
    final sheetName = group.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    Sheet sheetObject = excel[sheetName];

    // Заголовки
    List<String> headers = ['Студент'];
    for (final date in dates) {
      headers.add(date.label);
    }
    headers.addAll(['Н', 'РО', 'Отработка', 'Р']);
    if (group.includeExam) {
      headers.add('Экзам');
    }
    headers.addAll(['Итог', 'Бук. экв.', 'Циф. экв.']);

    // Записываем заголовки
    for (int i = 0; i < headers.length; i++) {
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
    }

    // Записываем данные студентов
    for (int rowIndex = 0; rowIndex < students.length; rowIndex++) {
      final student = students[rowIndex];
      int colIndex = 0;

      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = TextCellValue(student.name);

      // Оценки по датам
      final grades = _journalService.getGradesByStudent(student);
      final gradeMap = <String, String>{};
      for (final g in grades) {
        gradeMap[g.dateId] = g.grade;
      }

      for (final date in dates) {
        final gradeValue = gradeMap[date.key.toString()] ?? '';
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = TextCellValue(gradeValue);
      }

      // Спецстолбцы
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = IntCellValue(student.letterCount);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.roValue);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.otrabotka);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.rValue);
      
      if (group.includeExam) {
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.exam);
      }
      
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.itogValue);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = TextCellValue(student.letterEq);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.digitalEq);
    }
  }

  // Экспорт в Excel (одна группа)
  Future<String> exportToExcel(Group group) async {
    final students = _journalService.getStudentsByGroup(group);
    final dates = _journalService.getDatesByGroup(group);
    dates.sort((a, b) => a.date.compareTo(b.date));

    var excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheetName = group.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    Sheet sheetObject = excel[sheetName];

    // Заголовки
    List<String> headers = ['Студент'];
    for (final date in dates) {
      headers.add(date.label);
    }
    headers.addAll(['Н', 'РО', 'Отработка', 'Р']);
    if (group.includeExam) {
      headers.add('Экзам');
    }
    headers.addAll(['Итог', 'Бук. экв.', 'Циф. экв.']);

    // Записываем заголовки
    for (int i = 0; i < headers.length; i++) {
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
    }

    // Записываем данные студентов
    for (int rowIndex = 0; rowIndex < students.length; rowIndex++) {
      final student = students[rowIndex];
      int colIndex = 0;

      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = TextCellValue(student.name);

      // Оценки по датам
      final grades = _journalService.getGradesByStudent(student);
      final gradeMap = <String, String>{};
      for (final g in grades) {
        gradeMap[g.dateId] = g.grade;
      }

      for (final date in dates) {
        final gradeValue = gradeMap[date.key.toString()] ?? '';
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = TextCellValue(gradeValue);
      }

      // Спецстолбцы
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = IntCellValue(student.letterCount);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.roValue);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.otrabotka);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.rValue);
      
      if (group.includeExam) {
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.exam);
      }
      
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.itogValue);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = TextCellValue(student.letterEq);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: colIndex++, rowIndex: rowIndex + 1)).value = DoubleCellValue(student.digitalEq);
    }

    // Сохраняем файл
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/Группа_${group.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final fileBytes = excel.save();
    if (fileBytes != null) {
      File(filePath).writeAsBytesSync(fileBytes);
      return filePath;
    }
    throw Exception('Ошибка сохранения Excel файла');
  }

  // Экспорт в CSV
  Future<String> exportToCSV(Group group) async {
    final students = _journalService.getStudentsByGroup(group);
    final dates = _journalService.getDatesByGroup(group);
    dates.sort((a, b) => a.date.compareTo(b.date));

    List<List<dynamic>> rows = [];

    // Заголовки
    List<String> headers = ['Студент'];
    for (final date in dates) {
      headers.add(date.label);
    }
    headers.addAll(['Н', 'РО', 'Отработка', 'Р']);
    if (group.includeExam) {
      headers.add('Экзам');
    }
    headers.addAll(['Итог', 'Бук. экв.', 'Циф. экв.']);
    rows.add(headers);

    // Данные студентов
    for (final student in students) {
      List<dynamic> row = [student.name];

      // Оценки по датам
      final grades = _journalService.getGradesByStudent(student);
      final gradeMap = <String, String>{};
      for (final g in grades) {
        gradeMap[g.dateId] = g.grade;
      }

      for (final date in dates) {
        row.add(gradeMap[date.key.toString()] ?? '');
      }

      // Спецстолбцы
      row.addAll([
        student.letterCount,
        student.roValue,
        student.otrabotka,
        student.rValue,
      ]);
      
      if (group.includeExam) {
        row.add(student.exam);
      }
      
      row.addAll([
        student.itogValue,
        student.letterEq,
        student.digitalEq,
      ]);

      rows.add(row);
    }

    // Конвертируем в CSV
    String csv = const ListToCsvConverter().convert(rows);

    // Сохраняем файл
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/Группа_${group.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
    File(filePath).writeAsStringSync(csv);
    return filePath;
  }

  // Сохранить файл через диалог выбора места сохранения
  Future<String?> saveFile(String filePath, String fileName, String extension) async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Выберите место для сохранения файла',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: extension == 'xlsx' 
            ? ['xlsx'] 
            : extension == 'csv' 
                ? ['csv'] 
                : extension == 'json'
                    ? ['json']
                    : [extension],
      );
      
      if (outputFile != null) {
        if (filePath.isNotEmpty) {
          // Копируем файл в выбранное место
          final sourceFile = File(filePath);
          final targetFile = File(outputFile);
          await sourceFile.copy(targetFile.path);
          return targetFile.path;
        } else {
          // Создаем новый файл
          final targetFile = File(outputFile);
          await targetFile.writeAsString('');
          return targetFile.path;
        }
      }
      return null;
    } catch (e) {
      // Если диалог не поддерживается (например, на вебе), используем исходный путь
      if (filePath.isNotEmpty) {
        return filePath;
      }
      // Создаем временный файл
      final directory = await getApplicationDocumentsDirectory();
      final tempFile = File('${directory.path}/$fileName');
      await tempFile.writeAsString('');
      return tempFile.path;
    }
  }
}

