import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reminder.dart';
import '../providers/reminder_provider.dart';
import 'add_reminder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportReminders,
          ),
          IconButton(
            icon: const Icon(Icons.upload),
            onPressed: _importReminders,
          ),
        ],
      ),
      body: Consumer<ReminderProvider>(
        builder: (context, reminderProvider, child) {
          final reminders = reminderProvider.reminders;
          if (reminders.isEmpty) {
            return const Center(
              child: Text(
                'No reminders yet. Add one!',
                style: TextStyle(fontSize: 18),
              ),
            );
          }

          return ListView.builder(
            itemCount: reminders.length,
            itemBuilder: (context, index) {
              final reminder = reminders[index];
              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: ListTile(
                  title: Text(
                    reminder.title,
                    style: TextStyle(
                      decoration: reminder.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reminder.description.isNotEmpty)
                        Text(reminder.description),
                      if (reminder.url != null && reminder.url!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 16, color: Colors.blue),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                reminder.url!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (reminder.attachmentPath != null &&
                          reminder.attachmentPath!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.attach_file,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                reminder.attachmentPath!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        'Due: ${reminder.dateTime.toLocal().toString().split('.')[0]}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  trailing: Checkbox(
                    value: reminder.isCompleted,
                    onChanged: (bool? value) {
                      context
                          .read<ReminderProvider>()
                          .toggleReminderCompletion(reminder.id);
                    },
                  ),
                  onTap: () {
                    // Show reminder details or edit
                  },
                  onLongPress: () {
                    // Delete reminder
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Delete Reminder'),
                          content: Text(
                              'Are you sure you want to delete "${reminder.title}"?'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                context
                                    .read<ReminderProvider>()
                                    .deleteReminder(reminder.id);
                                Navigator.of(context).pop();
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddReminderScreen(),
            ),
          );

          if (result != null && result is Reminder) {
            context.read<ReminderProvider>().addReminder(
              title: result.title,
              description: result.description,
              dateTime: result.dateTime,
              url: result.url,
              attachmentPath: result.attachmentPath,
            );
          }
        },
        tooltip: 'Add Reminder',
        child: const Icon(Icons.add),
      ),
    );
  }

  _exportReminders() {
    // For simplicity, we'll show a snackbar with the export data
    final reminders = context.read<ReminderProvider>().reminders;
    if (reminders.isNotEmpty) {
      final exportData = reminders.map((r) => r.toJson()).toList();
      final exportString = exportData.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export data: $exportString'),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No reminders to export')),
      );
    }
  }

  _importReminders() {
    // For simplicity, we'll show a dialog to paste import data
    TextEditingController importController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Import Reminders'),
          content: TextField(
            controller: importController,
            decoration: const InputDecoration(
              hintText: 'Paste exported data here',
            ),
            maxLines: 5,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (importController.text.isNotEmpty) {
                  try {
                    // In a real implementation, you would parse the data properly
                    // This is a simplified version for demonstration
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Import functionality would be implemented here')),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to import reminders')),
                    );
                  }
                }
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }
}
