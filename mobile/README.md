# SafeRoute Mobile

## Android Flavors

Run explicit flavors so each build points at the intended backend:

```bash
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart --release
flutter build appbundle --flavor prod -t lib/main_prod.dart
```

Override backend URLs when needed:

```bash
flutter run --flavor dev -t lib/main_dev.dart \
  --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000 \
  --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000
```

App IDs:

- Dev: `com.saferoute.app.dev`
- Staging: `com.saferoute.app.staging`
- Prod: `com.saferoute.app`
