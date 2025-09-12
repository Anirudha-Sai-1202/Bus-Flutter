import 'dart:convert';
import '../models/reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _remindersKey = 'reminders';
  
  // Save reminders to shared preferences
  static Future<void> saveReminders(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final remindersJson = reminders.map((r) => r.toJson()).toList();
    await prefs.setString(_remindersKey, json.encode(remindersJson));
  }
  
  // Load reminders from shared preferences
  static Future<List<Reminder>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final remindersJson = prefs.getString(_remindersKey);
    
    if (remindersJson == null) {
      return [];
    }
    
    final remindersList = json.decode(remindersJson) as List;
    return remindersList.map((r) => Reminder.fromJson(r)).toList();
  }
  
  // Add a new reminder
  static Future<void> addReminder(Reminder reminder) async {
    final reminders = await loadReminders();
    reminders.add(reminder);
    await saveReminders(reminders);
  }
  
  // Update an existing reminder
  static Future<void> updateReminder(Reminder updatedReminder) async {
    final reminders = await loadReminders();
    final index = reminders.indexWhere((r) => r.id == updatedReminder.id);
    
    if (index != -1) {
      reminders[index] = updatedReminder;
      await saveReminders(reminders);
    }
  }
  
  // Delete a reminder
  static Future<void> deleteReminder(int id) async {
    final reminders = await loadReminders();
    reminders.removeWhere((r) => r.id == id);
    await saveReminders(reminders);
  }
}
