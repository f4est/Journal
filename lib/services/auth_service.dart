// Сервис аутентификации через Firebase
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // Текущий пользователь
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Регистрация с email и паролем
  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      rethrow;
    }
  }

  // Вход с email и паролем
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } catch (e) {
      rethrow;
    }
  }

  // Вход через Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Запускаем процесс входа в Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // Пользователь отменил вход
        return null;
      }

      // Получаем детали аутентификации
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      if (googleAuth.accessToken == null || googleAuth.idToken == null) {
        throw Exception('Не удалось получить данные аутентификации Google');
      }

      // Создаем новый credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Входим в Firebase с Google credential
      return await _auth.signInWithCredential(credential);
    } on MissingPluginException {
      throw Exception('Google Sign In не настроен. Убедитесь, что плагин правильно установлен и перезапустите приложение.');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        throw Exception('Аккаунт с таким email уже существует. Используйте другой метод входа.');
      } else if (e.code == 'invalid-credential') {
        throw Exception('Неверные учетные данные Google. Попробуйте снова.');
      } else if (e.code == 'network-request-failed') {
        throw Exception('Ошибка сети. Проверьте подключение к интернету.');
      }
      throw Exception('Ошибка входа через Google: ${e.message}');
    } catch (e) {
      throw Exception('Ошибка входа через Google: $e');
    }
  }
  
  // Обновить профиль пользователя
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Пользователь не авторизован');
    
    await user.updateDisplayName(displayName);
    await user.updatePhotoURL(photoURL);
    await user.reload();
  }

  // Выход
  Future<void> signOut() async {
    try {
      // Пытаемся выйти из Google, но игнорируем ошибки если плагин не настроен
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        // Игнорируем ошибки Google Sign In при выходе
      }
      await _auth.signOut();
    } catch (e) {
      // В любом случае выходим из Firebase
      await _auth.signOut();
      rethrow;
    }
  }

  // Сброс пароля
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Удаление аккаунта
  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }
}

