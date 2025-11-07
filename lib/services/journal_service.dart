// Улучшенный сервис для работы с журналом
import 'package:hive/hive.dart';
import '../models/journal_models.dart';
import '../models/template_models.dart';
import 'calculations_service.dart';
import 'template_service.dart';

class JournalService {
  late Box<Group> groupBox;
  late Box<Student> studentBox;
  late Box<LessonDate> dateBox;
  late Box<Grade> gradeBox;

  static final JournalService _instance = JournalService._();
  JournalService._();
  factory JournalService() => _instance;

  Future<void> init() async {
    groupBox = await Hive.openBox<Group>('groups');
    studentBox = await Hive.openBox<Student>('students');
    dateBox = await Hive.openBox<LessonDate>('dates');
    gradeBox = await Hive.openBox<Grade>('grades');
  }

  // ================= Groups ====================
  List<Group> getAllGroups() => groupBox.values.toList();
  Group? getGroupById(String id) {
    try {
      return groupBox.values.firstWhere((g) => g.groupId == id);
    } catch (e) {
      return null;
    }
  }
  
  Group? getGroupByName(String name) {
    try {
      return groupBox.values.firstWhere((g) => g.name == name);
    } catch (e) {
      return null;
    }
  }
  Future<void> addGroup(Group group) async {
    await groupBox.add(group);
    
    // Автоматически создаём зеркальную лабораторную группу, если это не лаб-группа
    if (!group.name.endsWith('_Лаб') && group.groupType != 'lab') {
      final labGroup = Group(
        name: '${group.name}_Лаб',
        includeExam: false,
        includeLabs: false,
        includeTheory: false,
        groupType: 'lab',
      );
      await groupBox.add(labGroup);
    }
  }
  Future<void> updateGroup(Group group) async => await group.save();
  Future<void> deleteGroup(Group group) async {
    // Удаляем связанных студентов, даты и оценки
    final students = getStudentsByGroup(group);
    for (final st in students) {
      await deleteStudent(st);
    }
    final dates = getDatesByGroup(group);
    for (final d in dates) {
      await deleteDate(d);
    }
    await group.delete();
  }

  // ================= Students ==================
  List<Student> getStudentsByGroup(Group group) =>
      studentBox.values.where((st) => st.groupId == group.groupId).toList();
  Student? getStudentByNameAndGroup(String name, String groupId) {
    try {
      return studentBox.values.firstWhere(
        (st) => st.name == name && st.groupId == groupId,
      );
    } catch (e) {
      return null;
    }
  }
  Future<void> addStudent(Student st) async => await studentBox.add(st);
  Future<void> updateStudent(Student st) async => await st.save();
  Future<void> deleteStudent(Student st) async {
    final grades = getGradesByStudent(st);
    for (final g in grades) {
      await deleteGrade(g);
    }
    await st.delete();
  }

  // ================= Dates =====================
  List<LessonDate> getDatesByGroup(Group group) =>
      dateBox.values.where((d) => d.groupId == group.groupId).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  Future<void> addDate(LessonDate d) async => await dateBox.add(d);
  Future<void> updateDate(LessonDate d) async => await d.save();
  Future<void> deleteDate(LessonDate d) async {
    final grades = getGradesByDate(d);
    for (final g in grades) {
      await deleteGrade(g);
    }
    await d.delete();
  }

  // ================= Grades =====================
  List<Grade> getGradesByStudent(Student st) =>
      gradeBox.values.where((g) => g.studentName == st.name && g.groupId == st.groupId).toList();
  List<Grade> getGradesByDate(LessonDate date) =>
      gradeBox.values.where((g) => g.dateId == date.key.toString()).toList();
  Grade? getGrade(String studentName, String groupId, String dateId) {
    try {
      return gradeBox.values.firstWhere(
        (g) => g.studentName == studentName && g.groupId == groupId && g.dateId == dateId,
      );
    } catch (e) {
      return null;
    }
  }
  Future<void> addOrUpdateGrade(Grade grade) async {
    try {
      final existing = gradeBox.values.firstWhere(
        (g) => g.studentName == grade.studentName &&
            g.groupId == grade.groupId &&
            g.dateId == grade.dateId,
      );
      existing.grade = grade.grade;
      await existing.save();
    } catch (e) {
      await gradeBox.add(grade);
    }
  }
  Future<void> updateGrade(Grade g) async => await g.save();
  Future<void> deleteGrade(Grade g) async => await g.delete();

  // ================= Calculations =====================
  Future<void> calculateRatings(Group group) async {
    final templateService = TemplateService();
    
    // Получаем шаблон для группы
    Template? template;
    if (group.templateId != null) {
      template = templateService.getTemplateById(group.templateId!);
    }
    template ??= templateService.getDefaultTemplate();
    
    if (template == null) {
      // Если шаблона нет, используем старую логику (для обратной совместимости)
      await _calculateRatingsLegacy(group);
      return;
    }

    final students = getStudentsByGroup(group);
    final dates = getDatesByGroup(group);

    for (final student in students) {
      final gradesList = getGradesByStudent(student);
      final gradesMap = <String, String>{};
      for (final g in gradesList) {
        gradesMap[g.dateId] = g.grade;
      }

      final gradesArray = dates.map((d) => gradesMap[d.key.toString()] ?? '').toList();

      // Подготовка данных для формул
      Map<String, dynamic>? labData;
      if (group.includeLabs && !group.isLabGroup) {
        final labGroupName = '${group.name}_Лаб';
        try {
          final labGroup = getGroupByName(labGroupName);
          if (labGroup != null) {
            final labStudents = getStudentsByGroup(labGroup);
            final labStudent = labStudents.firstWhere(
              (ls) => ls.name.toLowerCase() == student.name.toLowerCase(),
              orElse: () => throw Exception(),
            );
            final labDates = getDatesByGroup(labGroup);
            final labGradesList = getGradesByStudent(labStudent);
            final labGradesMap = <String, String>{};
            for (final g in labGradesList) {
              labGradesMap[g.dateId] = g.grade;
            }
            final labGradesArray = labDates.map((d) => labGradesMap[d.key.toString()] ?? '').toList();

            double labNumericSum = 0.0;
            int labCount = labDates.length;
            final labOVal = labStudent.otrabotka;

            for (final g in labGradesArray) {
              try {
                final v = double.parse(g);
                labNumericSum += v;
              } catch (e) {}
            }

            labData = {
              'lab_count': labCount,
              'lab_numeric_sum': labNumericSum,
            };
          }
        } catch (e) {}
      }

      // Подготавливаем переменные для формул
      final gradesNumeric = <double>[];
      int countN = 0;
      for (final g in gradesArray) {
        final gTrimmed = g.trim();
        if (gTrimmed.isEmpty) continue;
        if (gTrimmed.toUpperCase() == 'Н') {
          countN++;
        } else {
          try {
            gradesNumeric.add(double.parse(gTrimmed));
          } catch (e) {
            countN++;
          }
        }
      }
      
      final gradesSum = gradesNumeric.fold<double>(0.0, (a, b) => a + b);
      final gradesAvg = gradesNumeric.isNotEmpty ? gradesSum / gradesNumeric.length : 0.0;
      final gradesCount = gradesArray.length;
      final datesCount = dates.length;
      
      final labSum = labData?['lab_numeric_sum'] ?? 0.0;
      final labCount = labData?['lab_count'] ?? 0;

      // Вычисляем значения для каждого столбца шаблона
      final context = <String, dynamic>{
        // Базовые переменные
        'student': student,
        'student_name': student.name,
        'group': group,
        'dates': dates,
        'dates_count': datesCount,
        'grades': gradesArray,
        'grades_count': gradesCount,
        'grades_sum': gradesSum,
        'grades_avg': gradesAvg,
        'count_n': countN,
        'otrabotka': student.otrabotka,
        'exam': student.exam,
        'include_exam': group.includeExam,
        'includeExam': group.includeExam, // для обратной совместимости
        'lab_data': labData,
        'lab_sum': labSum,
        'lab_count': labCount,
        // Вычисляемые значения (будут добавлены по мере вычисления)
      };

      // Вычисляем столбцы в порядке зависимостей
      final calculatedValues = <String, dynamic>{};
      
      // Сначала вычисляем базовые значения
      for (final column in template.columns) {
        if (column.type == 'calculated' && column.formula != null) {
          final value = templateService.calculateColumnValue(
            column: column,
            context: {...context, ...calculatedValues},
          );
          calculatedValues[column.field] = value;
        }
      }

      // Сохраняем вычисленные значения в студента
      // Используем рефлексию или явное сопоставление полей
      for (final column in template.columns) {
        final value = calculatedValues[column.field] ?? 
                     (column.type == 'number' ? (student as dynamic)[column.field] : null);
        
        if (value != null) {
          // Сохраняем в соответствующее поле студента
          switch (column.field) {
            case 'letter_count':
              student.letterCount = value is int ? value : (value as num).toInt();
              break;
            case 'ro_value':
              student.roValue = value is double ? value : (value as num).toDouble();
              break;
            case 'r_value':
              student.rValue = value is double ? value : (value as num).toDouble();
              break;
            case 'itog_value':
              student.itogValue = value is double ? value : (value as num).toDouble();
              break;
            case 'letter_eq':
              student.letterEq = value.toString();
              break;
            case 'digital_eq':
              student.digitalEq = value is double ? value : (value as num).toDouble();
              break;
            case 'otrabotka':
              student.otrabotka = value is double ? value : (value as num).toDouble();
              break;
            case 'exam':
              student.exam = value is double ? value : (value as num).toDouble();
              break;
          }
        }
      }

      // Сбрасываем отработку если Н = 0
      student.otrabotka = resetOtrabotkaIfNeeded(student.letterCount, student.otrabotka);

      await updateStudent(student);
    }
  }

  // Старая логика расчетов (для обратной совместимости)
  Future<void> _calculateRatingsLegacy(Group group) async {
    final isLabGroup = group.isLabGroup;
    final students = getStudentsByGroup(group);
    final dates = getDatesByGroup(group);

    for (final student in students) {
      final gradesList = getGradesByStudent(student);
      final gradesMap = <String, String>{};
      for (final g in gradesList) {
        gradesMap[g.dateId] = g.grade;
      }

      final gradesArray = dates.map((d) => gradesMap[d.key.toString()] ?? '').toList();

      if (isLabGroup) {
        Map<String, dynamic> result;
        if (group.groupType == 'lab') {
          result = calcLabPraktValues(
            gradesList: gradesArray,
            manualO: student.otrabotka,
            labDatesCount: dates.length,
          );
        } else {
          result = calcLabValues(
            gradesList: gradesArray,
            manualO: student.otrabotka,
          );
        }
        student.letterCount = result['countN'] as int;
        student.roValue = result['ro'] as double;
        student.rValue = result['r'] as double;
        student.itogValue = result['itog'] as double;
        final eq = getEquivalents(student.itogValue);
        student.letterEq = eq['letter'] as String;
        student.digitalEq = eq['digital'] as double;
      } else {
        if (!group.includeTheory) {
          student.letterCount = 0;
          student.roValue = 0;
          student.rValue = 0;
          student.itogValue = 0;
          student.letterEq = 'F';
          student.digitalEq = 0.0;
        } else {
          Map<String, dynamic>? labData;
          if (group.includeLabs) {
            final labGroupName = '${group.name}_Лаб';
            try {
              final labGroup = getGroupByName(labGroupName);
              if (labGroup != null) {
                final labStudents = getStudentsByGroup(labGroup);
                final labStudent = labStudents.firstWhere(
                  (ls) => ls.name.toLowerCase() == student.name.toLowerCase(),
                  orElse: () => throw Exception(),
                );
                final labDates = getDatesByGroup(labGroup);
                final labGradesList = getGradesByStudent(labStudent);
                final labGradesMap = <String, String>{};
                for (final g in labGradesList) {
                  labGradesMap[g.dateId] = g.grade;
                }
                final labGradesArray = labDates.map((d) => labGradesMap[d.key.toString()] ?? '').toList();

                double labNumericSum = 0.0;
                double labReplacedSum = 0.0;
                int labCount = labDates.length;
                final labOVal = labStudent.otrabotka;

                for (final g in labGradesArray) {
                  try {
                    final v = double.parse(g);
                    labNumericSum += v;
                    labReplacedSum += v;
                  } catch (e) {
                    labReplacedSum += labOVal;
                  }
                }

                labData = {
                  'lab_count': labCount,
                  'lab_numeric_sum': labNumericSum,
                  'lab_replaced_sum': labReplacedSum,
                };
              }
            } catch (e) {}
          }

          final result = calcTheoryLabValues(
            theoryGrades: gradesArray,
            manualO: student.otrabotka,
            exam: student.exam,
            includeExam: group.includeExam,
            labData: labData,
          );

          student.letterCount = result['countN'] as int;
          student.roValue = result['ro'] as double;
          student.rValue = result['r'] as double;
          student.itogValue = result['itog'] as double;
          student.letterEq = result['letter'] as String;
          student.digitalEq = result['digital'] as double;

          student.otrabotka = resetOtrabotkaIfNeeded(student.letterCount, student.otrabotka);
        }
      }

      await updateStudent(student);
    }
  }
}

