import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings.dart';
import '../services/settings_store.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    state = await SettingsStore.load();
  }

  Future<void> update(AppSettings settings) async {
    state = settings;
    await SettingsStore.save(settings);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
        (ref) => SettingsNotifier());
