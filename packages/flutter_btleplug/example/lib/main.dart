import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_btleplug/flutter_btleplug.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBle();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Uint8List>? _sub;
  List<BleDevice> _devices = const [];
  String _status = 'idle';
  final _rx = <String>[];

  @override
  void initState() {
    super.initState();
    _sub = bleEvents().listen((bytes) {
      setState(() {
        _rx.insert(
          0,
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        );
        if (_rx.length > 8) _rx.removeLast();
      });
    });
  }

  Future<void> _scan() async {
    setState(() => _status = 'scanning…');
    final d = await scanBle();
    setState(() {
      _devices = d;
      _status = '${d.length} devices';
    });
  }

  Future<void> _connectAndQuery(String name) async {
    setState(() => _status = 'connecting $name…');
    try {
      await connectBle(name: name);
      // Request state (full 8080..F7 frame, header included over BLE-MIDI).
      await sendBle(_hex('8080F0000900010000000201020401F7'));
      setState(() => _status = 'connected $name');
    } catch (e) {
      setState(() => _status = 'error: $e');
    }
  }

  Uint8List _hex(String s) => Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
  ]);

  @override
  void dispose() {
    _sub?.cancel();
    disconnectBle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_btleplug demo')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  FilledButton(onPressed: _scan, child: const Text('Scan')),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final d in _devices)
                    ListTile(
                      title: Text(d.name.isEmpty ? '(unnamed)' : d.name),
                      subtitle: Text('${d.address}  rssi ${d.rssi}'),
                      onTap: () => _connectAndQuery(d.name),
                    ),
                  const Divider(),
                  for (final r in _rx)
                    ListTile(dense: true, title: Text('RX $r')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
