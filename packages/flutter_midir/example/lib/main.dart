import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_midir/flutter_midir.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMidi();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: MidiDemoPage());
}

class MidiDemoPage extends StatefulWidget {
  const MidiDemoPage({super.key});

  @override
  State<MidiDemoPage> createState() => _MidiDemoPageState();
}

class _MidiDemoPageState extends State<MidiDemoPage> {
  List<MidiPort> _ports = const [];
  final List<String> _log = [];
  StreamSubscription<Uint8List>? _sub;

  @override
  void initState() {
    super.initState();
    // Subscribe to the session event stream once.
    _sub = midiEvents().listen((bytes) {
      final hex = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      if (mounted) setState(() => _log.insert(0, 'RECV ${bytes.length}: $hex'));
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final ports = await listMidiPorts();
    if (mounted) setState(() => _ports = ports);
  }

  Future<void> _openAndQuery() async {
    try {
      // Match the pedal by name substring; one connection at a time.
      await openMidiConnection(
        inputPortName: 'Smart Box',
        outputPortName: 'Smart Box',
      );
      // Request global settings; over USB MIDI the 8080 header is stripped.
      await sendMidi(_hexToBytes('F00B0900010000000201020100F7'));
    } catch (e) {
      if (mounted) setState(() => _log.insert(0, 'ERROR: $e'));
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  @override
  void dispose() {
    _sub?.cancel();
    closeMidiConnection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_midir demo'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAndQuery,
        label: const Text('Open Smart Box + query'),
        icon: const Icon(Icons.usb),
      ),
      body: ListView(
        children: [
          const ListTile(
            title: Text('MIDI ports',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final p in _ports)
            ListTile(
              dense: true,
              leading: Icon(
                p.direction == MidiDirection.input
                    ? Icons.input
                    : Icons.output,
              ),
              title: Text(p.name),
            ),
          const Divider(),
          const ListTile(
            title: Text('Received',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final line in _log)
            ListTile(
              dense: true,
              title: Text(line,
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
        ],
      ),
    );
  }
}
