class PendingNote {
  final String front;
  final String back;

  PendingNote(this.front, this.back);

  Map<String, dynamic> toJson() => {
        "front": front,
        "back": back,
      };

  factory PendingNote.fromJson(Map<String, dynamic> json) =>
      PendingNote(json["front"], json["back"]);
}
