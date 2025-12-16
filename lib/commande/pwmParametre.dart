//[file name]: pwmParametre.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:claude_iot/pages/pwm_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Nouveaux enums pour les paramètres avancés
enum PWMProfile { linear, logarithmic, exponential, custom }
enum ChannelCategory { lighting, motor, fan, heater, generic, sensor, custom }

// Classe pour les paramètres généraux PWM
class PWMGeneralSettings {
  final int defaultFrequency;
  final int defaultResolution;
  final int defaultMinValue;
  final int defaultMaxValue;
  final bool safetyEnabled;
  final bool autoSaveEnabled;
  final bool confirmBeforeSend;
  final bool sendFrequencyByDefault;
  final bool sendResolutionByDefault;

  const PWMGeneralSettings({
    this.defaultFrequency = 1000,
    this.defaultResolution = 8,
    this.defaultMinValue = 0,
    this.defaultMaxValue = 255,
    this.safetyEnabled = true,
    this.autoSaveEnabled = true,
    this.confirmBeforeSend = false,
    this.sendFrequencyByDefault = false,
    this.sendResolutionByDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'defaultFrequency': defaultFrequency,
      'defaultResolution': defaultResolution,
      'defaultMinValue': defaultMinValue,
      'defaultMaxValue': defaultMaxValue,
      'safetyEnabled': safetyEnabled,
      'autoSaveEnabled': autoSaveEnabled,
      'confirmBeforeSend': confirmBeforeSend,
      'sendFrequencyByDefault': sendFrequencyByDefault,
      'sendResolutionByDefault': sendResolutionByDefault,
    };
  }

  factory PWMGeneralSettings.fromMap(Map<String, dynamic> map) {
    return PWMGeneralSettings(
      defaultFrequency: map['defaultFrequency'] ?? 1000,
      defaultResolution: map['defaultResolution'] ?? 8,
      defaultMinValue: map['defaultMinValue'] ?? 0,
      defaultMaxValue: map['defaultMaxValue'] ?? 255,
      safetyEnabled: map['safetyEnabled'] ?? true,
      autoSaveEnabled: map['autoSaveEnabled'] ?? true,
      confirmBeforeSend: map['confirmBeforeSend'] ?? false,
      sendFrequencyByDefault: map['sendFrequencyByDefault'] ?? false,
      sendResolutionByDefault: map['sendResolutionByDefault'] ?? false,
    );
  }

  PWMGeneralSettings copyWith({
    int? defaultFrequency,
    int? defaultResolution,
    int? defaultMinValue,
    int? defaultMaxValue,
    bool? safetyEnabled,
    bool? autoSaveEnabled,
    bool? confirmBeforeSend,
    bool? sendFrequencyByDefault,
    bool? sendResolutionByDefault,
  }) {
    return PWMGeneralSettings(
      defaultFrequency: defaultFrequency ?? this.defaultFrequency,
      defaultResolution: defaultResolution ?? this.defaultResolution,
      defaultMinValue: defaultMinValue ?? this.defaultMinValue,
      defaultMaxValue: defaultMaxValue ?? this.defaultMaxValue,
      safetyEnabled: safetyEnabled ?? this.safetyEnabled,
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      confirmBeforeSend: confirmBeforeSend ?? this.confirmBeforeSend,
      sendFrequencyByDefault: sendFrequencyByDefault ?? this.sendFrequencyByDefault,
      sendResolutionByDefault: sendResolutionByDefault ?? this.sendResolutionByDefault,
    );
  }
}

class PWMParametreModal extends StatefulWidget {
  final bool editMode;
  final Function(bool) onEditModeChanged;
  final List<PWMChannel> pwmChannels;
  final Function(int, PWMChannel) onChannelUpdated;
  final Function() onAddChannel;
  final Function(int) onDeleteChannel;

  const PWMParametreModal({
    Key? key,
    required this.editMode,
    required this.onEditModeChanged,
    required this.pwmChannels,
    required this.onChannelUpdated,
    required this.onAddChannel,
    required this.onDeleteChannel,
  }) : super(key: key);

  @override
  State<PWMParametreModal> createState() => _PWMParametreModalState();
}

class _PWMParametreModalState extends State<PWMParametreModal> {
  final TextEditingController _defaultFreqController = TextEditingController();
  final TextEditingController _defaultResController = TextEditingController();
  final TextEditingController _defaultMinController = TextEditingController();
  final TextEditingController _defaultMaxController = TextEditingController();
  
  PWMGeneralSettings _generalSettings = const PWMGeneralSettings();
  bool _settingsLoaded = false;
  
  // Contrôleurs pour l'édition des canaux
  final Map<int, TextEditingController> _channelNameControllers = {};
  final Map<int, TextEditingController> _channelPinControllers = {};
  final Map<int, TextEditingController> _channelFreqControllers = {};
  final Map<int, TextEditingController> _channelResControllers = {};
  final Map<int, TextEditingController> _channelMinControllers = {};
  final Map<int, TextEditingController> _channelMaxControllers = {};
  final Map<int, bool> _channelSendFrequency = {};
  final Map<int, bool> _channelSendResolution = {};

  @override
  void initState() {
    super.initState();
    _loadGeneralSettings();
    _initializeChannelControllers();
  }

  @override
  void didUpdateWidget(PWMParametreModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pwmChannels.length != widget.pwmChannels.length) {
      _initializeChannelControllers();
    }
  }

  @override
  void dispose() {
    _defaultFreqController.dispose();
    _defaultResController.dispose();
    _defaultMinController.dispose();
    _defaultMaxController.dispose();
    _disposeChannelControllers();
    super.dispose();
  }

  void _initializeChannelControllers() {
    // Dispose des anciens contrôleurs
    _disposeChannelControllers();
    
    // Crée les nouveaux contrôleurs pour chaque canal
    for (int i = 0; i < widget.pwmChannels.length; i++) {
      final channel = widget.pwmChannels[i];
      _channelNameControllers[i] = TextEditingController(text: channel.name);
      _channelPinControllers[i] = TextEditingController(text: channel.pin.toString());
      _channelFreqControllers[i] = TextEditingController(text: channel.frequency.toString());
      _channelResControllers[i] = TextEditingController(text: channel.resolution.toString());
      _channelMinControllers[i] = TextEditingController(text: channel.minValue.toString());
      _channelMaxControllers[i] = TextEditingController(text: channel.maxValue.toString());
      _channelSendFrequency[i] = channel.sendFrequency;
      _channelSendResolution[i] = channel.sendResolution;
    }
  }

  void _disposeChannelControllers() {
    for (var controller in _channelNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _channelPinControllers.values) {
      controller.dispose();
    }
    for (var controller in _channelFreqControllers.values) {
      controller.dispose();
    }
    for (var controller in _channelResControllers.values) {
      controller.dispose();
    }
    for (var controller in _channelMinControllers.values) {
      controller.dispose();
    }
    for (var controller in _channelMaxControllers.values) {
      controller.dispose();
    }
    _channelNameControllers.clear();
    _channelPinControllers.clear();
    _channelFreqControllers.clear();
    _channelResControllers.clear();
    _channelMinControllers.clear();
    _channelMaxControllers.clear();
    _channelSendFrequency.clear();
    _channelSendResolution.clear();
  }

  Future<void> _loadGeneralSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('pwm_general_settings');
      
      if (settingsJson != null) {
        final Map<String, dynamic> settingsMap = Map<String, dynamic>.from(
          const JsonDecoder().convert(settingsJson)
        );
        setState(() {
          _generalSettings = PWMGeneralSettings.fromMap(settingsMap);
          _settingsLoaded = true;
        });
      } else {
        setState(() {
          _settingsLoaded = true;
        });
      }
      
      // Initialiser les contrôleurs avec les valeurs chargées
      _defaultFreqController.text = _generalSettings.defaultFrequency.toString();
      _defaultResController.text = _generalSettings.defaultResolution.toString();
      _defaultMinController.text = _generalSettings.defaultMinValue.toString();
      _defaultMaxController.text = _generalSettings.defaultMaxValue.toString();
    } catch (e) {
      print('Erreur chargement paramètres: $e');
      setState(() {
        _settingsLoaded = true;
      });
    }
  }

  Future<void> _saveGeneralSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = const JsonEncoder().convert(_generalSettings.toMap());
      await prefs.setString('pwm_general_settings', settingsJson);
    } catch (e) {
      print('Erreur sauvegarde paramètres: $e');
    }
  }

  void _updateGeneralSettings() {
    final newSettings = _generalSettings.copyWith(
      defaultFrequency: int.tryParse(_defaultFreqController.text) ?? _generalSettings.defaultFrequency,
      defaultResolution: int.tryParse(_defaultResController.text) ?? _generalSettings.defaultResolution,
      defaultMinValue: int.tryParse(_defaultMinController.text) ?? _generalSettings.defaultMinValue,
      defaultMaxValue: int.tryParse(_defaultMaxController.text) ?? _generalSettings.defaultMaxValue,
    );
    
    setState(() {
      _generalSettings = newSettings;
    });
    _saveGeneralSettings();
  }

  void _updateChannelFromControllers(int index) {
    if (index >= widget.pwmChannels.length) return;
    
    final newChannel = PWMChannel(
      id: widget.pwmChannels[index].id,
      name: _channelNameControllers[index]?.text ?? widget.pwmChannels[index].name,
      icon: widget.pwmChannels[index].icon,
      minValue: int.tryParse(_channelMinControllers[index]?.text ?? '') ?? widget.pwmChannels[index].minValue,
      maxValue: int.tryParse(_channelMaxControllers[index]?.text ?? '') ?? widget.pwmChannels[index].maxValue,
      currentValue: widget.pwmChannels[index].currentValue,
      pin: int.tryParse(_channelPinControllers[index]?.text ?? '') ?? widget.pwmChannels[index].pin,
      frequency: int.tryParse(_channelFreqControllers[index]?.text ?? '') ?? widget.pwmChannels[index].frequency,
      resolution: int.tryParse(_channelResControllers[index]?.text ?? '') ?? widget.pwmChannels[index].resolution,
      sendFrequency: _channelSendFrequency[index] ?? false,
      sendResolution: _channelSendResolution[index] ?? false,
    );
    
    widget.onChannelUpdated(index, newChannel);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête fixe
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Configuration PWM Avancée',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Mode édition avec effet immédiat - TOUJOURS VISIBLE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.editMode 
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.editMode ? '🔧 Mode Édition Actif' : '👁️ Mode Visualisation',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: widget.editMode ? Colors.orange : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.editMode 
                              ? 'Vous pouvez modifier la configuration des canaux'
                              : 'Activez le mode édition pour modifier les canaux',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: widget.editMode,
                    onChanged: widget.onEditModeChanged,
                    activeColor: Colors.orange,
                  ),
                ],
              ),
            ),
            
            // Contenu défilable
            Expanded(
              child: _settingsLoaded 
                  ? DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          // Onglets
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                            ),
                            child: TabBar(
                              labelColor: Theme.of(context).colorScheme.primary,
                              unselectedLabelColor: Colors.grey.shade600,
                              indicatorColor: Theme.of(context).colorScheme.primary,
                              tabs: const [
                                Tab(
                                  icon: Icon(Icons.settings, size: 18),
                                  text: 'Paramètres',
                                ),
                                Tab(
                                  icon: Icon(Icons.tune, size: 18),
                                  text: 'Canaux PWM',
                                ),
                              ],
                            ),
                          ),
                          
                          // Contenu des onglets
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Onglet 1: Paramètres généraux
                                SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      _buildGeneralSettingsSection(),
                                      const SizedBox(height: 16),
                                      _buildSafetySettingsSection(),
                                      const SizedBox(height: 16),
                                      _buildCommandSettingsSection(),
                                    ],
                                  ),
                                ),
                                
                                // Onglet 2: Canaux PWM
                                widget.editMode 
                                    ? _buildChannelsSection()
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.edit_off,
                                              size: 48,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Mode édition désactivé',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Activez le mode édition pour modifier les canaux',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            ElevatedButton(
                                              onPressed: () => widget.onEditModeChanged(true),
                                              child: const Text('Activer le mode édition'),
                                            ),
                                          ],
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            
            // Boutons d'action fixes en bas
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _updateGeneralSettings();
                        Navigator.pop(context);
                      },
                      child: const Text('Appliquer'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettingsSection() {
  return Card(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Paramètres Généraux',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Nouvelle disposition responsive
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 400;
              return GridView.count(
                crossAxisCount: isWide ? 2 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isWide ? 4 : 3, // Ajusté pour mieux s'adapter
                children: [
                  _buildEnhancedEditableSetting(
                    'Fréquence par défaut (Hz)',
                    _defaultFreqController,
                    Icons.speed,
                    '1000',
                  ),
                  _buildEnhancedEditableSetting(
                    'Résolution par défaut (bits)',
                    _defaultResController,
                    Icons.memory,
                    '8',
                  ),
                  _buildEnhancedEditableSetting(
                    'Valeur minimale',
                    _defaultMinController,
                    Icons.arrow_downward,
                    '0',
                  ),
                  _buildEnhancedEditableSetting(
                    'Valeur maximale',
                    _defaultMaxController,
                    Icons.arrow_upward,
                    '255',
                  ),
                ],
              );
            },
          ),
          
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          
          // Paramètres booléens améliorés
          Text(
            'Options système:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          
          Wrap(
            spacing: 4,
            runSpacing: 12,
            children: [
              _buildEnhancedCheckboxTile(
                'Sécurité activée',
                'Protections automatiques',
                _generalSettings.safetyEnabled,
                (value) {
                  setState(() {
                    _generalSettings = _generalSettings.copyWith(safetyEnabled: value);
                  });
                  _saveGeneralSettings();
                },
                Icons.security,
              ),
              _buildEnhancedCheckboxTile(
                'Sauvegarde auto',
                'Sauvegarde automatique',
                _generalSettings.autoSaveEnabled,
                (value) {
                  setState(() {
                    _generalSettings = _generalSettings.copyWith(autoSaveEnabled: value);
                  });
                  _saveGeneralSettings();
                },
                Icons.save,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
  Widget _buildSafetySettingsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Paramètres de Sécurité',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            CheckboxListTile(
              title: const Text('Confirmation avant envoi'),
              subtitle: const Text('Demander confirmation pour les commandes critiques'),
              value: _generalSettings.confirmBeforeSend,
              onChanged: (value) {
                setState(() {
                  _generalSettings = _generalSettings.copyWith(confirmBeforeSend: value);
                });
                _saveGeneralSettings();
              },
            ),
            
            const SizedBox(height: 12),
            
            Text(
              'Limites de sécurité globales:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: const Text('Fréquence max: 20kHz'),
                  backgroundColor: Colors.orange.shade100,
                ),
                Chip(
                  label: const Text('Résolution max: 16 bits'),
                  backgroundColor: Colors.orange.shade100,
                ),
                Chip(
                  label: const Text('Température: 85°C'),
                  backgroundColor: Colors.red.shade100,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandSettingsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.send, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Format des Commandes',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Text(
              'Par défaut, les commandes sont envoyées au format simple: P5:255\n'
              'Vous pouvez activer l\'envoi de la fréquence et/ou de la résolution si nécessaire.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            
            const SizedBox(height: 16),
            
            CheckboxListTile(
              title: const Text('Inclure la fréquence par défaut'),
              subtitle: const Text('Format: P5:255:1000'),
              value: _generalSettings.sendFrequencyByDefault,
              onChanged: (value) {
                setState(() {
                  _generalSettings = _generalSettings.copyWith(sendFrequencyByDefault: value);
                });
                _saveGeneralSettings();
              },
            ),
            
            CheckboxListTile(
              title: const Text('Inclure la résolution par défaut'),
              subtitle: const Text('Format: P5:255::8'),
              value: _generalSettings.sendResolutionByDefault,
              onChanged: (value) {
                setState(() {
                  _generalSettings = _generalSettings.copyWith(sendResolutionByDefault: value);
                });
                _saveGeneralSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsSection() {
    return Column(
      children: [
        // En-tête des canaux
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Canaux PWM (${widget.pwmChannels.length})',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nouveau Canal'),
                onPressed: widget.onAddChannel,
              ),
            ],
          ),
        ),
        
        // Liste des canaux avec défilement
        Expanded(
          child: widget.pwmChannels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.extension_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun canal configuré',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: widget.onAddChannel,
                        child: const Text('Ajouter un canal'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.pwmChannels.length,
                  itemBuilder: (context, index) {
                    return _buildChannelCard(widget.pwmChannels[index], index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(PWMChannel channel, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(channel.icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          channel.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'GPIO ${channel.pin} • ${channel.frequency}Hz • ${channel.resolution}bits',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () {
            _showDeleteChannelDialog(index);
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildChannelForm(channel, index),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelForm(PWMChannel channel, int index) {
  return SingleChildScrollView( // Ajout du défilement pour éviter le dépassement
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête amélioré
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
  children: [
    Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 8),

    // 🔑 La clé est ici : Envelopper le Text dans Expanded
    Expanded( 
      child: Text(
        'Configuration du Canal - ${channel.name}',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        // S'assurer qu'il ne prend qu'une seule ligne
        maxLines: 1, 
        // Ceci fonctionne maintenant que la largeur est contrainte par Expanded
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
),
        ),
        
        // Grille responsive améliorée
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            return GridView.count(
              crossAxisCount: isWide ? 2 : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: isWide ? 3 : 2.8,
              children: [
                _buildEnhancedChannelField('Nom du canal', _channelNameControllers[index]!, Icons.label, 'LED Rouge'),
                _buildEnhancedChannelField('GPIO', _channelPinControllers[index]!, Icons.electrical_services, '5'),
                _buildEnhancedChannelField('Fréquence (Hz)', _channelFreqControllers[index]!, Icons.speed, '1000'),
                _buildEnhancedChannelField('Résolution (bits)', _channelResControllers[index]!, Icons.memory, '8'),
                _buildEnhancedChannelField('Valeur Min', _channelMinControllers[index]!, Icons.arrow_downward, '0'),
                _buildEnhancedChannelField('Valeur Max', _channelMaxControllers[index]!, Icons.arrow_upward, '255'),
              ],
            );
          },
        ),
        
        const SizedBox(height: 20),
        
        // Section paramètres d'envoi améliorée
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.send, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Format des Commandes',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                _buildEnhancedCheckboxTile(
                  'Inclure la fréquence',
                  'Format: P${channel.pin}:255:${channel.frequency}',
                  _channelSendFrequency[index] ?? false,
                  (value) {
                    setState(() {
                      _channelSendFrequency[index] = value ?? false;
                    });
                  },
                  Icons.speed,
                  dense: true,
                ),
                
                _buildEnhancedCheckboxTile(
                  'Inclure la résolution',
                  'Format: P${channel.pin}:255::${channel.resolution}',
                  _channelSendResolution[index] ?? false,
                  (value) {
                    setState(() {
                      _channelSendResolution[index] = value ?? false;
                    });
                  },
                  Icons.memory,
                  dense: true,
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Boutons d'action améliorés
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Réinitialiser'),
                onPressed: () {
                  _resetChannelForm(index, channel);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Sauvegarder'),
                onPressed: () {
                  _updateChannelFromControllers(index);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Canal ${channel.name} mis à jour'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildEnhancedEditableSetting(String label, TextEditingController controller, IconData icon, String hint) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        onChanged: (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateGeneralSettings();
          });
        },
      ),
    ],
  );
}

Widget _buildEnhancedChannelField(String label, TextEditingController controller, IconData icon, String hint) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    ],
  );
}

Widget _buildEnhancedCheckboxTile(String title, String subtitle, bool value, Function(bool?) onChanged, IconData icon, {bool dense = false}) {
  return Container(
    decoration: BoxDecoration(
      color: value ? Theme.of(context).colorScheme.primary.withOpacity(0.05) : null,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: value ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : Colors.transparent,
      ),
    ),
    child: CheckboxListTile(
      title: Text(title, style: TextStyle(fontSize: dense ? 14 : 15)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: dense ? 12 : 13)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 0 : 4),
      secondary: Icon(icon, size: dense ? 18 : 20, color: Theme.of(context).colorScheme.primary),
      controlAffinity: ListTileControlAffinity.leading,
    ),
  );
}

void _resetChannelForm(int index, PWMChannel originalChannel) {
  setState(() {
    _channelNameControllers[index]!.text = originalChannel.name;
    _channelPinControllers[index]!.text = originalChannel.pin.toString();
    _channelFreqControllers[index]!.text = originalChannel.frequency.toString();
    _channelResControllers[index]!.text = originalChannel.resolution.toString();
    _channelMinControllers[index]!.text = originalChannel.minValue.toString();
    _channelMaxControllers[index]!.text = originalChannel.maxValue.toString();
    _channelSendFrequency[index] = originalChannel.sendFrequency;
    _channelSendResolution[index] = originalChannel.sendResolution;
  });
}

  void _showDeleteChannelDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le canal'),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer le canal "${widget.pwmChannels[index].name}" ?',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              widget.onDeleteChannel(index);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Canal ${widget.pwmChannels[index].name} supprimé'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}