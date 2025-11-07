import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'models/journal_models.dart';
import 'models/template_models.dart';
import 'screens/journal_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/settings_screen.dart';
import 'services/journal_service.dart';
import 'services/template_service.dart';
import 'services/app_settings.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Игнорируем ошибки Firebase для веба, если не настроено
    if (!kIsWeb) rethrow;
  }
  
  // Инициализация Hive
  if (!kIsWeb) {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
  }
  // Для веба Hive использует IndexedDB автоматически, инициализация не требуется

  Hive.registerAdapter(GroupAdapter());
  Hive.registerAdapter(StudentAdapter());
  Hive.registerAdapter(LessonDateAdapter());
  Hive.registerAdapter(GradeAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(ColumnDefinitionAdapter());

  // Инициализация русской локали для календаря
  await initializeDateFormatting('ru_RU', null);

  // Инициализация сервисов
  final templateService = TemplateService();
  await templateService.init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppSettings _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _settings.loadSettings();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  ThemeMode _getThemeMode() {
    switch (_settings.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    final journalService = JournalService();
    final auth = FirebaseAuth.instance;
    
    return MaterialApp(
      title: 'Электронный журнал',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _getThemeMode(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_settings.textScale)),
          child: child!,
        );
      },
      home: StreamBuilder<User?>(
        stream: auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const JournalScreen();
          }
          return const AuthScreen();
        },
      ),
      routes: {
        '/auth': (context) => const AuthScreen(),
        '/home': (context) => const JournalScreen(),
        '/settings': (context) => SettingsScreen(journalService: journalService),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
