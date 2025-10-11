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
  final debugController = TextEditingController(text: "debug");
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


  void _showMessage(String msg) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    });
  }


  // version 2 of sending notes to Anki with offline support
  Future<void> addNote(String front, String back, String translation) async {
    final url = Uri.parse('http://${ipController.text}:8765');

    // Create two notes, each with a unique timestamp to avoid duplicate detection
    final timestamp = DateTime.now().millisecondsSinceEpoch;

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
        print("⚠️ Could not connect. Note saved for later.");
         print("⚠️ Could not connect. Note saved for later.");
          print("⚠️ Could not connect. Note saved for later.");
           print("⚠️ Could not connect. Note saved for later.");
            print("⚠️ Could not connect. Note saved for later.");
             print("⚠️ Could not connect. Note saved for later.");
              print("⚠️ Could not connect. Note saved for later.");

      }
    }

    await sendOrSave(note1);
    await sendOrSave(note2);

  }

Future<void> syncPendingNotes() async {
  final notes = pendingBox.values.toList(); // copy values to avoid issues while deleting
  if (notes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ No pending notes")),
    );
    return;
  }

  print("=== [SYNC STARTED] Found ${notes.length} pending notes ===");

  for (final noteObj in notes) {
    final note = noteObj as Map<String, dynamic>; // cast Hive value
    final front = note["front"];
    final back = note["back"];

    final body = {
      "action": "addNote",
      "version": 6,
      "params": {
        "note": {
          "deckName": deckController.text,
          "modelName": "Basic",
          "fields": {
            "Front": front,
            "Back": back,
          },
          "options": {"allowDuplicate": false},
        }
      }
    };

    try {
      final response = await http.post(
        Uri.parse('http://${ipController.text}:8765'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (data["error"] != null) throw Exception(data["error"]);

      // Success → remove note from Hive
      final key = pendingBox.keys.firstWhere(
        (k) => pendingBox.get(k) == noteObj,
        orElse: () => null,
      );
      if (key != null) await pendingBox.delete(key);

      print("✅ Synced note: $front → $back");
    } catch (e) {
      print("❌ Failed to sync note: $front → $back : $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Could not sync note: $front")),
      );
      return; // stop on first failure
    }
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("✅ All pending notes synced")),
  );
  setState(() {}); // refresh UI
  print("=== [SYNC COMPLETE] All pending notes synced ===");
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
              onPressed: () async {
                await syncPendingNotes();
                setState(() {}); // can rebuild after
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
                     setState(() {});          // can rebuild after
                  }
                },
                child: const Text("Send to Anki"),
              ),
              const SizedBox(height: 20),
              Expanded(
                child:  ValueListenableBuilder(
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
}
