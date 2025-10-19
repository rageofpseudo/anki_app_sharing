import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox("pendingNotes");
  runApp(const AnkiShareApp());
}

class AnkiShareApp extends StatelessWidget {
  const AnkiShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Hive.openBox("pendingNotes"),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return MaterialApp(
            home: ScaffoldMessenger(
              child: const _MainApp(),
            ),
          );
        }
        return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _MainApp extends StatefulWidget {
  const _MainApp({super.key});

  @override
  State<_MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<_MainApp> {
  final ipController = TextEditingController(text: "10.192.51.198");
  final deckController = TextEditingController(text: "Default");
  final frontController = TextEditingController();
  final backController = TextEditingController();
  final translationController = TextEditingController();
  late Box pendingBox;

  @override
  void initState() {
    super.initState();
    pendingBox = Hive.box("pendingNotes");

    // auto sync on app start
    syncPendingNotes();
    
    // Listen for shared media (text or files)
    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        setState(() {
          frontController.text = value.first.path;
        });
      }
    }, onError: (err) {
      print("getMediaStream error: $err");
    });

    // Get initial shared media if app is launched via Share
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        setState(() {
          frontController.text = value.first.path;
        });
      }
    });
  }

  Future<void> autoDetectAnkiConnect() async {
    const port = 8765;
    final subnet = "192.168.1"; // adjust if needed (could make dynamic)
    bool found = false;

    for (int i = 1; i < 255 && !found; i++) {
      final ip = "$subnet.$i";
      try {
        final url = Uri.parse("http://$ip:$port");
        final response = await http
            .post(url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"action": "version", "version": 6}))
            .timeout(const Duration(milliseconds: 400));

        if (response.statusCode == 200) {
          setState(() => ipController.text = ip);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Found AnkiConnect at $ip")),
          );
          found = true;
        }
      } catch (_) {}
    }

    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Could not find AnkiConnect")),
      );
    }
  }

  void _showMessage(String msg) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  Future<void> addNote(String front, String back, String translation) async {
    final url = Uri.parse('http://${ipController.text}:8765');

    final note1 = {
      "deckName": deckController.text,
      "modelName": "Basic",
      "fields": {
        "Front": front,
        "Back": "$back<br><br>$translation",
      },
      "options": {"allowDuplicate": false},
      "tags": ["fromFlutter"]
    };

    final note2 = {
      "deckName": deckController.text,
      "modelName": "Basic",
      "fields": {
        "Front": translation,
        "Back": "$front<br><br>$back",
      },
      "options": {"allowDuplicate": false},
      "tags": ["fromFlutter"]
    };

    Future<void> sendOrSave(Map<String, dynamic> note) async {
      try {
        final response = await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"action": "addNote", "version": 6, "params": {"note": note}}),
        );

        if (response.statusCode != 200) {
          throw Exception("HTTP ${response.statusCode}");
        }

        final data = jsonDecode(response.body);
        if (data["error"] != null) throw Exception(data["error"]);

        _showMessage("✅ Added: ${note['fields']['Front']}");
      } catch (e) {
        // Save note locally if failed
        await pendingBox.add(note);
        _showMessage("⚠️ Could not connect. Note saved for later.");
        print("⚠️ Could not connect. Note saved for later: $e");
      }
    }

    await sendOrSave(note1);
    await sendOrSave(note2);
  }

  Future<void> syncPendingNotes() async {
    final notes = pendingBox.values.toList();
    if (notes.isEmpty) {
      print("✅ No pending notes to sync");
      return;
    }

    print("=== [SYNC STARTED] Found ${notes.length} pending notes ===");

    final List<int> keysToDelete = [];
    int syncedCount = 0;
    int failedCount = 0;

    for (int i = 0; i < notes.length; i++) {
      final noteObj = notes[i];
      final note = noteObj as Map<String, dynamic>;
      final front = note["fields"]?["Front"] ?? "Unknown";
      final back = note["fields"]?["Back"] ?? "";

      final body = {
        "action": "addNote",
        "version": 6,
        "params": {
          "note": note
        }
      };

      try {
        final response = await http.post(
          Uri.parse('http://${ipController.text}:8765'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 5));

        final data = jsonDecode(response.body);
        if (data["error"] != null) throw Exception(data["error"]);

        keysToDelete.add(i);
        syncedCount++;
        print("✅ Synced note: $front");
      } catch (e) {
        failedCount++;
        print("❌ Failed to sync note: $front : $e");
      }
    }

    // Delete synced notes
    for (int i = keysToDelete.length - 1; i >= 0; i--) {
      final key = pendingBox.keyAt(keysToDelete[i]);
      await pendingBox.delete(key);
    }

    _showMessage("✅ Synced $syncedCount notes (${failedCount} failed)");
    setState(() {});
    print("=== [SYNC COMPLETE] Synced: $syncedCount, Failed: $failedCount ===");
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anki Share',
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Anki Share"),
          actions: [
            IconButton(
                icon: const Icon(Icons.search),
                tooltip: "Auto-detect Anki IP",
                onPressed: autoDetectAnkiConnect,
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () async {
                await syncPendingNotes();
                setState(() {});
              },
              tooltip: "Sync Pending Notes",
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () async {
                await pendingBox.clear();
                setState(() {});
                _showMessage("🗑️ Cleared all pending notes.");
              },
              tooltip: "Clear Pending Notes",
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                  controller: ipController,
                  decoration: const InputDecoration(labelText: "AnkiConnect IP"),
              ),
              TextField(
                controller: deckController,
                decoration: const InputDecoration(labelText: "Deck Name"),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: frontController,
                decoration: const InputDecoration(labelText: "Hanzi"),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: backController,
                decoration: const InputDecoration(labelText: "Pinyin"),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: translationController,
                decoration: const InputDecoration(labelText: "Translation"),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              if (frontController.text.isNotEmpty)
                Text("Last shared: ${frontController.text}",
                    style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (frontController.text.isNotEmpty) {
                    await addNote(frontController.text, backController.text, translationController.text);
                    setState(() {});
                  }
                },
                child: const Text("Send to Anki"),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: pendingBox.listenable(),
                  builder: (context, box, _) {
                    return Text(
                      "Pending notes: ${box.length}",
                      style: const TextStyle(fontSize: 16),
                    );
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ipController.dispose();
    deckController.dispose();
    frontController.dispose();
    backController.dispose();
    translationController.dispose();
    super.dispose();
  }
}