# Firebase Setup Guide — A1111 Mini

## 1. Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Add project**
3. Name it `a1111-mini` (or any name you prefer)
4. Disable Google Analytics if you don't need it (or enable — we have the `firebase_analytics` package)
5. Click **Create project**

## 2. Add iOS App

1. In your Firebase project, click the **iOS+** button
2. Enter the **Bundle ID**: `net.neuro9.a1111mini`
3. App nickname: `A1111 Mini`
4. Skip the App Store ID for now
5. Click **Register app**
6. **Download `GoogleService-Info.plist`**
7. Save it as `ios/Runner/GoogleService-Info.plist`. The build copies it into
   the app automatically; without it the app runs with accounts, analytics and
   feature requests turned off.

## 3. Enable Anonymous Authentication

1. In Firebase Console → **Build** → **Authentication**
2. Click **Get started**
3. Go to **Sign-in method** tab
4. Enable **Anonymous** provider
5. Click **Save**

## 4. Set Up Cloud Firestore

1. In Firebase Console → **Build** → **Firestore Database**
2. Click **Create database**
3. Choose a location close to you (e.g., `us-central1` or `asia-southeast1`)
4. Start in **test mode** for development (we'll lock it down later)
5. Click **Enable**

## 5. Firestore Security Rules (Production)

Once you're ready to secure the database, replace the default rules with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Admin UIDs — add your Firebase anonymous auth UID here
    function isAdmin() {
      return request.auth != null &&
        request.auth.uid in ['SIMULATOR_ADMIN_UID'];
    }

    match /feature_requests/{requestId} {
      // Anyone authenticated can read
      allow read: if request.auth != null;

      // Anyone authenticated can create
      allow create: if request.auth != null
        && request.resource.data.title is string
        && request.resource.data.title.size() > 0
        && request.resource.data.author_uid == request.auth.uid;

      // Users can only update votes (add/remove themselves)
      allow update: if request.auth != null
        && (
          // Users can toggle their own vote
          (request.resource.data.diff(resource.data).affectedKeys()
            .hasOnly(['voters', 'vote_count']))
          // Admins can update anything
          || isAdmin()
        );

      // Only admins can delete
      allow delete: if isAdmin();

      // Comments subcollection
      match /comments/{commentId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null
          && request.resource.data.text is string
          && request.resource.data.author_uid == request.auth.uid;
        allow update, delete: if isAdmin();
      }
    }
  }
}
```

## 6. Get Your Admin UID

When you first run the app in the simulator, check the Xcode console output for:

```
🔑 Firebase UID: <your-uid-here>
```

Then update **two places** with your UID:
1. `lib/features/feature_requests/presentation/feature_requests_screen.dart` → `_adminUids` set
2. Firestore Security Rules → `isAdmin()` function

## 7. Verify Setup

1. Run the app: `flutter run`
2. Navigate to **Feature Requests** (via the drawer)
3. Submit a test feature request
4. Verify it appears in the Firebase Console → Firestore → `feature_requests` collection
5. Check voting and commenting works

## Troubleshooting

- **"No Firebase App"** error → Make sure `GoogleService-Info.plist` is in `ios/Runner/` and added to the Xcode project
- **Permission denied** → Check Firestore rules are in test mode, or your UID is in the admin list
- **Anonymous auth fails** → Verify Anonymous sign-in is enabled in Firebase Console → Authentication → Sign-in method
