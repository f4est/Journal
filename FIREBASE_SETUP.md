# Настройка Firebase для электронного журнала

## Проблема с разрешениями Firestore

Если вы видите ошибку `[cloud_firestore/permission-denied] Missing or insufficient permissions`, необходимо настроить правила безопасности Firestore.

## Настройка правил безопасности Firestore

1. Откройте [Firebase Console](https://console.firebase.google.com/)
2. Выберите ваш проект
3. Перейдите в раздел **Firestore Database**
4. Откройте вкладку **Rules** (Правила)
5. Замените существующие правила на следующие:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Правила для пользовательских данных
    match /users/{userId} {
      // Пользователь может читать и писать только свои данные
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      // Правила для групп
      match /groups/{groupId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
      
      // Правила для студентов
      match /students/{studentId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
      
      // Правила для дат
      match /dates/{dateId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
      
      // Правила для оценок
      match /grades/{gradeId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

6. Нажмите **Publish** (Опубликовать)

## Настройка Google Sign In

### Для Android

1. В Firebase Console перейдите в **Project Settings** → **Your apps** → **Android app**
2. Скачайте файл `google-services.json`
3. Поместите его в `android/app/`
4. В Firebase Console включите **Google Sign-In** в разделе **Authentication** → **Sign-in method**

### Для iOS

1. В Firebase Console перейдите в **Project Settings** → **Your apps** → **iOS app**
2. Скачайте файл `GoogleService-Info.plist`
3. Поместите его в `ios/Runner/`
4. В Firebase Console включите **Google Sign-In** в разделе **Authentication** → **Sign-in method**

### Для Web

1. В Firebase Console включите **Google Sign-In** в разделе **Authentication** → **Sign-in method**
2. Добавьте ваш домен в список авторизованных доменов

## После настройки

1. Перезапустите приложение (hot restart недостаточно, нужен полный перезапуск)
2. Убедитесь, что Firebase Authentication включен (Email/Password и Google)
3. Проверьте, что правила Firestore опубликованы

## Примечание

Файл `firestore.rules` в корне проекта содержит готовые правила безопасности, которые можно скопировать в Firebase Console.

