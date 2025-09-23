import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  runApp(const AnkiShareApp());
}

class AnkiShareApp extends StatefulWidget {
  const AnkiShareApp({super.key});

  @override
  State<AnkiShareApp> createState() => _AnkiShareAppState();
}

class _AnkiShareAppState extends State<AnkiShareApp> {
  String? sharedText;
  final ipController = TextEditingController(text: "172.23.240.1"); 
  final deckController = TextEditingController(text: "Default");

  @override
  void initState() {
    super.initState();

    // Listen for shared text
    ReceiveSharingIntent.getTextStream().listen((String value) {
      setState(() {
        sharedText = value;
      });
      _sendToAnki(value);
    }, onError: (err) {
      print("getLinkStream error: $err");
    });

    // Get initial shared text if app is launched via Share
    ReceiveSharingIntent.getInitialText().then((String? value) {
      if (value != null) {
        setState(() {
          sharedText = value;
        });
        _sendToAnki(value);
      }
    });
  }

  Future<void> _sendToAnki(String word) async {
    final url = Uri.parse('http://${ipController.text}:8765');
    final body = {
      "action": "addNote",
      "version": 6,
      "key": "123Soleil",
      "params": {
        "note": {
          "deckName": deckController.text,
          "modelName": "Basic",
          "fields": {
            "Front": word,
            "Back": ""
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
        _showMessage("Added: $word ✅ (id ${res['result']})");
      } else {
        _showMessage("Error: ${response.statusCode}");
      }
    } catch (e) {
      _showMessage("Failed to connect: $e");
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anki Share',
      home: Scaffold(
        appBar: AppBar(title: const Text("Anki Share")),
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
              if (sharedText != null)
                Text("Last shared: $sharedText",
                    style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (sharedText != null) _sendToAnki(sharedText!);
                },
                child: const Text("Send Again"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
