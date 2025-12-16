import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:permission_handler/permission_handler.dart';

enum ScanType { ble, reactiveBle }

class SimpleDevice {
  final String id;
  final String name;
  final int rssi;
  final ScanType type;
  SimpleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.type,
  });
}

class BluetoothScanPage extends StatefulWidget {
  final Duration scanDuration;
  final bool showAppBar;
  final Widget? title;
  final bool autoStart;

  const BluetoothScanPage({
    this.scanDuration = const Duration(seconds: 10),
    this.showAppBar = true,
    this.title,
    this.autoStart = true,
    super.key,
  });

  @override
  State<BluetoothScanPage> createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  bool _isScanning = false;
  ScanType? _scanType;
  final List<SimpleDevice> _devices = [];
  String _scanError = '';
  Offset _scanButtonPosition = const Offset(320, 600); // Position initiale
  StreamSubscription? _bleSub;
  StreamSubscription? _reactiveBleSub;
  final reactive.FlutterReactiveBle _reactiveBle =
      reactive.FlutterReactiveBle();

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _startScan();
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _reactiveBleSub?.cancel();
    super.dispose();
  }

  Future<void> _startScan({ScanType? forceType}) async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _devices.clear();
      _scanError = '';
      _scanType = null;
    });

    try {
      await _requestPermissions();

      // Choix du mode de scan
      ScanType scanType =
          forceType ??
          (await FlutterBluePlus.isAvailable && await FlutterBluePlus.isOn
              ? ScanType.ble
              : ScanType.reactiveBle);

      setState(() => _scanType = scanType);

      if (scanType == ScanType.ble) {
        await _scanBLE();
      } else {
        await _scanReactiveBle();
      }
    } catch (e) {
      setState(() => _scanError = 'Erreur de scan : $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (statuses.values.any((s) => !s.isGranted)) {
      throw 'Certaines permissions Bluetooth ou localisation sont manquantes.';
    }
  }

  Future<void> _scanBLE() async {
    _bleSub?.cancel();
    _devices.clear();

    _bleSub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        final id = r.device.remoteId.str;
        final name = r.device.advName.isNotEmpty
            ? r.device.advName
            : r.device.platformName;
        final rssi = r.rssi;
        if (!_devices.any((d) => d.id == id)) {
          setState(() {
            _devices.add(
              SimpleDevice(id: id, name: name, rssi: rssi, type: ScanType.ble),
            );
          });
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: widget.scanDuration);
    await Future.delayed(widget.scanDuration);
    await FlutterBluePlus.stopScan();
    await _bleSub?.cancel();
  }

  Future<void> _scanReactiveBle() async {
    _reactiveBleSub?.cancel();
    _devices.clear();

    _reactiveBleSub = _reactiveBle
        .scanForDevices(
          withServices: [],
          scanMode: reactive.ScanMode.lowLatency,
        )
        .listen(
          (device) {
            if (!_devices.any((d) => d.id == device.id)) {
              setState(() {
                _devices.add(
                  SimpleDevice(
                    id: device.id,
                    name: device.name.isNotEmpty
                        ? device.name
                        : 'Appareil inconnu',
                    rssi: device.rssi,
                    type: ScanType.reactiveBle,
                  ),
                );
              });
            }
          },
          onError: (e) {
            setState(() => _scanError = 'Erreur Reactive BLE : $e');
          },
        );

    await Future.delayed(widget.scanDuration);
    await _reactiveBleSub?.cancel();
  }

  void _onDeviceSelected(SimpleDevice device) {
    Navigator.pop(context, device);
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.title ??
        Text(
          'Scan Bluetooth',
          style: const TextStyle(fontWeight: FontWeight.bold),
        );
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: title,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isScanning
                      ? null
                      : () => _startScan(forceType: _scanType),
                  tooltip: 'Relancer le scan',
                ),
                PopupMenuButton<ScanType>(
                  onSelected: (type) => _startScan(forceType: type),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: ScanType.ble,
                      child: Text('BLE (flutter_blue_plus)'),
                    ),
                    const PopupMenuItem(
                      value: ScanType.reactiveBle,
                      child: Text('BLE (reactive_ble)'),
                    ),
                  ],
                  icon: const Icon(Icons.settings_bluetooth),
                  tooltip: 'Choisir le mode de scan',
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            _scanType == ScanType.ble
                ? 'Mode BLE (flutter_blue_plus)'
                : _scanType == ScanType.reactiveBle
                ? 'Mode BLE (reactive_ble)'
                : 'Détection automatique...',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_isScanning) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
          if (_scanError.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _scanError,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: DeviceListWidget(
              devices: _devices,
              onSelect: _onDeviceSelected,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      
    );
  }
}

// Widget réutilisable pour la liste des appareils Bluetooth
class DeviceListWidget extends StatelessWidget {
  final List<SimpleDevice> devices;
  final Function(SimpleDevice) onSelect;

  const DeviceListWidget({
    super.key,
    required this.devices,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const Center(child: Text('Aucun appareil trouvé.'));
    }
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final d = devices[index];
        return ListTile(
          leading: Icon(
            d.type == ScanType.ble
                ? Icons.bluetooth
                : Icons.bluetooth_searching,
            color: d.type == ScanType.ble ? Colors.blue : Colors.green,
          ),
          title: Text(d.name.isNotEmpty ? d.name : 'Nom inconnu'),
          subtitle: Text('${d.id}\nRSSI: ${d.rssi}'),
          onTap: () => onSelect(d),
        );
      },
    );
  }
}
