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


// version 1 
  Future<void> _sendToAnki(String front, String back, String translation) async {
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
            "Back": "$back  $translation",
          },
          "options": {
            "allowDuplicate": false
          },
          "tags": ["fromFlutter"]
        }
      }
    };

    final body2 = {
      "action": "addNote",
      "version": 6,
      "params": {
        "note": {
          "deckName": deckController.text,
          "modelName": "Basic",
          "fields": {
            "Front": translation,
            "Back": "$front  $back",
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

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body2),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        _showMessage("✅ Added: $translation → $front (id ${res['result']})");
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


  // version 2 of sending notes to Anki with offline support
  Future<void> addNote(String front, String back, String translation) async {
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
            "Back": "$back  $translation",
          },
          "options": {
            "allowDuplicate": false
          },
          "tags": ["fromFlutter"]
        }
      }
    };

    final body2 = {
      "action": "addNote",
      "version": 6,
      "params": {
        "note": {
          "deckName": deckController.text,
          "modelName": "Basic",
          "fields": {
            "Front": translation,
            "Back": "$front  $back",
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
        throw Exception("Failed to add note");
      }
    } catch (e) {
      // On failure, save note locally
      final pendingNote = PendingNote(front, "$back  $translation");
      await pendingBox.add(pendingNote.toJson());
      _showMessage("⚠️ Could not connect. Note saved for later.");
    }

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body2),
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        _showMessage("✅ Added: $translation → $front (id ${res['result']})");
      } else {
        _showMessage("Error: ${response.statusCode}");
        throw Exception("Failed to add note");
      }
    } catch (e) {
      // On failure, save note locally
      final pendingNote = PendingNote(translation, "$front  $back");
      await pendingBox.add(pendingNote.toJson());
      _showMessage("⚠️ Could not connect. Note saved for later.");
    }
  
      
   
    setState(() {}); // ✅ Forces refresh count
    
  }

Future<void> syncPendingNotes() async {
  final notes = pendingBox.values.toList();

  for (int i = 0; i < notes.length; i++) {
    final note = notes[i] as Map<String, dynamic>; // ✅ cast

    final body = {
      "action": "addNote",
      "version": 6,
      "params": {
        "note": {
          "deckName": deckController.text,
          "modelName": "Basic",
          "fields": {
            "Front": note["front"],
            "Back": note["back"],
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

      // Success → remove from pending
      await pendingBox.deleteAt(i);
    } catch (e) {
      print("Failed to sync note ${note["front"]}: $e");
      break; // stop on first failure
    }
  }

  setState(() {}); // refresh UI
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
