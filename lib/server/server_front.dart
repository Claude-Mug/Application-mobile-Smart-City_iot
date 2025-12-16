// server_front.dart
import 'package:flutter/material.dart';
import 'server_back.dart';

class ServerFront extends StatefulWidget {
  const ServerFront({Key? key}) : super(key: key);

  @override
  _ServerFrontState createState() => _ServerFrontState();
}

class _ServerFrontState extends State<ServerFront> {
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();
  
  bool _isConnected = false;
  bool _isLoading = false;
  bool _autoRefresh = true;
  String _connectionMessage = 'Non connecté';
  List<dynamic> _messages = [];
  String _currentServerUrl = ServerBack.activeBaseUrl;
  
  @override
  void initState() {
    super.initState();
    _serverUrlController.text = ServerBack.activeBaseUrl;
    _checkConnection();
    _startAutoRefresh();
  }
  
  void _startAutoRefresh() {
    if (_autoRefresh) {
      Future.delayed(const Duration(seconds: 3), () {
        if (_autoRefresh && _isConnected) {
          _getMessages();
          _startAutoRefresh();
        }
      });
    }
  }
  
  Future<void> _checkConnection() async {
    setState(() {
      _isLoading = true;
    });
    
    final result = await ServerBack.checkServerStatus();
    
    setState(() {
      _isLoading = false;
      _isConnected = result['success'] ?? false;
      _connectionMessage = result['message'] ?? 'Erreur inconnue';
      _currentServerUrl = ServerBack.activeBaseUrl;
    });
    
    if (_isConnected) {
      _getMessages();
    }
  }
  
  Future<void> _getMessages() async {
    if (!_isConnected) return;
    
    final result = await ServerBack.getMessages();
    if (result['success'] == true) {
      setState(() {
        _messages = result['messages'] ?? [];
      });
    }
  }
  
  Future<void> _sendCommand() async {
    if (_commandController.text.isEmpty) return;
    
    setState(() {
      _isLoading = true;
    });
    
    final result = await ServerBack.sendCommand(_commandController.text);
    
    setState(() {
      _isLoading = false;
    });
    
    _showSnackBar(result['message'] ?? 'Commande traitée');
    
    if (result['success'] == true) {
      _commandController.clear();
      _getMessages();
    }
  }
  
  void _updateServerConfig() {
    final newUrl = _serverUrlController.text.trim();
    if (newUrl.isNotEmpty) {
      ServerBack.setCustomBaseUrl(newUrl);
      _showSnackBar('URL du serveur mise à jour');
      _checkConnection();
    }
  }
  
  void _resetToDefault() {
    ServerBack.resetToDefault();
    _serverUrlController.text = ServerBack.activeBaseUrl;
    _showSnackBar('URL par défaut restaurée');
    _checkConnection();
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isConnected)
                    Text(
                      'URL du serveur: $_currentServerUrl',
                      style: const TextStyle(fontSize: 12, color: Color.fromARGB(255, 2, 60, 16)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    _isConnected ? 'Connecté' : 'Déconnecté',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  Text(
                    _connectionMessage,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _checkConnection,
              iconSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(
                labelText: 'Commande',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isConnected ? _sendCommand : null,
                child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('ENVOYER'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesSection() {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Messages',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  if (_autoRefresh)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('Auto', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 20),
                    onPressed: _showServerConfigDialog,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _messages.isEmpty
                  ? Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.message, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              _isConnected ? 'Aucun message' : 'Non connecté',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Expanded(
                      child: ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.smartphone, size: 14, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(
                                      'ESP ${message['device_id'] ?? 'Inconnu'}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _formatTimestamp(message['timestamp']),
                                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  message['message']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerConfigDialog() {
    showDialog(
      barrierDismissible: false,
      barrierColor: const Color.fromARGB(64, 7, 221, 240),
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration Serveur'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL du serveur',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetToDefault,
                      child: const Text('Défaut'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('Auto Refresh', style: TextStyle(fontSize: 14)),
                      value: _autoRefresh,
                      onChanged: (value) {
                        setState(() {
                          _autoRefresh = value;
                        });
                        if (value) _startAutoRefresh();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              _updateServerConfig();
              Navigator.pop(context);
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Inconnu';
    try {
      final date = DateTime.parse(timestamp.toString()).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp.toString();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromARGB(182, 198, 200, 201),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildConnectionStatus(),
          const SizedBox(height: 12),
          _buildCommandSection(),
          const SizedBox(height: 12),
          _buildMessagesSection(),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _commandController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }
}