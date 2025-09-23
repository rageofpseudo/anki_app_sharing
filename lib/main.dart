import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'pending_note.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  final frontController = TextEditingController(); // recto
  final backController = TextEditingController(); // verso
  late Box pendingBox;

  @override
  void initState() {
    super.initState();
    pendingBox = Hive.box("pendingNotes");

    // auto sync on app start
     _syncPending();
    // Listen for shared media (text or files)
    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.type == SharedMediaType.text) {
        setState(() {
          frontController.text = value.first.path; 
        });
        //_sendToAnki(value.first.path);
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
        //_sendToAnki(value.first.path);
      }
    });
  }

  Future<void> _sendToAnki(String front, String back) async {
    final url = Uri.parse('http://${ipController.text}:8765');
    final body = {
      "action": "addNote",
      "version": 6,
      "params": {
        "note": {
          "deckName": deckController.text,
          "modelName": "Basic",
          "fields": {
            "Front": front,
            "Back": back
          },
          "options": {
            "allowDuplicate": false
          },
          "tags": ["fromFlutter"]
        }
      }
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        _showMessage("✅ Added: $front → $back (id ${res['result']})");
      } else {
        _showMessage("Error: ${response.statusCode}");
      }
    } catch (e) {
      _showMessage("Failed to connect: $e");
    }
  }

  void _showMessage(String msg) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  Future<void> _queueOrSend(String front, String back) async {
    try {
      await _sendToAnki(front, back);
    } catch (e) {
      // Save locally if sending failed
      final note = {"front": front, "back": back};
      await pendingBox.add(note);
      _showMessage("⚠️ Anki not available. Saved locally.");
    }
  }  

  Future<void> _syncPending() async {
    final keys = pendingBox.keys.toList(); // stable list of keys
    for (final key in keys) {
      final note = pendingBox.get(key) as Map;
      try {
        await _sendToAnki(note["front"], note["back"]);
        await pendingBox.delete(key);
        _showMessage("✅ Synced: ${note["front"]}");
      } catch (_) {
        _showMessage("❌ Still can’t reach Anki.");
        break; // stop trying if still offline
      }
    }
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
              icon: const Icon(Icons.sync),
              onPressed: _syncPending,
              tooltip: "Sync Pending Notes",
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
                decoration: const InputDecoration(labelText: "Front (Recto)"),
              ),
              TextField(
                controller: backController,
                decoration: const InputDecoration(labelText: "Back (Verso)"),
              ),

              if (frontController.text.isNotEmpty)
                Text("Last shared: ${frontController.text}",
                    style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (frontController.text.isNotEmpty) _queueOrSend(frontController.text, backController.text);
                },
                child: const Text("Send to Anki"),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: pendingBox.listenable(),
                  builder: (context, box, _) {
                    final notes = box.values.toList();
                    if (notes.isEmpty) {
                      return const Text("✅ No pending notes");
                    }
                    return ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, i) {
                        final note = notes[i] as Map;
                        return ListTile(
                          title: Text(note["front"]),
                          subtitle: Text(note["back"]),
                        );
                      },
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
}
