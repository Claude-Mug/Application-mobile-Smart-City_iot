import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'wifi_control_widget.dart';
import 'bluetooth_widget.dart';
import 'vocal_widget.dart';
import 'switch_widget.dart';
import 'terminal_widget.dart';
import 'pwm_widget.dart';
import 'esp_cam_widget.dart';
import 'package:claude_iot/server/server_front.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeData _themeData = ThemeData(
    primarySwatch: Colors.blue,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  void setTheme(ThemeData theme) async {
    setState(() {
      _themeData = theme;
    });
    final prefs = await SharedPreferences.getInstance();
    // Sauvegarde un identifiant de thème, par exemple 'light', 'dark', 'pink'
    await prefs.setString('theme', theme.brightness == Brightness.dark ? 'dark' : 'light');
  }

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme') ?? 'light';
    // Applique le thème selon themeName
    setTheme(themeName == 'dark' ? ThemeData.dark() : ThemeData.light());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electro-Lab Control',
      theme: _themeData,
      initialRoute: '/',
      routes: {
        '/': (context) => AccueilPage(onThemeChanged: setTheme),
        '/wifi': (context) => const WifiControlScreen(),
        '/bluetooth': (context) => const BluetoothScreen(),
        '/vocal': (context) => const VocalScreen(),
        '/terminal': (context) => const TerminalScreen(),
        '/switch': (context) => const ESP32ControllerScreen(),
        '/pwm': (context) => const PWMControllerScreen(),
        '/camera': (context) => const EspCamWidget(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class AccueilPage extends StatefulWidget {
  final void Function(ThemeData) onThemeChanged;
  const AccueilPage({super.key, required this.onThemeChanged});

  @override
  State<AccueilPage> createState() => _AccueilPageState();
}

class _AccueilPageState extends State<AccueilPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isAuthenticated = false; // Ajouté

  @override
  void initState() {
    super.initState();
    _checkAccountOnStartup();
  }



  void _checkAccountOnStartup() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedName = prefs.getString('app_username');
    String? storedPassword = prefs.getString('app_password');
    if (storedName != null && storedPassword != null) {
      bool ok = await _showLoginDialog(storedName, storedPassword);
      setState(() {
        _isAuthenticated = ok;
      });
    } else {
      setState(() {
        _isAuthenticated = true; // Permet d'accéder à la création de compte
      });
    }
  }

  // =================== DIALOGUE POUR LE MOT DE PASSE ===================
  void _showPasswordDialog() {
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Changer le mot de passe', style: GoogleFonts.inter()),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Nouveau mot de passe',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler', style: GoogleFonts.inter()),
            ),
            ElevatedButton(
              onPressed: () async {
                if (passwordController.text.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('app_password', passwordController.text);
                  Navigator.pop(context);
                  _showSnackBar('Mot de passe enregistré');
                }
              },
              child: Text('Confirmer', style: GoogleFonts.inter()),
            ),
          ],
        );
      },
    );
  }

// =================== SYSTÈME DE VÉRIFICATION AU LANCEMENT DE LA PAGE ===================
 
  // Affiche le formulaire de création de compte si aucun compte n'existe
  void _showAccountCreationDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Créer un compte', style: GoogleFonts.inter()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Nom d\'utilisateur',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty && passwordController.text.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('app_username', nameController.text);
                  await prefs.setString('app_password', passwordController.text);
                  Navigator.pop(context);
                  _showSnackBar('Compte créé');
                }
              },
              child: Text('Créer', style: GoogleFonts.inter()),
            ),
          ],
        );
      },
    );
  }

  // Affiche le formulaire de connexion
  Future<bool> _showLoginDialog(String storedName, String storedPassword) async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    bool isAuthenticated = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Connexion', style: GoogleFonts.inter()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Nom d\'utilisateur',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (nameController.text == storedName && passwordController.text == storedPassword) {
                  isAuthenticated = true;
                  Navigator.pop(context);
                } else {
                  _showSnackBar('Nom ou mot de passe incorrect');
                }
              },
              child: Text('Se connecter', style: GoogleFonts.inter()),
            ),
          ],
        );
      },
    );
    return isAuthenticated;
  }

  // Pour changer le mot de passe, demande l'ancien mot de passe
  void _showChangePasswordDialog() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedPassword = prefs.getString('app_password');

    final TextEditingController oldPasswordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Changer le mot de passe', style: GoogleFonts.inter()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Ancien mot de passe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Nouveau mot de passe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (oldPasswordController.text == storedPassword && newPasswordController.text.isNotEmpty) {
                  await prefs.setString('app_password', newPasswordController.text);
                  Navigator.pop(context);
                  _showSnackBar('Mot de passe changé');
                } else {
                  _showSnackBar('Ancien mot de passe incorrect');
                }
              },
              child: Text('Changer', style: GoogleFonts.inter()),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Affiche le vrai contenu seulement si authentifié
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xF8FFFFFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

               // =================== EN-TÊTE ===================
// Contient le titre et les boutons de droite (caméra et paramètres)
Container(
  width: double.infinity,
  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
  decoration: BoxDecoration(
    color: Colors.blueGrey[900], //  Couleur de fond personnalisée
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // Titre de l'application (réduit avec flex si l'espace est limité)
      Expanded(
        child: Text(
          'Electro-Lab Control',
          style: GoogleFonts.interTight(
            fontSize: 24, // ✅ Légèrement réduit pour éviter les débordements
            fontWeight: FontWeight.bold,
            color: Colors.white, // ✅ Contraste élevé avec le fond
          ),
          overflow: TextOverflow.ellipsis, // ✅ Évite le débordement sur les petits écrans
        ),
      ),
      const SizedBox(width: 12),
      // Boutons Caméra et Paramètres
      Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.pushNamed(context, '/camera');
            },
            icon: const Icon(Icons.linked_camera, size: 24, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blueAccent, // ✅ Couleur personnalisée
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildSettingsButton(), // Assure-toi que ce widget a une taille raisonnable
        ],
      ),
    ],
  ),
),


                // =================== BANNIÈRE IMAGE ===================
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.25),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                       'assets/images/Microcontroller.jpg', // Remplacez par le nom exact de votre fichier
                         fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

                // =================== TITRE SECTION ===================
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Choisissez votre type de commande',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),

                // =================== GRILLE DE BOUTONS ===================
                // Contient les 6 boutons principaux de l'application
                Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 24,
                    childAspectRatio: 0.8,
                    children: [
                      // Bouton Wi-Fi
                      _buildControlButton(
                        icon: Icons.wifi,
                        color: const Color(0xFF4FC3F7),
                        label: 'Wi-Fi',
                        onTap: () => Navigator.pushNamed(context, '/wifi'),
                      ),
                      // Bouton Bluetooth
                      _buildControlButton(
                        icon: Icons.bluetooth,
                        color: const Color(0xFF1565C0),
                        label: 'Bluetooth',
                        onTap: () => Navigator.pushNamed(context, '/bluetooth'),
                      ),
                      // Bouton Vocal
                      _buildControlButton(
                        icon: Icons.mic,
                        color: Colors.purple,
                        label: 'Vocal',
                        onTap: () => Navigator.pushNamed(context, '/vocal'),
                      ),
                      // Bouton Terminal
                      _buildControlButton(
                        icon: Icons.code,
                        color: Colors.green,
                        label: 'Terminal',
                        onTap: () => Navigator.pushNamed(context, '/terminal'),
                      ),
                      // Bouton Switch
                      _buildControlButton(
                        icon: Icons.toggle_on,
                        color: Colors.orange,
                        label: 'Switch',
                        onTap: () => Navigator.pushNamed(context, '/switch'),
                      ),
                      // Bouton PWM
                      _buildControlButton(
                        icon: Icons.show_chart,
                        color: const Color(0xFFE91E63),
                        label: 'PWM',
                        onTap: () => Navigator.pushNamed(context, '/pwm'),
                      ),
                    ],
                  ),
                ),

                // =================== PIED DE PAGE ===================
                // Contient les informations sur le projet
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFB6CD49E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text(
                            'Project Bac III. UB-I.S.S.A',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.memory,
                                color: Theme.of(context).primaryColor,
                                size: 30,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Elo M.S.Claude',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =================== MÉTHODE POUR CRÉER LES BOUTONS DE COMMANDE ===================
  // Cette méthode permet de créer un bouton circulaire avec un icône et un label
  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        // Bouton circulaire
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.25),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 8),
        // Label du bouton
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

// =================== BOUTON PARAMÈTRES ===================
  Widget _buildSettingsButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings, size: 24),
      style: IconButton.styleFrom(
              backgroundColor: Colors.blueAccent, // ✅ Couleur personnalisée
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
      itemBuilder: (BuildContext context) => [
        PopupMenuItem(
          value: 'theme',
          child: Row(
            children: [
              const Icon(Icons.color_lens, color: Colors.blue),
              const SizedBox(width: 8),
              Text('Thème', style: GoogleFonts.inter()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'vibration',
          child: Row(
            children: [
              const Icon(Icons.vibration, color: Colors.green),
              const SizedBox(width: 8),
              Text('Vibration', style: GoogleFonts.inter()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'server',
          child: Row(
            children: [
              const Icon(Icons.cloud, color: Colors.orange),
              const SizedBox(width: 8),
              Text('Serveur IoT', style: GoogleFonts.inter()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'password',
          child: Row(
            children: [
              const Icon(Icons.lock, color: Colors.red),
              const SizedBox(width: 8),
              Text('Mot de passe', style: GoogleFonts.inter()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              const Icon(Icons.history, color: Colors.purple),
              const SizedBox(width: 8),
              Text('Historique', style: GoogleFonts.inter()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'about',
          child: Row(
            children: [
              const Icon(Icons.info, color: Colors.teal),
              const SizedBox(width: 8),
              Text('À propos', style: GoogleFonts.inter()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'help',
          child: Row(
            children: [
              const Icon(Icons.help, color: Colors.indigo),
              const SizedBox(width: 8),
              Text('Aide', style: GoogleFonts.inter()),
            ],
          ),
        ),
      ],
      onSelected: (String value) {
        switch (value) {
          case 'theme':
            _showThemeDialog();
            break;
          case 'vibration':
            _showSnackBar('Paramètre de vibration modifié');
            break;
          case 'server':
            _showServerModal(context);
            break;
          case 'password':
            _showPasswordMenu();
            break;
          case 'history':
            _showSnackBar('Historique des actions');
            break;
          case 'about':
            Navigator.pushNamed(context, '/aboutPage');
            break;
          case 'help':
            Navigator.pushNamed(context, '/helpPage');
            break;
        }
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      offset: const Offset(0, 50),
    );
  }

// =================== DIALOGUE POUR LE THÈME ===================
  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Changer le thème', style: GoogleFonts.inter()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_5, color: Colors.blue),
                title: Text('Clair', style: GoogleFonts.inter()),
                onTap: () {
                  Navigator.pop(context);
                  widget.onThemeChanged(
                    ThemeData(
                      brightness: Brightness.light,
                      primarySwatch: Colors.blue,
                      scaffoldBackgroundColor: Colors.white,
                      appBarTheme: const AppBarTheme(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  );
                  _showSnackBar('Thème clair appliqué');
                },
              ),
              ListTile(
                leading: const Icon(Icons.brightness_2, color: Colors.purple),
                title: Text('Sombre', style: GoogleFonts.inter()),
                onTap: () {
                  Navigator.pop(context);
                  widget.onThemeChanged(
                    ThemeData(
                      brightness: Brightness.dark,
                      primarySwatch: Colors.deepPurple,
                      scaffoldBackgroundColor: Colors.black,
                      appBarTheme: const AppBarTheme(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  );
                  _showSnackBar('Thème sombre appliqué');
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.pink),
                title: Text('Rose', style: GoogleFonts.inter()),
                onTap: () {
                  Navigator.pop(context);
                  widget.onThemeChanged(
                    ThemeData(
                      brightness: Brightness.light,
                      primarySwatch: Colors.pink,
                      scaffoldBackgroundColor: Colors.pink[50],
                      appBarTheme: const AppBarTheme(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  );
                  _showSnackBar('Thème rose appliqué');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showServerModal(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        width: MediaQuery.of(context).size.width * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              color: Colors.black.withOpacity(0.2),
            ),
          ],
        ),
        child: ServerFront(),
      ),
    ),
  );
}

  void _showPasswordMenu() async {
  final prefs = await SharedPreferences.getInstance();
  String? storedName = prefs.getString('app_username');
  String? storedPassword = prefs.getString('app_password');

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Sécurité', style: GoogleFonts.inter()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (storedName == null || storedPassword == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add),
                label: Text('Créer un compte', style: GoogleFonts.inter()),
                onPressed: () {
                  Navigator.pop(context);
                  _showAccountCreationDialog();
                },
              )
            else ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.lock_reset),
                label: Text('Changer le mot de passe', style: GoogleFonts.inter()),
                onPressed: () {
                  Navigator.pop(context);
                  _showChangePasswordDialog();
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: Text('Supprimer le compte', style: GoogleFonts.inter()),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  await prefs.remove('app_username');
                  await prefs.remove('app_password');
                  Navigator.pop(context);
                  _showSnackBar('Compte supprimé');
                },
              ),
            ],
          ],
          ),
        );
      },
    );
  }
}

  
  

// =================== WIDGET PLACEHOLDER POUR LES AUTRES PAGES ===================
class PlaceholderWidget extends StatelessWidget {
  final String title;

  const PlaceholderWidget({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title Page',
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}