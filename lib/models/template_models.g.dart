// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ColumnDefinitionAdapter extends TypeAdapter<ColumnDefinition> {
  @override
  final int typeId = 10;

  @override
  ColumnDefinition read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ColumnDefinition(
      field: fields[0] as String,
      title: fields[1] as String,
      type: fields[2] as String,
      formula: fields[3] as String?,
      readOnly: fields[4] as bool,
      frozen: fields[5] as bool,
      width: fields[6] as double,
      format: fields[7] as String?,
      order: fields[8] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ColumnDefinition obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.field)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.formula)
      ..writeByte(4)
      ..write(obj.readOnly)
      ..writeByte(5)
      ..write(obj.frozen)
      ..writeByte(6)
      ..write(obj.width)
      ..writeByte(7)
      ..write(obj.format)
      ..writeByte(8)
      ..write(obj.order);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColumnDefinitionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TemplateAdapter extends TypeAdapter<Template> {
  @override
  final int typeId = 11;

  @override
  Template read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Template(
      templateId: fields[0] as String?,
      name: fields[1] as String,
      description: fields[2] as String,
      columns: (fields[3] as List).cast<ColumnDefinition>(),
      isDefault: fields[4] as bool,
      createdAt: fields[5] as DateTime?,
      updatedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Template obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.templateId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.columns)
      ..writeByte(4)
      ..write(obj.isDefault)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
