import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/accueil_widget.dart';

void main() {
  // Configuration du système avant le lancement de l'app
  WidgetsFlutterBinding.ensureInitialized();

  // Configuration de l'orientation (optionnel)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configuration de la barre de statut
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Lancement de l'application définie dans accueil_widget.dart
  runApp(const MyApp());
}
