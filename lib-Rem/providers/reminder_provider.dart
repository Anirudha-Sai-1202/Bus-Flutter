import 'package:flutter/foundation.dart';
import '../models/reminder.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';

class ReminderProvider with ChangeNotifier {
  List<Reminder> _reminders = [];
  bool _isLoading = false;
  
  List<Reminder> get reminders => _reminders;
  bool get isLoading => _isLoading;
  
  // Load reminders from storage
  Future<void> loadReminders() async {
    _isLoading = true;
    notifyListeners();
    
    _reminders = await StorageService.loadReminders();
    _isLoading = false;
    notifyListeners();
  }
  
  // Add a new reminder
  Future<void> addReminder({
    required String title,
    required String description,
    required DateTime dateTime,
    String? url,
    String? attachmentPath,
  }) async {
    final newReminder = Reminder(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      description: description,
      dateTime: dateTime,
      url: url,
      attachmentPath: attachmentPath,
    );
    
    await StorageService.addReminder(newReminder);
    await NotificationService().scheduleNotification(
      id: newReminder.id,
      title: 'Reminder',
      body: newReminder.title,
      scheduledTime: newReminder.dateTime,
    );
    
    await loadReminders(); // Reload to ensure consistency
  }
  
  // Update a reminder
  Future<void> updateReminder(Reminder updatedReminder) async {
    await StorageService.updateReminder(updatedReminder);
    
    // Cancel existing notification and schedule new one
    await NotificationService().cancelNotification(updatedReminder.id);
    if (!updatedReminder.isCompleted) {
      await NotificationService().scheduleNotification(
        id: updatedReminder.id,
        title: 'Reminder',
        body: updatedReminder.title,
        scheduledTime: updatedReminder.dateTime,
      );
    }
    
    await loadReminders(); // Reload to ensure consistency
  }
  
  // Delete a reminder
  Future<void> deleteReminder(int id) async {
    await StorageService.deleteReminder(id);
    await NotificationService().cancelNotification(id);
    await loadReminders(); // Reload to ensure consistency
  }
  
  // Toggle reminder completion status
  Future<void> toggleReminderCompletion(int id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    
    if (index != -1) {
      final updatedReminder = _reminders[index].copyWith(
        isCompleted: !_reminders[index].isCompleted,
      );
      
      await updateReminder(updatedReminder);
    }
  }
}
