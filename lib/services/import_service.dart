// Сервис для импорта данных из Excel и CSV
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../models/journal_models.dart';
import 'journal_service.dart';

class ImportService {
  final JournalService _journalService;

  ImportService(this._journalService);

  // Выбрать файл для импорта
  Future<String?> pickFile({List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions ?? ['xlsx', 'csv'],
    );
    
    if (result != null && result.files.single.path != null) {
      return result.files.single.path;
    }
    return null;
  }

  // Импорт из Excel
  Future<ImportResult> importFromExcel(String filePath, Group targetGroup) async {
    try {
      var bytes = File(filePath).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);
      
      if (excel.tables.isEmpty) {
        throw Exception('Файл Excel пуст или поврежден');
      }

      Sheet sheet = excel.tables.values.first;
      if (sheet.rows.isEmpty) {
        throw Exception('Таблица пуста');
      }

      // Пропускаем заголовки (первая строка)
      int importedStudents = 0;
      int importedGrades = 0;

      for (int rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
        final row = sheet.rows[rowIndex];
        if (row.isEmpty || row[0] == null) continue;

        final studentName = (row[0]?.value?.toString() ?? '').trim();
        if (studentName.isEmpty) continue;

        // Находим или создаем студента
        Student? student = _journalService.getStudentByNameAndGroup(studentName, targetGroup.groupId);
        if (student == null) {
          student = Student(name: studentName, groupId: targetGroup.groupId);
          await _journalService.addStudent(student);
          importedStudents++;
        }

        // Получаем даты группы
        final dates = _journalService.getDatesByGroup(targetGroup);
        dates.sort((a, b) => a.date.compareTo(b.date));

        // Импортируем оценки (начиная с колонки 1, после имени студента)
        for (int colIndex = 1; colIndex < row.length && (colIndex - 1) < dates.length; colIndex++) {
          final gradeValue = (row[colIndex]?.value?.toString() ?? '').trim();
          if (gradeValue.isNotEmpty) {
            final date = dates[colIndex - 1];
            final grade = Grade(
              studentName: studentName,
              groupId: targetGroup.groupId,
              grade: gradeValue,
              dateId: date.key.toString(),
            );
            await _journalService.addOrUpdateGrade(grade);
            importedGrades++;
          }
        }

        // Импортируем спецстолбцы (если есть)
        int specColStart = 1 + dates.length;
        if (row.length > specColStart) {
          // Отработка
          if (row.length > specColStart + 2 && row[specColStart + 2] != null) {
            try {
              student.otrabotka = double.parse(row[specColStart + 2]!.value.toString());
            } catch (e) {
              // Игнорируем ошибки парсинга
            }
          }
          
          // Экзамен (если включен)
          if (targetGroup.includeExam && row.length > specColStart + 4 && row[specColStart + 4] != null) {
            try {
              student.exam = double.parse(row[specColStart + 4]!.value.toString());
            } catch (e) {
              // Игнорируем ошибки парсинга
            }
          }
          
          await _journalService.updateStudent(student);
        }
      }

      // Пересчитываем оценки
      await _journalService.calculateRatings(targetGroup);

      return ImportResult(
        success: true,
        importedStudents: importedStudents,
        importedGrades: importedGrades,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // Импорт из CSV
  Future<ImportResult> importFromCSV(String filePath, Group targetGroup) async {
    try {
      final file = File(filePath);
      final csvContent = await file.readAsString();
      final fields = const CsvToListConverter().convert(csvContent);

      if (fields.isEmpty) {
        throw Exception('Файл CSV пуст');
      }

      // Пропускаем заголовки (первая строка)
      int importedStudents = 0;
      int importedGrades = 0;

      for (int rowIndex = 1; rowIndex < fields.length; rowIndex++) {
        final row = fields[rowIndex];
        if (row.isEmpty || row[0] == null) continue;

        final studentName = row[0].toString().trim();
        if (studentName.isEmpty) continue;

        // Находим или создаем студента
        Student? student = _journalService.getStudentByNameAndGroup(studentName, targetGroup.groupId);
        if (student == null) {
          student = Student(name: studentName, groupId: targetGroup.groupId);
          await _journalService.addStudent(student);
          importedStudents++;
        }

        // Получаем даты группы
        final dates = _journalService.getDatesByGroup(targetGroup);
        dates.sort((a, b) => a.date.compareTo(b.date));

        // Импортируем оценки
        for (int colIndex = 1; colIndex < row.length && (colIndex - 1) < dates.length; colIndex++) {
          final gradeValue = (row[colIndex]?.toString() ?? '').trim();
          if (gradeValue.isNotEmpty) {
            final date = dates[colIndex - 1];
            final grade = Grade(
              studentName: studentName,
              groupId: targetGroup.groupId,
              grade: gradeValue,
              dateId: date.key.toString(),
            );
            await _journalService.addOrUpdateGrade(grade);
            importedGrades++;
          }
        }

        // Импортируем спецстолбцы (если есть)
        int specColStart = 1 + dates.length;
        if (row.length > specColStart) {
          // Отработка
          if (row.length > specColStart + 2 && row[specColStart + 2] != null) {
            try {
              student.otrabotka = double.parse(row[specColStart + 2].toString());
            } catch (e) {
              // Игнорируем ошибки парсинга
            }
          }
          
          // Экзамен (если включен)
          if (targetGroup.includeExam && row.length > specColStart + 4 && row[specColStart + 4] != null) {
            try {
              student.exam = double.parse(row[specColStart + 4].toString());
            } catch (e) {
              // Игнорируем ошибки парсинга
            }
          }
          
          await _journalService.updateStudent(student);
        }
      }

      // Пересчитываем оценки
      await _journalService.calculateRatings(targetGroup);

      return ImportResult(
        success: true,
        importedStudents: importedStudents,
        importedGrades: importedGrades,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}

class ImportResult {
  final bool success;
  final int importedStudents;
  final int importedGrades;
  final String? error;

  ImportResult({
    required this.success,
    this.importedStudents = 0,
    this.importedGrades = 0,
    this.error,
  });
}

