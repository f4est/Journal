// Экран настроек
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/firebase_sync_service.dart';
import '../services/journal_service.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../models/journal_models.dart';
import '../services/app_settings.dart';
import 'help_screen.dart';

class SettingsScreen extends StatefulWidget {
  final JournalService journalService;

  const SettingsScreen({super.key, required this.journalService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  late final FirebaseSyncService _syncService;
  late final ExportService _exportService;
  late final ImportService _importService;
  bool _isSyncing = false;
  String? _syncMessage;
  
  String _themeMode = 'system';
  double _textScale = 1.0;
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _photoURLController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncService = FirebaseSyncService(widget.journalService);
    _exportService = ExportService(widget.journalService);
    _importService = ImportService(widget.journalService);
    _loadSettings();
    _loadProfile();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _themeMode = prefs.getString('theme_mode') ?? 'system';
        _textScale = prefs.getDouble('text_scale') ?? 1.0;
      });
    }
  }

  Future<void> _loadProfile() async {
    final user = _authService.currentUser;
    if (user != null) {
      _displayNameController.text = user.displayName ?? '';
      _photoURLController.text = user.photoURL ?? '';
    }
  }

  Future<void> _saveThemeMode(String themeMode) async {
    await AppSettings().setThemeMode(themeMode);
    if (mounted) {
      setState(() {
        _themeMode = themeMode;
      });
    }
  }

  Future<void> _saveTextScale(double scale) async {
    await AppSettings().setTextScale(scale);
    if (mounted) {
      setState(() {
        _textScale = scale;
      });
    }
  }

  Future<void> _updateProfile() async {
    try {
      await _authService.updateProfile(
        displayName: _displayNameController.text.trim().isEmpty 
            ? null 
            : _displayNameController.text.trim(),
        photoURL: _photoURLController.text.trim().isEmpty 
            ? null 
            : _photoURLController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль обновлен')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления профиля: $e')),
        );
      }
    }
  }

  Future<void> _syncToFirebase() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = 'Синхронизация с Firebase...';
    });

    try {
      await _syncService.syncToFirebase();
      if (mounted) {
        setState(() {
          _syncMessage = 'Данные успешно синхронизированы с Firebase';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные успешно синхронизированы')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncMessage = 'Ошибка синхронизации: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _syncFromFirebase() async {
    // Показываем диалог с выбором
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Загрузка из Firebase'),
        content: const Text(
          'Все локальные данные будут удалены и заменены данными из Firebase. Продолжить?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Заменить все'),
          ),
        ],
      ),
    );

    if (action != 'replace') return;

    setState(() {
      _isSyncing = true;
      _syncMessage = 'Загрузка данных из Firebase...';
    });

    try {
      await _syncService.syncFromFirebase();
      if (mounted) {
        setState(() {
          _syncMessage = 'Данные успешно загружены из Firebase';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные успешно загружены')),
        );
        // Возвращаемся на главный экран для обновления данных
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncMessage = 'Ошибка загрузки: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _exportData() async {
    final allGroups = widget.journalService.getAllGroups();
    if (allGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет групп для экспорта')),
      );
      return;
    }

    // Спрашиваем что экспортировать
    final exportType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Что экспортировать?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Все группы (Excel)'),
              subtitle: const Text('Каждая группа - отдельная страница'),
              onTap: () => Navigator.pop(context, 'all_excel'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Выбрать группу'),
              onTap: () => Navigator.pop(context, 'single'),
            ),
          ],
        ),
      ),
    );

    if (exportType == null) return;

    if (exportType == 'all_excel') {
      try {
        final filePath = await _exportService.exportAllGroupsToExcel();
        final fileName = 'Все_группы_${DateTime.now().millisecondsSinceEpoch}';
        if (mounted) {
          final savedPath = await _exportService.saveFile(filePath, fileName, 'xlsx');
          if (savedPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Файл сохранён: $savedPath')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Сохранение отменено')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка экспорта: $e')),
          );
        }
      }
      return;
    }

    // Выбор одной группы
    final group = await showDialog<Group>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите группу для экспорта'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allGroups.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(allGroups[index].name),
                onTap: () => Navigator.pop(context, allGroups[index]),
              );
            },
          ),
        ),
      ),
    );

    if (group == null) return;

    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите формат'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel (.xlsx)'),
              onTap: () => Navigator.pop(context, 'excel'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('CSV (.csv)'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
          ],
        ),
      ),
    );

    if (format == null) return;

    try {
      String filePath;
      String fileName;
      String extension;
      
      if (format == 'excel') {
        filePath = await _exportService.exportToExcel(group);
        fileName = 'Группа_${group.name}_${DateTime.now().millisecondsSinceEpoch}';
        extension = 'xlsx';
      } else {
        filePath = await _exportService.exportToCSV(group);
        fileName = 'Группа_${group.name}_${DateTime.now().millisecondsSinceEpoch}';
        extension = 'csv';
      }
      
      if (mounted) {
        final savedPath = await _exportService.saveFile(filePath, fileName, extension);
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Файл сохранён: $savedPath')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сохранение отменено')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  Future<void> _importData() async {
    final allGroups = widget.journalService.getAllGroups();
    if (allGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала создайте группу')),
      );
      return;
    }

    final group = await showDialog<Group>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите группу для импорта'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allGroups.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(allGroups[index].name),
                onTap: () => Navigator.pop(context, allGroups[index]),
              );
            },
          ),
        ),
      ),
    );

    if (group == null) return;

    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите формат'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel (.xlsx)'),
              onTap: () => Navigator.pop(context, 'excel'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('CSV (.csv)'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
          ],
        ),
      ),
    );

    if (format == null) return;

    final filePath = await _importService.pickFile(
      allowedExtensions: format == 'excel' ? ['xlsx'] : ['csv'],
    );

    if (filePath == null) return;

    try {
      final result = format == 'excel'
          ? await _importService.importFromExcel(filePath, group)
          : await _importService.importFromCSV(filePath, group);

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Импортировано: ${result.importedStudents} студентов, ${result.importedGrades} оценок',
              ),
            ),
          );
          Navigator.of(context).pop(); // Возвращаемся на главный экран
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка импорта: ${result.error}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _authService.signOut();
        // Навигация происходит автоматически через StreamBuilder в main.dart
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка при выходе: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _photoURLController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Профиль пользователя
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Профиль',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (user != null) ...[
                    TextField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Имя',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _photoURLController,
                      decoration: const InputDecoration(
                        labelText: 'URL фото',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.image),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _updateProfile,
                      child: const Text('Сохранить изменения'),
                    ),
                    const Divider(height: 32),
                    ListTile(
                      leading: const Icon(Icons.email),
                      title: const Text('Email'),
                      subtitle: Text(user.email ?? 'Не указан'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Тема
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Тема',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<String>(
                    title: const Text('Системная'),
                    value: 'system',
                    groupValue: _themeMode,
                    onChanged: (value) => _saveThemeMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Светлая'),
                    value: 'light',
                    groupValue: _themeMode,
                    onChanged: (value) => _saveThemeMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Тёмная'),
                    value: 'dark',
                    groupValue: _themeMode,
                    onChanged: (value) => _saveThemeMode(value!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Масштаб
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Масштаб текста',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _textScale,
                    min: 0.8,
                    max: 1.5,
                    divisions: 7,
                    label: '${(_textScale * 100).toInt()}%',
                    onChanged: (value) => _saveTextScale(value),
                  ),
                  Text('Текущий масштаб: ${(_textScale * 100).toInt()}%'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Импорт/Экспорт
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Импорт/Экспорт',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _exportData,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Экспорт в Excel/CSV'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _importData,
                    icon: const Icon(Icons.download),
                    label: const Text('Импорт из Excel/CSV'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Синхронизация
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Синхронизация с Firebase',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_syncMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _syncMessage!,
                        style: TextStyle(
                          color: _syncMessage!.contains('Ошибка')
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _syncToFirebase,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Загрузить в Firebase'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isSyncing ? null : _syncFromFirebase,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Загрузить из Firebase'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  if (_isSyncing)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Документация
          Card(
            child: ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Документация и помощь'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HelpScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Выход
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Выйти', style: TextStyle(color: Colors.red)),
              onTap: _signOut,
            ),
          ),
        ],
      ),
    );
  }
}
