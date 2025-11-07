// Сервис для работы с шаблонами
import 'package:hive/hive.dart';
import '../models/template_models.dart';
import 'calculations_service.dart';

class TemplateService {
  late Box<Template> templateBox;

  static final TemplateService _instance = TemplateService._();
  TemplateService._();
  factory TemplateService() => _instance;

  Future<void> init() async {
    templateBox = await Hive.openBox<Template>('templates');
    
    // Создаем дефолтный шаблон если его нет
    if (templateBox.isEmpty) {
      await _createDefaultTemplate();
    }
  }

  // Создание дефолтного шаблона с текущими формулами
  Future<void> _createDefaultTemplate() async {
    final columns = [
      ColumnDefinition(
        field: 'letter_count',
        title: 'Н',
        type: 'calculated',
        formula: 'COUNT_N(grades)',
        readOnly: true,
        frozen: true,
        width: 50.0,
        order: 0,
      ),
      ColumnDefinition(
        field: 'ro_value',
        title: 'РО',
        type: 'calculated',
        formula: 'RO(grades, labData)',
        readOnly: true,
        frozen: true,
        width: 70.0,
        format: '0.1',
        order: 1,
      ),
      ColumnDefinition(
        field: 'otrabotka',
        title: 'Отработка',
        type: 'number',
        readOnly: false,
        frozen: true,
        width: 90.0,
        order: 2,
      ),
      ColumnDefinition(
        field: 'r_value',
        title: 'Р',
        type: 'calculated',
        formula: 'R(grades, otrabotka, labData)',
        readOnly: true,
        frozen: true,
        width: 70.0,
        format: '0.1',
        order: 3,
      ),
      ColumnDefinition(
        field: 'exam',
        title: 'Экзам',
        type: 'number',
        readOnly: false,
        frozen: true,
        width: 70.0,
        order: 4,
      ),
      ColumnDefinition(
        field: 'itog_value',
        title: 'Итог',
        type: 'calculated',
        formula: 'ITOG(r_value, exam, includeExam)',
        readOnly: true,
        frozen: true,
        width: 70.0,
        format: '0.1',
        order: 5,
      ),
      ColumnDefinition(
        field: 'letter_eq',
        title: 'Бук. экв.',
        type: 'calculated',
        formula: 'LETTER_EQ(itog_value)',
        readOnly: true,
        frozen: true,
        width: 80.0,
        order: 6,
      ),
      ColumnDefinition(
        field: 'digital_eq',
        title: 'Циф. экв.',
        type: 'calculated',
        formula: 'DIGITAL_EQ(itog_value)',
        readOnly: true,
        frozen: true,
        width: 90.0,
        format: '0.2',
        order: 7,
      ),
    ];

    final defaultTemplate = Template(
      templateId: 'default',
      name: 'Дефолтный шаблон',
      description: 'Стандартный шаблон с формулами РО, Р, Итог и эквивалентами',
      columns: columns,
      isDefault: true,
    );

    await templateBox.add(defaultTemplate);
  }

  // Получить все шаблоны
  List<Template> getAllTemplates() {
    return templateBox.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  // Получить шаблон по ID
  Template? getTemplateById(String templateId) {
    try {
      return templateBox.values.firstWhere((t) => t.templateId == templateId);
    } catch (e) {
      return null;
    }
  }

  // Получить дефолтный шаблон
  Template? getDefaultTemplate() {
    try {
      return templateBox.values.firstWhere((t) => t.isDefault);
    } catch (e) {
      return templateBox.values.isNotEmpty ? templateBox.values.first : null;
    }
  }

  // Сохранить шаблон
  Future<void> saveTemplate(Template template) async {
    template.updatedAt = DateTime.now();
    await template.save();
  }

  // Добавить шаблон
  Future<void> addTemplate(Template template) async {
    // Если это новый дефолтный шаблон, снимаем дефолт с других
    if (template.isDefault) {
      for (final t in templateBox.values) {
        if (t.isDefault && t.templateId != template.templateId) {
          t.isDefault = false;
          await t.save();
        }
      }
    }
    await templateBox.add(template);
  }

  // Удалить шаблон
  Future<void> deleteTemplate(Template template) async {
    // Нельзя удалить дефолтный шаблон
    if (template.isDefault) {
      throw Exception('Нельзя удалить дефолтный шаблон');
    }
    await template.delete();
  }

  // Установить шаблон как дефолтный
  Future<void> setDefaultTemplate(Template template) async {
    // Снимаем дефолт с других
    for (final t in templateBox.values) {
      if (t.isDefault) {
        t.isDefault = false;
        await t.save();
      }
    }
    template.isDefault = true;
    await template.save();
  }

  // Вычислить значение столбца по формуле
  dynamic calculateColumnValue({
    required ColumnDefinition column,
    required Map<String, dynamic> context, // grades, dates, student, group, labData
  }) {
    if (column.type != 'calculated' || column.formula == null) {
      return null;
    }

    final formula = column.formula!;
    
    // Парсим и выполняем формулу
    // Поддерживаемые функции:
    // COUNT_N(grades) - количество Н
    // RO(grades, labData) - расчет РО
    // R(grades, otrabotka, labData) - расчет Р
    // ITOG(r_value, exam, includeExam) - расчет итога
    // LETTER_EQ(itog_value) - буквенный эквивалент
    // DIGITAL_EQ(itog_value) - цифровой эквивалент
    // SUM(grades) - сумма оценок
    // AVG(grades) - среднее
    // COUNT(grades) - количество
    
    try {
      if (formula == 'COUNT_N(grades)') {
        final grades = context['grades'] as List<String>;
        int count = 0;
        for (final g in grades) {
          if (g.trim().toUpperCase() == 'Н') {
            count++;
          }
        }
        return count;
      }
      
      if (formula == 'RO(grades, labData)') {
        final grades = context['grades'] as List<String>;
        final labData = context['labData'] as Map<String, dynamic>?;
        final dates = context['dates'] as List;
        
        double theorySum = 0.0;
        for (final g in grades) {
          final gTrimmed = g.trim();
          if (gTrimmed.isEmpty || gTrimmed.toUpperCase() == 'Н') continue;
          try {
            theorySum += double.parse(gTrimmed);
          } catch (e) {}
        }
        
        final labSum = labData?['lab_numeric_sum'] ?? 0.0;
        final labCount = labData?['lab_count'] ?? 0;
        
        final totalDates = dates.length + labCount;
        return totalDates > 0 ? (theorySum + labSum) / totalDates : 0.0;
      }
      
      if (formula == 'R(grades, otrabotka, labData)') {
        final grades = context['grades'] as List<String>;
        final otrabotka = context['otrabotka'] as double;
        final labData = context['labData'] as Map<String, dynamic>?;
        final dates = context['dates'] as List;
        
        double theorySum = 0.0;
        int theoryDatesCount = dates.length;
        int countN = 0;
        
        for (final g in grades) {
          final gTrimmed = g.trim();
          if (gTrimmed.isEmpty) continue;
          if (gTrimmed.toUpperCase() == 'Н') {
            countN++;
            continue;
          }
          try {
            theorySum += double.parse(gTrimmed);
          } catch (e) {
            countN++;
          }
        }
        
        final labCount = labData?['lab_count'] ?? 0;
        final labSum = labData?['lab_numeric_sum'] ?? 0.0;
        
        final roVal = (theoryDatesCount + labCount) > 0 
            ? (theorySum + labSum) / (theoryDatesCount + labCount) 
            : 0.0;
        
        double rVal;
        if (countN > 0 && otrabotka > 0) {
          final numerator = theorySum + labSum + otrabotka;
          final denom = (theoryDatesCount - countN) + labCount + 1;
          rVal = denom > 0 ? numerator / denom : 0.0;
        } else if (countN == 0 && otrabotka == 0) {
          final numerator = theorySum + labSum;
          final denom = theoryDatesCount + labCount;
          rVal = denom > 0 ? numerator / denom : 0.0;
        } else if (countN > 0 && otrabotka == 0) {
          rVal = roVal;
        } else {
          final numerator = theorySum + labSum + otrabotka;
          final denom = theoryDatesCount + labCount + 1;
          rVal = denom > 0 ? numerator / denom : 0.0;
        }
        
        return rVal;
      }
      
      if (formula == 'ITOG(r_value, exam, includeExam)') {
        final rValue = context['r_value'] as double? ?? 0.0;
        final exam = context['exam'] as double? ?? 0.0;
        final includeExam = context['includeExam'] as bool? ?? false;
        
        return includeExam ? rValue * 0.6 + exam * 0.4 : rValue;
      }
      
      if (formula == 'LETTER_EQ(itog_value)') {
        final itog = context['itog_value'] as double? ?? 0.0;
        final eq = getEquivalents(itog);
        return eq['letter'] as String;
      }
      
      if (formula == 'DIGITAL_EQ(itog_value)') {
        final itog = context['itog_value'] as double? ?? 0.0;
        final eq = getEquivalents(itog);
        return eq['digital'] as double;
      }
      
      // Простые математические выражения
      // Поддержка: SUM, AVG, COUNT, +, -, *, /, ()
      return _evaluateSimpleFormula(formula, context);
    } catch (e) {
      return null;
    }
  }

  // Простая оценка математических формул с поддержкой переменных
  dynamic _evaluateSimpleFormula(String formula, Map<String, dynamic> context) {
    try {
      // Поддерживаемые функции
      if (formula.startsWith('SUM(') && formula.endsWith(')')) {
        final arg = formula.substring(4, formula.length - 1).trim();
        if (arg == 'grades') {
          final grades = context['grades'] as List<String>? ?? [];
          double sum = 0.0;
          for (final g in grades) {
            try {
              sum += double.parse(g.trim());
            } catch (e) {}
          }
          return sum;
        }
        return _getVariableValue(arg, context) ?? 0.0;
      }
      
      if (formula.startsWith('AVG(') && formula.endsWith(')')) {
        final arg = formula.substring(4, formula.length - 1).trim();
        if (arg == 'grades') {
          return context['grades_avg'] as double? ?? 0.0;
        }
        final value = _getVariableValue(arg, context);
        return value is num ? value.toDouble() : 0.0;
      }
      
      if (formula.startsWith('COUNT(') && formula.endsWith(')')) {
        final arg = formula.substring(6, formula.length - 1).trim();
        if (arg == 'grades') {
          return context['grades_count'] as int? ?? 0;
        }
        if (arg == 'dates') {
          return context['dates_count'] as int? ?? 0;
        }
        final value = _getVariableValue(arg, context);
        if (value is List) return value.length;
        return 0;
      }
      
      if (formula.startsWith('COUNT_N(') && formula.endsWith(')')) {
        return context['count_n'] as int? ?? 0;
      }
      
      // Заменяем переменные на значения из контекста
      String processed = formula;
      
      // Сначала заменяем функции
      processed = processed.replaceAllMapped(
        RegExp(r'\b(SUM|AVG|COUNT|COUNT_N)\(([^)]+)\)'),
        (match) {
          final func = match.group(1)!;
          final arg = match.group(2)!.trim();
          final value = _getVariableValue(arg, context);
          if (value == null) return '0';
          if (func == 'SUM') {
            if (value is List) {
              double sum = 0.0;
              for (final item in value) {
                if (item is num) sum += item.toDouble();
              }
              return sum.toString();
            }
            return value.toString();
          }
          if (func == 'AVG') {
            if (value is List && value.isNotEmpty) {
              double sum = 0.0;
              int count = 0;
              for (final item in value) {
                if (item is num) {
                  sum += item.toDouble();
                  count++;
                }
              }
              return count > 0 ? (sum / count).toString() : '0';
            }
            return value.toString();
          }
          if (func == 'COUNT') {
            if (value is List) return value.length.toString();
            return '1';
          }
          if (func == 'COUNT_N') {
            return value.toString();
          }
          return '0';
        },
      );
      
      // Затем заменяем переменные
      final sortedKeys = context.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (final key in sortedKeys) {
        final value = context[key];
        if (value != null) {
          String replacement;
          if (value is num) {
            replacement = value.toString();
          } else if (value is bool) {
            replacement = value ? '1' : '0';
          } else if (value is List) {
            replacement = value.length.toString();
          } else {
            continue;
          }
          // Заменяем только целые слова (с границами слов)
          processed = processed.replaceAll(RegExp('\\b$key\\b'), replacement);
        }
      }
      
      // Удаляем пробелы
      processed = processed.replaceAll(' ', '');
      
      // Простой парсер арифметических выражений
      return _evaluateExpression(processed);
    } catch (e) {
      return null;
    }
  }
  
  // Получить значение переменной из контекста
  dynamic _getVariableValue(String variable, Map<String, dynamic> context) {
    final trimmed = variable.trim();
    
    // Прямые переменные
    if (context.containsKey(trimmed)) {
      return context[trimmed];
    }
    
    // Специальные случаи
    if (trimmed == 'grades_sum') return context['grades_sum'];
    if (trimmed == 'grades_avg') return context['grades_avg'];
    if (trimmed == 'grades_count') return context['grades_count'];
    if (trimmed == 'dates_count') return context['dates_count'];
    if (trimmed == 'count_n') return context['count_n'];
    if (trimmed == 'lab_sum') return context['lab_sum'];
    if (trimmed == 'lab_count') return context['lab_count'];
    
    return null;
  }
  
  // Простой парсер арифметических выражений (поддерживает +, -, *, /, скобки)
  double _evaluateExpression(String expr) {
    try {
      // Удаляем все пробелы
      expr = expr.replaceAll(' ', '');
      
      // Обрабатываем скобки
      while (expr.contains('(')) {
        final start = expr.lastIndexOf('(');
        final end = expr.indexOf(')', start);
        if (end == -1) break;
        
        final subExpr = expr.substring(start + 1, end);
        final result = _evaluateSimpleExpression(subExpr);
        expr = expr.substring(0, start) + result.toString() + expr.substring(end + 1);
      }
      
      return _evaluateSimpleExpression(expr);
    } catch (e) {
      return 0.0;
    }
  }
  
  // Вычисление простого выражения без скобок
  double _evaluateSimpleExpression(String expr) {
    // Сначала умножение и деление
    expr = _processOperations(expr, ['*', '/']);
    // Затем сложение и вычитание
    expr = _processOperations(expr, ['+', '-']);
    
    return double.tryParse(expr) ?? 0.0;
  }
  
  // Обработка операций
  String _processOperations(String expr, List<String> operators) {
    for (final op in operators) {
      while (expr.contains(op)) {
        final index = expr.indexOf(op);
        if (index == 0 || index == expr.length - 1) break;
        
        // Находим левый операнд
        int leftStart = index - 1;
        while (leftStart > 0 && 
               (expr[leftStart].contains(RegExp(r'[0-9.]')) || 
                expr[leftStart] == '-' || expr[leftStart] == '+')) {
          leftStart--;
        }
        if (leftStart > 0 || !expr[leftStart].contains(RegExp(r'[0-9.]'))) leftStart++;
        
        // Находим правый операнд
        int rightEnd = index + 1;
        while (rightEnd < expr.length && 
               (expr[rightEnd].contains(RegExp(r'[0-9.]')) || 
                (rightEnd == index + 1 && (expr[rightEnd] == '-' || expr[rightEnd] == '+')))) {
          rightEnd++;
        }
        
        final left = double.tryParse(expr.substring(leftStart, index)) ?? 0.0;
        final right = double.tryParse(expr.substring(index + 1, rightEnd)) ?? 0.0;
        
        double result;
        if (op == '*') {
          result = left * right;
        } else if (op == '/') {
          result = right != 0 ? left / right : 0.0;
        } else if (op == '+') {
          result = left + right;
        } else {
          result = left - right;
        }
        
        expr = expr.substring(0, leftStart) + result.toString() + expr.substring(rightEnd);
      }
    }
    return expr;
  }
}

