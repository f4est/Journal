// Сервис синхронизации с Firebase Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/journal_models.dart';
import 'journal_service.dart';

class FirebaseSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final JournalService _journalService;

  FirebaseSyncService(this._journalService);

  // Получить путь к данным пользователя
  String get _userId => _auth.currentUser?.uid ?? '';
  String get _groupsPath => 'users/$_userId/groups';
  String get _studentsPath => 'users/$_userId/students';
  String get _datesPath => 'users/$_userId/dates';
  String get _gradesPath => 'users/$_userId/grades';

  // Загрузить все данные из Firebase
  Future<void> syncFromFirebase() async {
    if (_auth.currentUser == null) {
      throw Exception('Пользователь не авторизован');
    }

    try {
      // Очищаем локальные данные перед загрузкой
      final allGroups = _journalService.getAllGroups();
      for (final group in allGroups) {
        await _journalService.deleteGroup(group);
      }
      
      // Загружаем группы
      final groupsSnapshot = await _firestore.collection(_groupsPath).get();
      final groupsMap = <String, Group>{};
      
      for (final doc in groupsSnapshot.docs) {
        final data = doc.data();
        final group = Group(
          name: data['name'] as String,
          includeExam: data['includeExam'] as bool? ?? true,
          includeLabs: data['includeLabs'] as bool? ?? false,
          includeTheory: data['includeTheory'] as bool? ?? true,
          groupId: data['groupId'] as String? ?? doc.id,
          groupType: data['groupType'] as String? ?? 'classic',
        );
        await _journalService.addGroup(group);
        groupsMap[group.groupId] = group;
      }

      // Загружаем студентов
      final studentsSnapshot = await _firestore.collection(_studentsPath).get();
      for (final doc in studentsSnapshot.docs) {
        final data = doc.data();
        final groupId = data['groupId'] as String?;
        if (groupId == null || !groupsMap.containsKey(groupId)) continue;
        
        final student = Student(
          name: data['name'] as String,
          groupId: groupId,
        );
        student.otrabotka = (data['otrabotka'] as num?)?.toDouble() ?? 0.0;
        student.exam = (data['exam'] as num?)?.toDouble() ?? 0.0;
        student.letterCount = data['letterCount'] as int? ?? 0;
        student.roValue = (data['roValue'] as num?)?.toDouble() ?? 0.0;
        student.rValue = (data['rValue'] as num?)?.toDouble() ?? 0.0;
        student.itogValue = (data['itogValue'] as num?)?.toDouble() ?? 0.0;
        student.letterEq = data['letterEq'] as String? ?? '';
        student.digitalEq = (data['digitalEq'] as num?)?.toDouble() ?? 0.0;
        
        // Проверяем, существует ли студент
        final existingStudent = _journalService.getStudentByNameAndGroup(student.name, student.groupId);
        if (existingStudent == null) {
          await _journalService.addStudent(student);
        } else {
          // Обновляем существующего студента
          existingStudent.otrabotka = student.otrabotka;
          existingStudent.exam = student.exam;
          existingStudent.letterCount = student.letterCount;
          existingStudent.roValue = student.roValue;
          existingStudent.rValue = student.rValue;
          existingStudent.itogValue = student.itogValue;
          existingStudent.letterEq = student.letterEq;
          existingStudent.digitalEq = student.digitalEq;
          await _journalService.updateStudent(existingStudent);
        }
      }

      // Загружаем даты
      final datesSnapshot = await _firestore.collection(_datesPath).get();
      final datesMap = <String, LessonDate>{};
      
      for (final doc in datesSnapshot.docs) {
        final data = doc.data();
        final groupId = data['groupId'] as String?;
        if (groupId == null || !groupsMap.containsKey(groupId)) continue;
        
        final date = LessonDate(
          date: (data['date'] as Timestamp).toDate(),
          label: data['label'] as String,
          groupId: groupId,
          notes: data['notes'] as String?,
        );
        await _journalService.addDate(date);
        datesMap[date.key.toString()] = date;
      }

      // Загружаем оценки
      final gradesSnapshot = await _firestore.collection(_gradesPath).get();
      for (final doc in gradesSnapshot.docs) {
        final data = doc.data();
        final groupId = data['groupId'] as String?;
        final dateId = data['dateId'] as String?;
        
        if (groupId == null || !groupsMap.containsKey(groupId)) continue;
        if (dateId == null || !datesMap.containsKey(dateId)) continue;
        
        final grade = Grade(
          studentName: data['studentName'] as String,
          groupId: groupId,
          grade: data['grade'] as String? ?? '',
          dateId: dateId,
        );
        await _journalService.addOrUpdateGrade(grade);
      }
    } catch (e) {
      throw Exception('Ошибка синхронизации с Firebase: $e');
    }
  }

  // Загрузить все данные в Firebase
  Future<void> syncToFirebase() async {
    if (_auth.currentUser == null) return;

    try {
      // Очищаем старые данные
      await _clearFirebaseData();

      // Сохраняем группы
      final groups = _journalService.getAllGroups();
      for (final group in groups) {
        await _firestore.collection(_groupsPath).doc(group.groupId).set({
          'name': group.name,
          'includeExam': group.includeExam,
          'includeLabs': group.includeLabs,
          'includeTheory': group.includeTheory,
          'groupId': group.groupId,
          'groupType': group.groupType,
        });
      }

      // Сохраняем студентов
      for (final group in groups) {
        final students = _journalService.getStudentsByGroup(group);
        for (final student in students) {
          final studentId = student.key.toString();
          await _firestore.collection(_studentsPath).doc(studentId).set({
            'name': student.name,
            'groupId': student.groupId,
            'otrabotka': student.otrabotka,
            'exam': student.exam,
            'letterCount': student.letterCount,
            'roValue': student.roValue,
            'rValue': student.rValue,
            'itogValue': student.itogValue,
            'letterEq': student.letterEq,
            'digitalEq': student.digitalEq,
          });
        }
      }

      // Сохраняем даты
      for (final group in groups) {
        final dates = _journalService.getDatesByGroup(group);
        for (final date in dates) {
          final dateId = date.key.toString();
          await _firestore.collection(_datesPath).doc(dateId).set({
            'date': Timestamp.fromDate(date.date),
            'label': date.label,
            'groupId': date.groupId,
            'notes': date.notes,
          });
        }
      }

      // Сохраняем оценки
      for (final group in groups) {
        final students = _journalService.getStudentsByGroup(group);
        for (final student in students) {
          final grades = _journalService.getGradesByStudent(student);
          for (final grade in grades) {
            final gradeId = grade.key.toString();
            await _firestore.collection(_gradesPath).doc(gradeId).set({
              'studentName': grade.studentName,
              'groupId': grade.groupId,
              'grade': grade.grade,
              'dateId': grade.dateId,
            });
          }
        }
      }
    } catch (e) {
      throw Exception('Ошибка синхронизации с Firebase: $e');
    }
  }

  // Очистить данные в Firebase
  Future<void> _clearFirebaseData() async {
    final batch = _firestore.batch();

    // Удаляем группы
    final groupsSnapshot = await _firestore.collection(_groupsPath).get();
    for (final doc in groupsSnapshot.docs) {
      batch.delete(doc.reference);
    }

    // Удаляем студентов
    final studentsSnapshot = await _firestore.collection(_studentsPath).get();
    for (final doc in studentsSnapshot.docs) {
      batch.delete(doc.reference);
    }

    // Удаляем даты
    final datesSnapshot = await _firestore.collection(_datesPath).get();
    for (final doc in datesSnapshot.docs) {
      batch.delete(doc.reference);
    }

    // Удаляем оценки
    final gradesSnapshot = await _firestore.collection(_gradesPath).get();
    for (final doc in gradesSnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}

