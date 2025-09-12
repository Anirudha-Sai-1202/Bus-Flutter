class Reminder {
  final int id;
  final String title;
  final String description;
  final DateTime dateTime;
  final bool isCompleted;
  final String? url;
  final String? attachmentPath;

  Reminder({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    this.isCompleted = false,
    this.url,
    this.attachmentPath,
  });

  Reminder copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? dateTime,
    bool? isCompleted,
    String? url,
    String? attachmentPath,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      isCompleted: isCompleted ?? this.isCompleted,
      url: url ?? this.url,
      attachmentPath: attachmentPath ?? this.attachmentPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dateTime': dateTime.toIso8601String(),
      'isCompleted': isCompleted,
      'url': url,
      'attachmentPath': attachmentPath,
    };
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      dateTime: DateTime.parse(json['dateTime']),
      isCompleted: json['isCompleted'] ?? false,
      url: json['url'],
      attachmentPath: json['attachmentPath'],
    );
  }
}
