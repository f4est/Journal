// Модели для системы шаблонов с настраиваемыми столбцами и формулами
import 'package:hive/hive.dart';

part 'template_models.g.dart';

@HiveType(typeId: 10)
class ColumnDefinition extends HiveObject {
  @HiveField(0)
  String field; // Уникальный идентификатор поля (например, 'ro_value', 'r_value')
  
  @HiveField(1)
  String title; // Название столбца
  
  @HiveField(2)
  String type; // 'text', 'number', 'calculated'
  
  @HiveField(3)
  String? formula; // Формула для вычисляемых столбцов (например, 'SUM(dates) / COUNT(dates)')
  
  @HiveField(4)
  bool readOnly; // Можно ли редактировать
  
  @HiveField(5)
  bool frozen; // Закреплен ли столбец (start, end, none)
  
  @HiveField(6)
  double width; // Ширина столбца
  
  @HiveField(7)
  String? format; // Формат отображения (например, '0.1' для одной цифры после запятой)
  
  @HiveField(8)
  int order; // Порядок отображения

  ColumnDefinition({
    required this.field,
    required this.title,
    required this.type,
    this.formula,
    this.readOnly = false,
    this.frozen = false,
    this.width = 80.0,
    this.format,
    this.order = 0,
  });
}

@HiveType(typeId: 11)
class Template extends HiveObject {
  @HiveField(0)
  String templateId; // Уникальный ID шаблона
  
  @HiveField(1)
  String name; // Название шаблона
  
  @HiveField(2)
  String description; // Описание шаблона
  
  @HiveField(3)
  List<ColumnDefinition> columns; // Список столбцов
  
  @HiveField(4)
  bool isDefault; // Является ли шаблон дефолтным
  
  @HiveField(5)
  DateTime createdAt; // Дата создания
  
  @HiveField(6)
  DateTime updatedAt; // Дата обновления

  Template({
    String? templateId,
    required this.name,
    this.description = '',
    required this.columns,
    this.isDefault = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : templateId = templateId ?? DateTime.now().millisecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
}

