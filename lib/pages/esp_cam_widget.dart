import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

// Définition de FormFieldController, adapté pour être un ChangeNotifier simple.
// Il peut être utilisé pour gérer la valeur d'un champ de formulaire et notifier les écouteurs.
class FormFieldController<T> extends ChangeNotifier {
  T? _value;

  FormFieldController([T? initialValue]) : _value = initialValue;

  T? get value => _value;

  set value(T? newValue) {
    if (_value != newValue) {
      _value = newValue;
      notifyListeners();
    }
  }

  // Un validateur factice pour la démonstration.
  // Dans une application réelle, vous implémenteriez une logique de validation ici.
  FormFieldValidator<T>? asValidator(BuildContext context) {
    return (val) => null;
  }
}

// Définition de FormFieldValidator, un alias de type pour la fonction de validation.
typedef FormFieldValidator<T> = String? Function(T? value)?;

// MODIFIED FlutterFlowTheme adapté en un thème Flutter plus standard.
// Il définit les couleurs et les styles de texte de base pour l'application.
class CustomAppTheme {
  static CustomAppTheme of(BuildContext context) => CustomAppTheme();

  // Couleurs de base de l'application
  Color primaryBackground = const Color(0xFFF1F4F8);
  Color secondaryBackground = Colors.white;
  Color primary = const Color(0xFF4B39EF);
  Color secondaryText = const Color(0xFF57636C);
  Color alternate = const Color(0xFFE0E3E7);
  Color error = const Color(0xFFFF5963);
  Color primaryText = const Color(0xFF101213);

  // Styles de texte de base, utilisant GoogleFonts pour la flexibilité.
  // Les styles sont définis avec des valeurs par défaut et peuvent être surchargés.
  TextStyle get titleMedium => GoogleFonts.interTight(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: primaryText,
      );

  TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: primaryText,
      );

  TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: secondaryText,
      );

  // Méthode d'aide pour copier un style de texte existant et le modifier.
  // Utile pour des ajustements ponctuels sans redéfinir un style complet.
  TextStyle overrideTextStyle(
    TextStyle textStyle, {
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    TextDecoration? decoration,
    double? height,
    String? fontFamily, // Changé pour correspondre à TextStyle
  }) {
    return textStyle.copyWith(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      decoration: decoration,
      height: height,
      fontFamily: fontFamily,
    );
  }
}

// Dummy createModel et safeSetState pour simuler le comportement de FlutterFlow.
// Dans une application réelle, la gestion de l'état serait faite avec Provider, Riverpod, BLoC, etc.
T createModel<T extends ChangeNotifier>(BuildContext context, T Function() constructor) {
  // Simule la création et l'initialisation du modèle.
  // En production, vous utiliseriez un gestionnaire d'état comme Provider.
  return constructor();
}

void safeSetState(VoidCallback fn) {
  // Simule la mise à jour de l'état en toute sécurité.
  // En production, setState() est la méthode appropriée dans un StatefulWidget.
  fn();
}

// EspCamModel gère l'état de la page EspCamWidget.
// Il étend ChangeNotifier pour permettre aux widgets d'écouter les changements.
class EspCamModel extends ChangeNotifier {
  bool masque = false;
  bool switchValue1 = true;
  bool switchValue2 = true;
  bool switchValue3 = true;
  bool switchValue4 = true;
  bool switchValue5 = true;
  bool switchValue6 = true;
  bool switchValue7 = true;
  bool switchValue8 = true;
  bool switchValue9 = true;
  bool switchValue10 = true;
  bool switchValue11 = true;
  bool switchValue12 = true;
  bool switchValue13 = true;

  TextEditingController? textController1;
  FocusNode? textFieldFocusNode1;
  TextEditingController? textController2;
  FocusNode? textFieldFocusNode2;

  String? dropDownValue;
  // Utilisation directe de FormFieldController pour le Dropdown
  FormFieldController<String>? dropDownValueController;

  bool passwordVisibility = false;

  // Validateurs factices pour les champs de texte.
  // La logique de validation réelle serait implémentée ici.
  String? Function(String?)? get textController1Validator => (val) => null;
  String? Function(String?)? get textController2Validator => (val) => null;

  @override
  void dispose() {
    // Libère les ressources des contrôleurs de texte et des nœuds de focus.
    textController1?.dispose();
    textFieldFocusNode1?.dispose();
    textController2?.dispose();
    textFieldFocusNode2?.dispose();
    // Libère également le contrôleur du Dropdown s'il est utilisé.
    dropDownValueController?.dispose();
    super.dispose();
  }
}

// EspCamWidget est le widget principal qui affiche l'interface utilisateur.
class EspCamWidget extends StatefulWidget {
  const EspCamWidget({super.key});

  static String routeName = 'EspCam';
  static String routePath = '/espCam';

  @override
  State<EspCamWidget> createState() => _EspCamWidgetState();
}

class _EspCamWidgetState extends State<EspCamWidget> {
  late EspCamModel _model; // Instance du modèle pour gérer l'état.

  final scaffoldKey = GlobalKey<ScaffoldState>(); // Clé pour le Scaffold.
  

  @override
  void initState() {
    super.initState();
    // Initialise le modèle lors de la création de l'état du widget.
    _model = createModel(context, () => EspCamModel());

    // Action à exécuter après le rendu initial de la page.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _model.masque = !_model.masque; // Change la valeur de 'masque'.
      safeSetState(() {}); // Met à jour l'interface utilisateur.
    });

    // Initialisation des valeurs des interrupteurs.
    _model.switchValue1 = true;
    _model.switchValue2 = true;
    _model.switchValue3 = true;
    _model.switchValue4 = true;
    _model.switchValue5 = true;
    _model.switchValue6 = true;
    _model.switchValue7 = true;
    _model.switchValue8 = true;
    _model.switchValue9 = true;
    _model.switchValue10 = true;
    _model.switchValue11 = true;
    _model.switchValue12 = true;
    _model.textController1 ??= TextEditingController(text: 'ESP32-CAM-01');
    _model.textFieldFocusNode1 ??= FocusNode();

    _model.textController2 ??= TextEditingController(text: '••••••••');
    _model.textFieldFocusNode2 ??= FocusNode();

    _model.switchValue13 = true;

    // Initialisation du contrôleur pour le Dropdown.
    _model.dropDownValueController = FormFieldController<String>(_model.dropDownValue ??= '480p');
  }

  @override
  void dispose() {
    // Libère les ressources du modèle lorsque le widget est supprimé de l'arbre.
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Obtient une instance du thème personnalisé pour accéder aux couleurs et styles.
    final theme = CustomAppTheme.of(context);

    return GestureDetector(
      // Ferme le clavier lorsque l'utilisateur tape en dehors des champs de texte.
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground, // Couleur de fond du Scaffold.
        appBar: AppBar(
          backgroundColor: theme.primary, // Couleur de fond de l'AppBar.
          automaticallyImplyLeading: false, // Ne pas afficher le bouton retour par défaut.
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 24,
            ),
            onPressed: () {
              Navigator.of(context).pop(); // Revenir à la page précédente.
            },
          ),
          title: Text(
            'ESP32-CAM Control',
            // Utilisation du style titleMedium du thème, puis surcharge avec GoogleFonts.interTight
            style: theme.overrideTextStyle(
              theme.titleMedium,
              fontFamily: GoogleFonts.interTight().fontFamily,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.0,
            ),
          ),
          actions: [
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
                  child: IconButton(
                    icon: const Icon(
                      Icons.wifi,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      debugPrint('IconButton WiFi pressed ...');
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
                  child: IconButton(
                    icon: const Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      debugPrint('IconButton Settings pressed ...');
                    },
                  ),
                ),
              ],
            ),
          ],
          centerTitle: true, // Centre le titre de l'AppBar.
          elevation: 0, // Pas d'ombre sous l'AppBar.
        ),
        body: SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Section pour l'aperçu du streaming (désactivé ici).
                  Container(
                    width: double.infinity,
                    height: 240,
                    decoration: BoxDecoration(
                      color: theme.secondaryBackground,
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 5,
                          color: Color.fromRGBO(0, 0, 0, 0.25),
                          offset: Offset(0, 2),
                        )
                      ],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 8),
                            child: Icon(
                              Icons.videocam_off,
                              color: theme.secondaryText,
                              size: 48,
                            ),
                          ),
                          Text(
                            'Streaming désactivé',
                            textAlign: TextAlign.center,
                            style: theme.overrideTextStyle(
                              theme.bodyMedium,
                              fontFamily: GoogleFonts.inter().fontFamily,
                              color: theme.secondaryText,
                              letterSpacing: 0.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Carte pour le contrôle de la caméra.
                  Card(
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    color: const Color(0xFFDAD8D8),
                    child: Visibility(
                      visible: _model.masque == true, // Visibilité contrôlée par le modèle.
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
                                        child: Icon(
                                          Icons.videocam,
                                          color: theme.primary,
                                          size: 24,
                                        ),
                                      ),
                                      Text(
                                        'Contrôle Caméra',
                                        style: theme.overrideTextStyle(
                                          theme.titleMedium,
                                          fontFamily: GoogleFonts.interTight().fontFamily,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.expand_more,
                                      color: theme.secondaryText,
                                      size: 24,
                                    ),
                                    onPressed: () {
                                      safeSetState(() {}); // Mettre à jour l'état (pour un effet d'expansion/rétraction si implémenté).
                                    },
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 16),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: const Color.fromRGBO(0, 0, 0, 0.12),
                                ),
                              ),
                              // Liste des interrupteurs pour les options de la caméra.
                              // Chaque interrupteur est dans une Row avec un Text pour le libellé.
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Activer le streaming en direct',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue1,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue1 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Activer le Flash LED',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue2,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue2 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Activer la détection de mouvement',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue3,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue3 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Enregistrement vidéo automatique',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue4,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue4 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Mode Nuit (IR)',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue5,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue5 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Photos périodiques',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue6,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue6 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Envoi auto vers carte SD/serveur',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    Switch(
                                      value: _model.switchValue7,
                                      onChanged: (newValue) {
                                        safeSetState(() => _model.switchValue7 = newValue);
                                      },
                                      activeColor: theme.primary,
                                      inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Résolution de la caméra',
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        letterSpacing: 0.0,
                                      ),
                                    ),
                                    // Dropdown pour la résolution de la caméra.
                                    // Utilise DropdownButtonFormField de Flutter natif.
                                    DropdownButtonFormField<String>(
                                      value: _model.dropDownValue,
                                      items: const <String>['240p', '480p', '720p', '1080p']
                                          .map<DropdownMenuItem<String>>((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value, style: theme.bodyMedium.copyWith(color: const Color(0xFFF0F6FB))),
                                        );
                                      }).toList(),
                                      onChanged: (String? newValue) {
                                        safeSetState(() {
                                          _model.dropDownValue = newValue;
                                          _model.dropDownValueController?.value = newValue; // Mettre à jour le contrôleur
                                        });
                                      },
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color.fromRGBO(22, 22, 23, 0.67),
                                        contentPadding: EdgeInsets.zero,
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: theme.alternate,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: theme.primary,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      style: theme.overrideTextStyle(
                                        theme.bodyMedium,
                                        fontFamily: GoogleFonts.inter().fontFamily,
                                        color: const Color(0xFFF0F6FB), // Couleur du texte dans le Dropdown
                                        fontSize: 14,
                                        letterSpacing: 0.0,
                                      ),
                                      icon: Icon(
                                        Icons.keyboard_arrow_down,
                                        color: theme.primaryText,
                                        size: 18,
                                      ),
                                      elevation: 2,
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Bouton "Prendre une photo" utilisant ElevatedButton.
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        debugPrint('Bouton "Prendre une photo" pressé ...');
                                      },
                                      icon: const Icon(
                                        Icons.photo_camera,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      label: Text(
                                        'Prendre une photo',
                                        style: theme.overrideTextStyle(
                                          theme.bodyMedium,
                                          fontFamily: GoogleFonts.inter().fontFamily,
                                          color: Colors.white,
                                          letterSpacing: 0.0,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(200, 40),
                                        padding: const EdgeInsets.all(8),
                                        backgroundColor: theme.primary,
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: const BorderSide(color: Colors.transparent, width: 1),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ].divide(const SizedBox(height: 16)), // Ajoute un espacement entre les enfants.
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Carte pour la gestion du stockage.
                  Card(
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
                                    child: Icon(
                                      Icons.sd_card,
                                      color: theme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  Text(
                                    'Gestion du stockage',
                                    style: theme.overrideTextStyle(
                                      theme.titleMedium,
                                      fontFamily: GoogleFonts.interTight().fontFamily,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.expand_more,
                                  color: theme.secondaryText,
                                  size: 24,
                                ),
                                onPressed: () {
                                  debugPrint('IconButton pressed ...');
                                },
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 16),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: const Color.fromRGBO(0, 0, 0, 0.12),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Text(
                                    'Espace disponible',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  // Barre de progression simulée pour l'espace de stockage.
                                  Container(
                                    width: double.infinity,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: const Color.fromRGBO(0, 0, 0, 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Align( // Utilisation d'Align pour positionner la barre interne
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: 150, // Largeur fixe pour simuler l'espace utilisé.
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: theme.primary,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '2.3 Go utilisés',
                                        style: theme.overrideTextStyle(
                                          theme.bodySmall,
                                          fontFamily: GoogleFonts.inter().fontFamily,
                                          letterSpacing: 0.0,
                                        ),
                                      ),
                                      Text(
                                        '5.7 Go disponibles',
                                        style: theme.overrideTextStyle(
                                          theme.bodySmall,
                                          fontFamily: GoogleFonts.inter().fontFamily,
                                          letterSpacing: 0.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ].divide(const SizedBox(height: 8)),
                              ),
                              // Interrupteurs pour l'enregistrement sur carte SD et la synchronisation cloud.
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Enregistrer photos sur carte SD',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  Switch(
                                    value: _model.switchValue8,
                                    onChanged: (newValue) {
                                      safeSetState(() => _model.switchValue8 = newValue);
                                    },
                                    activeColor: theme.primary,
                                    inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Enregistrer vidéos sur carte SD',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  Switch(
                                    value: _model.switchValue9,
                                    onChanged: (newValue) {
                                      safeSetState(() => _model.switchValue9 = newValue);
                                    },
                                    activeColor: theme.primary,
                                    inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Synchronisation auto avec cloud',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  Switch(
                                    value: _model.switchValue10,
                                    onChanged: (newValue) {
                                      safeSetState(() => _model.switchValue10 = newValue);
                                    },
                                    activeColor: theme.primary,
                                    inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                  ),
                                ],
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Text(
                                    'Fichiers enregistrés',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  // Liste des fichiers enregistrés simulée avec ListView.
                                  Container(
                                    width: double.infinity,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: const Color.fromRGBO(0, 0, 0, 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListView(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      scrollDirection: Axis.vertical,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: ListTile(
                                            title: Text(
                                              'IMG_20230615_153042.jpg',
                                              style: theme.overrideTextStyle(
                                                theme.bodyMedium,
                                                fontFamily: GoogleFonts.inter().fontFamily,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '15/06/2023 15:30',
                                              style: theme.overrideTextStyle(
                                                theme.bodySmall,
                                                fontFamily: GoogleFonts.inter().fontFamily,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                            dense: false,
                                          ),
                                        ),
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: const Color.fromRGBO(0, 0, 0, 0.06),
                                        ),
                                        Material(
                                          color: Colors.transparent,
                                          child: ListTile(
                                            title: Text(
                                              'VID_20230615_160023.mp4',
                                              style: theme.overrideTextStyle(
                                                theme.bodyMedium,
                                                fontFamily: GoogleFonts.inter().fontFamily,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '15/06/2023 16:00',
                                              style: theme.overrideTextStyle(
                                                theme.bodySmall,
                                                fontFamily: GoogleFonts.inter().fontFamily,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                            dense: false,
                                          ),
                                        ),
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: const Color.fromRGBO(0, 0, 0, 0.06),
                                        ),
                                        Material(
                                          color: Colors.transparent,
                                          child: ListTile(
                                            title: Text(
                                              'IMG_20230615_172135.jpg',
                                              style: theme.overrideTextStyle(
                                                theme.bodyMedium,
                                                fontFamily: GoogleFonts.inter().fontFamily,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '15/06/2023 17:21',
                                              style: theme.overrideTextStyle(
                                                theme.bodySmall,
                                                fontFamily: GoogleFonts.inter().fontFamily,
                                                letterSpacing: 0.0,
                                              ),
                                            ),
                                            dense: false,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ].divide(const SizedBox(height: 8)),
                              ),
                              // Bouton "Formater la carte SD" avec une couleur d'erreur.
                              ElevatedButton(
                                onPressed: () {
                                  debugPrint('Bouton "Formater la carte SD" pressé ...');
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(200, 40),
                                  padding: const EdgeInsets.all(8),
                                  backgroundColor: theme.error,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Colors.transparent, width: 1),
                                  ),
                                ),
                                child: Text(
                                  'Formater la carte SD',
                                  style: theme.overrideTextStyle(
                                    theme.bodyMedium,
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    color: Colors.white,
                                    letterSpacing: 0.0,
                                  ),
                                ),
                              ),
                            ].divide(const SizedBox(height: 16)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Carte pour les paramètres généraux.
                  Card(
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
                                    child: Icon(
                                      Icons.settings,
                                      color: theme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  Text(
                                    'Paramètres',
                                    style: theme.overrideTextStyle(
                                      theme.titleMedium,
                                      fontFamily: GoogleFonts.interTight().fontFamily,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.expand_more,
                                  color: theme.secondaryText,
                                  size: 24,
                                ),
                                onPressed: () {
                                  debugPrint('IconButton pressed ...');
                                },
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 16),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: const Color.fromRGBO(0, 0, 0, 0.12),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              // Interrupteurs pour les modes Wi-Fi.
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Mode Wi-Fi local',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  Switch(
                                    value: _model.switchValue11,
                                    onChanged: (newValue) {
                                      safeSetState(() => _model.switchValue11 = newValue);
                                    },
                                    activeColor: theme.primary,
                                    inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Mode point d\'accès (AP)',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  Switch(
                                    value: _model.switchValue12,
                                    onChanged: (newValue) {
                                      safeSetState(() => _model.switchValue12 = newValue);
                                    },
                                    activeColor: theme.primary,
                                    inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                  ),
                                ],
                              ),
                              // Champ de texte pour le nom de l'appareil.
                              TextFormField(
                                controller: _model.textController1,
                                focusNode: _model.textFieldFocusNode1,
                                autofocus: false,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Nom de l\'appareil',
                                  labelStyle: theme.overrideTextStyle(
                                    theme.bodyMedium,
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    letterSpacing: 0.0,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.alternate,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.primary,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.error,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.error,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                style: theme.overrideTextStyle(
                                  theme.bodyMedium,
                                  fontFamily: GoogleFonts.inter().fontFamily,
                                  letterSpacing: 0.0,
                                ),
                                cursorColor: theme.primary,
                                validator: _model.textController1Validator,
                              ),
                              // Champ de texte pour le mot de passe avec bascule de visibilité.
                              TextFormField(
                                controller: _model.textController2,
                                focusNode: _model.textFieldFocusNode2,
                                autofocus: false,
                                obscureText: !_model.passwordVisibility,
                                decoration: InputDecoration(
                                  labelText: 'Mot de passe',
                                  labelStyle: theme.overrideTextStyle(
                                    theme.bodyMedium,
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    letterSpacing: 0.0,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.alternate,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.primary,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.error,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: theme.error,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  suffixIcon: InkWell(
                                    onTap: () => safeSetState(
                                      () => _model.passwordVisibility = !_model.passwordVisibility,
                                    ),
                                    focusNode: FocusNode(skipTraversal: true),
                                    child: Icon(
                                      _model.passwordVisibility ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                style: theme.overrideTextStyle(
                                  theme.bodyMedium,
                                  fontFamily: GoogleFonts.inter().fontFamily,
                                  letterSpacing: 0.0,
                                ),
                                cursorColor: theme.primary,
                                validator: _model.textController2Validator, // Note: Le code original avait textController1Validator ici. Corrigé.
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Mode veille (tout désactiver)',
                                    style: theme.overrideTextStyle(
                                      theme.bodyMedium,
                                      fontFamily: GoogleFonts.inter().fontFamily,
                                      letterSpacing: 0.0,
                                    ),
                                  ),
                                  Switch(
                                    value: _model.switchValue13,
                                    onChanged: (newValue) {
                                      safeSetState(() => _model.switchValue13 = newValue);
                                    },
                                    activeColor: theme.primary,
                                    inactiveTrackColor: const Color.fromRGBO(0, 0, 0, 0.12),
                                  ),
                                ],
                              ),
                              // Bouton pour redémarrer le module ESP32-CAM.
                              ElevatedButton(
                                onPressed: () {
                                  debugPrint('Bouton "Redémarrer" pressé ...');
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 40),
                                  padding: const EdgeInsets.all(8),
                                  backgroundColor: theme.primary,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Colors.transparent, width: 1),
                                  ),
                                ),
                                child: Text(
                                  'Redémarrer le module ESP32-CAM',
                                  style: theme.overrideTextStyle(
                                    theme.bodyMedium,
                                    fontFamily: GoogleFonts.inter().fontFamily,
                                    color: Colors.white,
                                    letterSpacing: 0.0,
                                  ),
                                ),
                              ),
                            ].divide(const SizedBox(height: 16)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ].divide(const SizedBox(height: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Extension pour simuler la méthode .divide utilisée dans FlutterFlow,
// permettant d'insérer un widget séparateur entre chaque élément d'une liste.
extension ListDivider on List<Widget> {
  List<Widget> divide(Widget divider) {
    if (isEmpty) return [];
    final List<Widget> result = [first];
    for (int i = 1; i < length; i++) {
      result.add(divider);
      result.add(this[i]);
    }
    return result;
  }
}